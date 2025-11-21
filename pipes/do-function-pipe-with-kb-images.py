"""
title: Digital Ocean Function Pipe with KB Image Support
author: open-webui
date: 2025-01-12
version: 8.1.0
license: MIT
description: Full-featured DO pipe with automatic image URL extraction and display from knowledge base responses
required_open_webui_version: 0.3.9
requirements: requests

KEY FEATURES:
- JSON-aware task handling (title/follow-up generation)
- Streaming and non-streaming support
- Optional system notification on first response
- **Automatic image URL detection from agent responses**
- **Smart deduplication prevents duplicate images** (always enabled)
- Extracts DO Spaces URLs (public and presigned) from text
- Displays images as markdown at end of response
- Works with OpenSearch knowledge base image metadata

HOW IT WORKS:
1. DO agent queries OpenSearch knowledge base
2. Retrieves chunks with image_url in metadata
3. Agent includes image URLs in response text (e.g., "See chart at https://...")
4. Pipe extracts URLs using regex pattern
5. Pipe checks if URLs are already embedded by agent (smart deduplication)
6. Converts non-embedded URLs to markdown images
7. Appends images to response (no duplicates)

CONFIGURATION:
- ENABLE_KB_IMAGE_DETECTION: Toggle automatic image detection (default: True)
- IMAGE_URL_PATTERN: Regex for detecting image URLs (default: DO Spaces URLs)
- MAX_IMAGES_PER_RESPONSE: Limit number of images displayed (default: 10)

Note: Smart deduplication is always enabled - images embedded by the agent will not be duplicated.
"""

from __future__ import annotations

import json
import os
import re
import time
import uuid
from typing import Any, Dict, List, Optional, Union, Generator, Iterator

import requests
from pydantic import BaseModel, Field

# Import TASKS from Open WebUI if available
try:
    from open_webui.constants import TASKS
except ImportError:
    # Fallback if running outside Open WebUI
    class TASKS:
        TITLE_GENERATION = "title_generation"
        FOLLOW_UP_GENERATION = "follow_up_generation"


