"""
title: Digital Ocean Pipe with Manual Image Mapping
author: open-webui
date: 2025-11-11
version: 7.0.0
license: MIT
description: DO pipe with keyword-based image display (no KB query required)
required_open_webui_version: 0.3.9
requirements: requests
"""

from typing import Dict, Any
from pydantic import BaseModel, Field
import requests


class Pipe:
    """DO pipe with keyword-based image detection."""

    class Valves(BaseModel):
        DIGITALOCEAN_FUNCTION_URL: str = Field(
            default="",
            description="Digital Ocean agent endpoint URL"
        )
        DIGITALOCEAN_FUNCTION_TOKEN: str = Field(
            default="",
            description="Digital Ocean agent access token"
        )
        ENABLE_IMAGE_DETECTION: bool = Field(
            default=True,
            description="Enable keyword-based image detection"
        )
        DEBUG_MODE: bool = Field(
            default=False,
            description="Enable debug logging"
        )

    # Image mapping: keywords -> image URLs
    IMAGE_MAP = {
        "revenue": {
            "url": "https://vtaufnxworztolfdwlll.supabase.co/storage/v1/object/public/pub_images/Revenue_Graphs.jpg",
            "description": "Quarterly revenue growth trends showing significant increase from Q1 to Q4",
            "keywords": ["revenue", "quarterly", "financial", "growth", "performance", "q1", "q2", "q3", "q4"]
        }
        # Add more images here as needed
    }

    def __init__(self):
        self.type = "pipe"
        self.id = "do_simple_working"
        self.name = "DO Pipe (Simple Working)"
        self.valves = self.Valves()

    def _debug_log(self, message: str):
        """Print debug message if debug mode is enabled."""
        if self.valves.DEBUG_MODE:
            print(f"[SIMPLE PIPE] {message}")

    def _detect_relevant_images(self, user_message: str) -> list:
        """
        Detect which images are relevant based on keywords in user message.
        """
        if not self.valves.ENABLE_IMAGE_DETECTION:
            return []

        user_lower = user_message.lower()
        relevant_images = []

        for image_key, image_info in self.IMAGE_MAP.items():
            # Check if any keyword matches
            for keyword in image_info["keywords"]:
                if keyword in user_lower:
                    self._debug_log(f"Matched keyword '{keyword}' for image: {image_key}")
                    relevant_images.append(image_info)
                    break  # Don't add the same image twice

        return relevant_images

    def _format_images(self, images: list) -> str:
        """Convert images to markdown."""
        if not images:
            return ""

        markdown = "\n\n---\n### 📷 Related Images:\n"

        for idx, img in enumerate(images, 1):
            desc = img["description"]
            url = img["url"]

            markdown += f"\n**{idx}. {desc}**\n"
            markdown += f"![{desc}]({url})\n"

        return markdown

    def _call_do_agent(self, body: dict) -> dict:
        """Call DO agent."""
        api_url = f"{self.valves.DIGITALOCEAN_FUNCTION_URL.rstrip('/')}/api/v1/chat/completions"

        headers = {
            "Authorization": f"Bearer {self.valves.DIGITALOCEAN_FUNCTION_TOKEN}",
            "Content-Type": "application/json",
        }

        payload = {
            "messages": body.get("messages", []),
            "stream": False,
            "model": body.get("model", ""),
        }

        for param in ["temperature", "max_tokens", "top_p"]:
            if param in body:
                payload[param] = body[param]

        try:
            response = requests.post(
                url=api_url,
                json=payload,
                headers=headers,
                timeout=120.0
            )

            response.raise_for_status()

            if not response.text:
                return {
                    "choices": [{
                        "message": {
                            "role": "assistant",
                            "content": "Error: Empty response"
                        },
                        "finish_reason": "error"
                    }]
                }

            return response.json()

        except Exception as e:
            self._debug_log(f"Error: {str(e)}")
            return {
                "choices": [{
                    "message": {
                        "role": "assistant",
                        "content": f"Error: {str(e)}"
                    },
                    "finish_reason": "error"
                }]
            }

    def pipe(
        self,
        body: dict,
        __task__: str = None,
        __task_body__: dict = None,
        __metadata__: dict = None,
        __user__: dict = None,
        **kwargs
    ) -> dict:
        """Main pipe entry point."""

        # Skip images for tasks
        if __task__ is not None:
            return self._call_do_agent(body)

        # Get user message
        messages = body.get("messages", [])
        user_message = ""
        for msg in reversed(messages):
            if msg.get("role") == "user":
                content = msg.get("content", "")
                if not content.startswith("### Task:"):
                    user_message = content
                    break

        self._debug_log(f"User: {user_message[:50]}...")

        # Call DO agent
        response_data = self._call_do_agent(body)

        # Extract agent response
        agent_response = ""
        if "choices" in response_data and response_data["choices"]:
            agent_response = response_data["choices"][0].get("message", {}).get("content", "")

        # Detect and add relevant images
        if self.valves.ENABLE_IMAGE_DETECTION and user_message:
            relevant_images = self._detect_relevant_images(user_message)

            if relevant_images:
                image_markdown = self._format_images(relevant_images)
                response_data["choices"][0]["message"]["content"] = agent_response + image_markdown
                self._debug_log(f"Added {len(relevant_images)} images")

        return response_data