class Pipe:
    class Valves(BaseModel):
        DIGITALOCEAN_FUNCTION_URL: str = Field(
            default="https://your-digitalocean-agent-url.do-ai.run",
            description="Digital Ocean agent endpoint URL (without /api/v1/chat/completions)"
        )
        DIGITALOCEAN_FUNCTION_TOKEN: str = Field(
            default="your-digitalocean-token-here",
            description="Digital Ocean agent access token"
        )
        REQUEST_TIMEOUT_SECONDS: float = Field(
            default=120.0,
            description="Request timeout in seconds"
        )
        VERIFY_SSL: bool = Field(
            default=True,
            description="Verify SSL certificates"
        )
        ENABLE_STREAMING: bool = Field(
            default=True,
            description="Enable streaming responses for regular chat"
        )
        ENABLE_SYSTEM_NOTIFICATION: bool = Field(
            default=False,
            description="Show system notification on first assistant response"
        )
        SYSTEM_NOTIFICATION_MESSAGE: str = Field(
            default="Note: This assistant is still learning and may occasionally miss details or make incorrect connections.",
            description="Custom system notification message to display on first response"
        )
        ENABLE_KB_IMAGE_DETECTION: bool = Field(
            default=True,
            description="Automatically detect and display images from knowledge base URLs in agent responses"
        )
        IMAGE_URL_PATTERN: str = Field(
            default=r"https://[a-zA-Z0-9\-]+\.(?:nyc3|sfo3|ams3|sgp1|fra1|blr1|lon1|tor1)\.digitaloceanspaces\.com/[^\s\)\"\'>]+\.(?:png|jpg|jpeg|gif|webp|PNG|JPG|JPEG|GIF|WEBP)",
            description="Regex pattern for detecting image URLs in agent responses. Default matches DO Spaces URLs with common extensions and presigned URL parameters."
        )
        MAX_IMAGES_PER_RESPONSE: int = Field(
            default=10,
            description="Maximum number of images to display per response"
        )
        DEBUG_MODE: bool = Field(
            default=False,
            description="Enable debug logging to help diagnose issues"
        )

    def __init__(self) -> None:
        self.type = "pipe"
        self.id = "do_function_pipe_kb_images"
        self.name = "DO Function Pipe (KB Images)"
        self.valves = self.Valves()

    # Main entry point ---------------------------------------------------
    def pipe(
        self,
        body: Dict[str, Any],
        __task__: Optional[str] = None,
        __task_body__: Optional[Dict[str, Any]] = None,
        __metadata__: Optional[Dict[str, Any]] = None,
        __user__: Optional[Dict[str, Any]] = None,
        **kwargs: Any,
    ) -> Union[Dict[str, Any], Iterator, str]:
        """
        Main pipe entry point. Handles both regular chat and task model operations.
        """

        # Check if this is a task model call
        if __task__ is not None:
            return self._handle_task_model_call(
                body=body,
                task=__task__,
                task_body=__task_body__,
                metadata=__metadata__,
                user=__user__,
                extras=kwargs,
            )

        # Regular chat completion
        return self._handle_chat_completion(
            body=body,
            metadata=__metadata__,
            user=__user__,
            extras=kwargs,
        )

    # Task Model Handling ------------------------------------------------
    def _handle_task_model_call(
        self,
        body: Dict[str, Any],
        task: str,
        task_body: Optional[Dict[str, Any]],
        metadata: Optional[Dict[str, Any]],
        user: Optional[Dict[str, Any]],
        extras: Dict[str, Any],
    ) -> str:
        """Handle task model operations (title/follow-up generation)."""

        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] Task model call: {task}")

        # Invoke the DO agent with task-specific prompts
        raw_response = self._invoke_function(
            body=body,
            task=task,
            task_body=task_body,
            metadata=metadata,
            user=user,
            extras=extras,
        )

        # Extract content from the OpenAI-format response
        content = ""
        if isinstance(raw_response, dict) and "choices" in raw_response:
            choices = raw_response.get("choices", [])
            if choices and isinstance(choices[0], dict):
                message = choices[0].get("message", {})
                content = message.get("content", "")

        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] DO agent response content: {content[:200] if content else 'None'}")

        # Format the response based on task type
        if task == str(TASKS.TITLE_GENERATION):
            title = self._extract_title(content, task_body)
            json_result = json.dumps({"title": title})

            if self.valves.DEBUG_MODE:
                print(f"[DEBUG] Returning title JSON: {json_result}")

            return json_result

        elif task == str(TASKS.FOLLOW_UP_GENERATION):
            follow_ups = self._extract_follow_ups(content, task_body)
            json_result = json.dumps({"follow_ups": follow_ups})

            if self.valves.DEBUG_MODE:
                print(f"[DEBUG] Returning follow-ups JSON: {json_result}")

            return json_result

        # Unknown task type
        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] Unknown task type: {task}")

        return "{}"

    def _extract_title(self, content: str, task_body: Optional[Dict[str, Any]]) -> str:
        """Extract title from DO agent response (JSON or plain text)."""
        if not content:
            return self._fallback_title(task_body)

        content = content.strip()

        # Try parsing as JSON first
        try:
            json_start = content.find("{")
            json_end = content.rfind("}") + 1

            if json_start != -1 and json_end > json_start:
                json_str = content[json_start:json_end]
                parsed = json.loads(json_str)

                if "title" in parsed:
                    title = parsed["title"]
                    if self.valves.DEBUG_MODE:
                        print(f"[DEBUG] Extracted title from JSON: {title}")
                    return title
        except Exception as e:
            if self.valves.DEBUG_MODE:
                print(f"[DEBUG] JSON parsing failed: {e}")

        # Fallback: treat entire content as title
        title = content

        # Remove quotes if present
        if title and title[0] == '"' and title[-1] == '"':
            title = title[1:-1]

        # Limit length
        if len(title) > 100:
            title = title[:97] + "..."

        if not title:
            title = self._fallback_title(task_body)

        return title

    def _extract_follow_ups(self, content: str, task_body: Optional[Dict[str, Any]]) -> List[str]:
        """Extract follow-up questions from DO agent response (JSON or plain text)."""
        if not content:
            return self._fallback_follow_ups(task_body)

        content = content.strip()

        # Try parsing as JSON first
        try:
            json_start = content.find("{")
            json_end = content.rfind("}") + 1

            if json_start != -1 and json_end > json_start:
                json_str = content[json_start:json_end]
                parsed = json.loads(json_str)

                if "follow_ups" in parsed and isinstance(parsed["follow_ups"], list):
                    follow_ups = parsed["follow_ups"]
                    if self.valves.DEBUG_MODE:
                        print(f"[DEBUG] Extracted follow-ups from JSON: {follow_ups}")
                    return follow_ups[:5]  # Limit to 5
        except Exception as e:
            if self.valves.DEBUG_MODE:
                print(f"[DEBUG] JSON parsing failed: {e}, falling back to line parsing")

        # Fallback: parse as plain text lines
        follow_ups = []
        lines = content.split('\n')

        for line in lines:
            # Remove numbering, bullets, and clean up
            cleaned = re.sub(r"^\d+[\.\)\-:]*\s*", "", line.strip())
            cleaned = re.sub(r"^[\-\*\u2022]+\s*", "", cleaned)
            cleaned = cleaned.strip()

            # Skip empty lines and JSON artifacts
            if cleaned and len(cleaned) > 5 and not cleaned.startswith("{") and not cleaned.startswith("["):
                follow_ups.append(cleaned)

            if len(follow_ups) >= 5:
                break

        # Use fallback if no follow-ups found
        if not follow_ups:
            follow_ups = self._fallback_follow_ups(task_body)

        return follow_ups

    # Regular Chat Handling ----------------------------------------------
    def _handle_chat_completion(
        self,
        body: Dict[str, Any],
        metadata: Optional[Dict[str, Any]],
        user: Optional[Dict[str, Any]],
        extras: Dict[str, Any],
    ) -> Union[Dict[str, Any], Iterator]:
        """Handle regular chat completions with image detection."""

        if not self.valves.DIGITALOCEAN_FUNCTION_URL:
            raise ValueError("DIGITALOCEAN_FUNCTION_URL valve is not configured.")

        # Build the API URL
        api_url = f"{self.valves.DIGITALOCEAN_FUNCTION_URL.rstrip('/')}/api/v1/chat/completions"

        # Prepare payload
        payload = {
            "messages": body.get("messages", []),
            "stream": body.get("stream", False) and self.valves.ENABLE_STREAMING,
            "model": body.get("model", ""),
        }

        # Add optional parameters
        for param in ["temperature", "max_tokens", "top_p", "frequency_penalty", "presence_penalty"]:
            if param in body:
                payload[param] = body[param]

        headers = {
            "Authorization": f"Bearer {self.valves.DIGITALOCEAN_FUNCTION_TOKEN}",
            "Content-Type": "application/json",
        }

        try:
            response = requests.post(
                api_url,
                json=payload,
                headers=headers,
                timeout=self.valves.REQUEST_TIMEOUT_SECONDS,
                verify=self.valves.VERIFY_SSL,
                stream=payload["stream"]
            )
            response.raise_for_status()

            # Handle streaming
            if payload["stream"]:
                return self._stream_with_enhancements(response.iter_lines(), body)

            # Handle non-streaming
            response_data = response.json()
            response_data = self._add_enhancements_to_response(response_data, body)

            return response_data

        except requests.RequestException as exc:
            error_msg = f"DigitalOcean Agent request failed: {exc}"
            if hasattr(exc, 'response') and exc.response is not None:
                try:
                    error_detail = exc.response.json()
                    error_msg += f" - Details: {error_detail}"
                except:
                    error_msg += f" - Response: {exc.response.text[:500]}"
            raise RuntimeError(error_msg) from exc

    def _stream_with_enhancements(
        self,
        stream_iter: Iterator,
        request_body: Dict[str, Any]
    ) -> Iterator:
        """Wrap streaming response to add images and system notification."""

        # Count existing assistant messages
        messages = request_body.get("messages", [])
        assistant_count = len([m for m in messages if m.get("role") == "assistant"])

        # Collect response content for image extraction
        accumulated_content = []

        # Yield all chunks from the original stream
        for chunk in stream_iter:
            yield chunk

            # Try to extract content from streaming chunk
            if chunk:
                try:
                    # Decode if bytes
                    if isinstance(chunk, bytes):
                        chunk_str = chunk.decode('utf-8')
                    else:
                        chunk_str = chunk

                    # Remove SSE prefix
                    if chunk_str.startswith('data: '):
                        chunk_str = chunk_str[6:].strip()

                    # Skip special markers
                    if chunk_str in ['[DONE]', '']:
                        continue

                    # Parse JSON chunk
                    chunk_data = json.loads(chunk_str)
                    if "choices" in chunk_data and chunk_data["choices"]:
                        delta = chunk_data["choices"][0].get("delta", {})
                        content = delta.get("content", "")
                        if content:
                            accumulated_content.append(content)
                except:
                    pass  # Ignore parsing errors

        # Combine accumulated content
        full_response = "".join(accumulated_content)

        # Extract image URLs from the response
        image_urls = []
        if self.valves.ENABLE_KB_IMAGE_DETECTION and full_response:
            image_urls = self._extract_image_urls(full_response)

            if self.valves.DEBUG_MODE and image_urls:
                print(f"[DEBUG] Detected {len(image_urls)} image URLs in streaming response")

        # Add system notification if first message
        if assistant_count == 0 and self.valves.ENABLE_SYSTEM_NOTIFICATION:
            notification = f"\n\n{self.valves.SYSTEM_NOTIFICATION_MESSAGE}"
            yield self._create_streaming_chunk(notification)

            if self.valves.DEBUG_MODE:
                print("[DEBUG] Added system notification to streaming response")

        # Add images if detected
        if image_urls:
            image_markdown = self._format_images_as_markdown(image_urls)
            yield self._create_streaming_chunk(image_markdown)

            if self.valves.DEBUG_MODE:
                print(f"[DEBUG] Added {len(image_urls)} images to streaming response")

    def _create_streaming_chunk(self, content: str) -> bytes:
        """Create a properly formatted SSE chunk."""
        chunk_data = {
            "choices": [{
                "delta": {"content": content},
                "index": 0,
                "finish_reason": None
            }]
        }
        return f"data: {json.dumps(chunk_data)}\n\n".encode('utf-8')

    def _add_enhancements_to_response(
        self,
        response_data: Dict[str, Any],
        request_body: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Add system notification and images to non-streaming response."""

        # Count existing assistant messages
        messages = request_body.get("messages", [])
        assistant_count = len([m for m in messages if m.get("role") == "assistant"])

        # Extract original content
        original_content = ""
        if isinstance(response_data, dict) and "choices" in response_data:
            choices = response_data.get("choices", [])
            if choices and isinstance(choices[0], dict):
                message = choices[0].get("message", {})
                original_content = message.get("content", "")

        # Build enhanced content
        enhanced_content = original_content

        # Add system notification if first message
        if assistant_count == 0 and self.valves.ENABLE_SYSTEM_NOTIFICATION:
            notification = f"\n\n{self.valves.SYSTEM_NOTIFICATION_MESSAGE}"
            enhanced_content += notification

            if self.valves.DEBUG_MODE:
                print("[DEBUG] Added system notification to first assistant response")

        # Extract and add images
        if self.valves.ENABLE_KB_IMAGE_DETECTION and original_content:
            image_urls = self._extract_image_urls(original_content)

            if image_urls:
                image_markdown = self._format_images_as_markdown(image_urls)
                enhanced_content += image_markdown

                if self.valves.DEBUG_MODE:
                    print(f"[DEBUG] Added {len(image_urls)} images to response")

        # Update response with enhanced content
        if enhanced_content != original_content:
            response_data["choices"][0]["message"]["content"] = enhanced_content

        return response_data

    def _extract_image_urls(self, text: str) -> List[str]:
        """
        Extract image URLs from text using configured pattern.

        Supports:
        - Plain URLs in text
        - URLs in markdown links: [text](url)
        - URLs in markdown images: ![alt](url)
        - Presigned URLs with query parameters

        Smart deduplication (always enabled):
        - Automatically excludes URLs already embedded as markdown images (![...](url))
        - Only adds images that are mentioned but not displayed
        - Prevents duplicate images in the response
        """
        if not text:
            return []

        image_urls = []

        try:
            # Compile regex pattern from valve
            pattern = re.compile(self.valves.IMAGE_URL_PATTERN, re.IGNORECASE)

            # Find all matches
            matches = pattern.findall(text)

            # Detect URLs already embedded as markdown images (smart deduplication always enabled)
            # Pattern: ![any text](url)
            embedded_pattern = r'!\[.*?\]\((' + self.valves.IMAGE_URL_PATTERN + r')\)'
            embedded_matches = re.findall(embedded_pattern, text, re.IGNORECASE)
            embedded_urls = set(embedded_matches)

            if self.valves.DEBUG_MODE and embedded_urls:
                print(f"[DEBUG] Found {len(embedded_urls)} images already embedded in response")
                print(f"[DEBUG] Will skip these URLs to prevent duplicates")

            # Deduplicate while preserving order
            # Skip URLs that are already embedded as images
            seen = set()
            for url in matches:
                if url not in seen and url not in embedded_urls:
                    seen.add(url)
                    image_urls.append(url)

                    # Respect max images limit
                    if len(image_urls) >= self.valves.MAX_IMAGES_PER_RESPONSE:
                        break

            if self.valves.DEBUG_MODE:
                print(f"[DEBUG] Extracted {len(image_urls)} image URLs (after deduplication)")
                if image_urls:
                    print(f"[DEBUG] URLs to add: {image_urls[:3]}...")  # Show first 3

                    # Warn about potential hallucinated URLs (mixed doc IDs with timestamps)
                    for url in image_urls:
                        # Check if URL has timestamp pattern but negative doc_id (indicates possible hallucination)
                        if re.search(r'/docs/\d{8}_\d{6}/doc_-\d+', url):
                            print(f"[DEBUG] ⚠️  WARNING: Possible hallucinated URL detected: {url}")
                            print(f"[DEBUG]    Negative doc_id with timestamp path may indicate LLM combined chunks")

        except Exception as e:
            if self.valves.DEBUG_MODE:
                print(f"[DEBUG] Error extracting image URLs: {e}")

        return image_urls

    def _format_images_as_markdown(self, image_urls: List[str]) -> str:
        """Convert list of image URLs to markdown format."""
        if not image_urls:
            return ""

        markdown = "\n\n---\n### 📊 Referenced Images from Knowledge Base:\n\n"

        for idx, url in enumerate(image_urls, 1):
            # Extract filename from URL for description
            filename = url.split('/')[-1].split('?')[0]  # Remove query params

            # Create description from filename
            desc = filename.replace('_', ' ').replace('-', ' ').rsplit('.', 1)[0]
            desc = desc.title()  # Capitalize words

            markdown += f"**{idx}. {desc}**\n\n"
            markdown += f"![{desc}]({url})\n\n"

        return markdown

    # DigitalOcean invocation --------------------------------------------
    def _invoke_function(
        self,
        body: Dict[str, Any],
        task: Optional[str],
        task_body: Optional[Dict[str, Any]],
        metadata: Optional[Dict[str, Any]],
        user: Optional[Dict[str, Any]],
        extras: Dict[str, Any],
    ) -> Any:
        """Invoke the DigitalOcean agent using OpenAI-compatible API format."""

        if not self.valves.DIGITALOCEAN_FUNCTION_URL:
            raise ValueError("DIGITALOCEAN_FUNCTION_URL valve is not configured.")

        api_url = f"{self.valves.DIGITALOCEAN_FUNCTION_URL.rstrip('/')}/api/v1/chat/completions"

        # Modify messages for task operations
        messages = body.get("messages", [])

        if task == str(TASKS.TITLE_GENERATION):
            messages = [
                {"role": "system", "content": "Generate a brief, descriptive title for this conversation. Respond with just the title, no quotes or extra text."},
                *messages
            ]
        elif task == str(TASKS.FOLLOW_UP_GENERATION):
            messages = [
                {"role": "system", "content": "Generate 3-5 follow-up questions based on this conversation. Return them as a simple list, one per line."},
                *messages
            ]

        payload = {
            "messages": messages,
            "stream": False,  # Never stream for task operations
            "model": body.get("model", ""),
        }

        # Add optional parameters
        if "temperature" in body:
            payload["temperature"] = body["temperature"]
        if "max_tokens" in body:
            payload["max_tokens"] = body["max_tokens"]

        headers = {
            "Authorization": f"Bearer {self.valves.DIGITALOCEAN_FUNCTION_TOKEN}",
            "Content-Type": "application/json",
        }

        try:
            response = requests.post(
                api_url,
                json=payload,
                headers=headers,
                timeout=self.valves.REQUEST_TIMEOUT_SECONDS,
                verify=self.valves.VERIFY_SSL,
            )
            response.raise_for_status()
        except requests.RequestException as exc:
            error_msg = f"DigitalOcean Agent request failed: {exc}"
            if hasattr(exc, 'response') and exc.response is not None:
                try:
                    error_detail = exc.response.json()
                    error_msg += f" - Details: {error_detail}"
                except:
                    error_msg += f" - Response: {exc.response.text[:500]}"
            raise RuntimeError(error_msg) from exc

        try:
            return response.json()
        except ValueError:
            text = response.text.strip()
            return text if text else {}

    # Fallback helpers ---------------------------------------------------
    def _fallback_title(self, task_body: Optional[Dict[str, Any]]) -> str:
        """Generate a fallback title from the conversation."""
        if not task_body:
            return "New Chat"
        messages = task_body.get("messages") or []
        for message in reversed(messages):
            if isinstance(message, dict) and message.get("role") == "user":
                content = message.get("content")
                if isinstance(content, str) and content.strip():
                    title = content.strip()[:100]
                    title = re.sub(r'\s+', ' ', title)
                    return title
        return "New Chat"

    @staticmethod
    def _fallback_follow_ups(_task_body: Optional[Dict[str, Any]]) -> List[str]:
        """Generate fallback follow-up questions."""
        return []
