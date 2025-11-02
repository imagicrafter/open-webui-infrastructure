"""
Digital Ocean Knowledge Base Agent - JSON-Aware function pipe

This pipe handles the case where the DO agent returns JSON directly for task operations.

KEY FEATURES:
- DO agent returns '{"follow_ups": ["Q1", "Q2"]}' instead of plain text lines
- Pipe now tries JSON parsing FIRST, then falls back to text parsing
- Prevents double-nesting of JSON structures
- Optional system notification message on first response (toggle via valve)
- System notification works with BOTH streaming and non-streaming modes

Configuration:
1. Install this pipe in Open WebUI
2. Select it as your main chat model
3. Also select it as your Task Model in Settings → Interface
4. The pipe will automatically handle both roles
5. Configure system notification in pipe valves:
   - ENABLE_SYSTEM_NOTIFICATION: Toggle notification on/off
   - SYSTEM_NOTIFICATION_MESSAGE: Customize the notification text

How it works:
- Regular chat: Forwards to DO agent and streams response
- Title generation: Extracts title (JSON or plain text)
- Follow-up generation: Extracts follow-ups (JSON or plain text)
- System notification: Appends to first assistant response (streaming or non-streaming)
  * Streaming mode: Notification is appended as additional SSE chunks after response completes
  * Non-streaming mode: Notification is appended to the response content before returning
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
        DEBUG_MODE: bool = Field(
            default=False,
            description="Enable debug logging to help diagnose issues"
        )

    def __init__(self) -> None:
        self.type = "pipe"
        self.id = "do_function_pipe"
        self.name = "DO Function Pipe"
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

        When called as a task model (__task__ is not None), returns JSON string
        that the backend middleware can parse.
        When called for regular chat, returns OpenAI-format completion or streams.
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
        """
        Handle task model operations (title generation, follow-up questions).

        Returns a JSON string that Open WebUI's backend middleware expects:
        - Title: '{"title": "..."}'
        - Follow-ups: '{"follow_ups": ["Q1", "Q2", ...]}'

        The backend wraps this in an OpenAI completion and the middleware extracts it.
        """

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

            # Return JSON string (backend will wrap this in OpenAI completion)
            json_result = json.dumps({"title": title})

            if self.valves.DEBUG_MODE:
                print(f"[DEBUG] Returning title JSON: {json_result}")

            return json_result

        elif task == str(TASKS.FOLLOW_UP_GENERATION):
            follow_ups = self._extract_follow_ups(content, task_body)

            # Return JSON string (backend will wrap this in OpenAI completion)
            json_result = json.dumps({"follow_ups": follow_ups})

            if self.valves.DEBUG_MODE:
                print(f"[DEBUG] Returning follow-ups JSON: {json_result}")

            return json_result

        # Unknown task type - return empty JSON
        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] Unknown task type: {task}")

        return "{}"

    def _extract_title(self, content: str, task_body: Optional[Dict[str, Any]]) -> str:
        """
        Extract title from DO agent response.

        Handles two cases:
        1. DO agent returns JSON: {"title": "My Title"}
        2. DO agent returns plain text: My Title
        """
        if not content:
            return self._fallback_title(task_body)

        content = content.strip()

        # Try parsing as JSON first (DO agent might return JSON directly)
        try:
            # Look for JSON block
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
        """
        Extract follow-up questions from DO agent response.

        Handles two cases:
        1. DO agent returns JSON: {"follow_ups": ["Q1", "Q2", ...]}
        2. DO agent returns plain text lines (one question per line)
        """
        if not content:
            return self._fallback_follow_ups(task_body)

        content = content.strip()

        # Try parsing as JSON first (DO agent might return JSON directly)
        try:
            # Look for JSON block with curly braces
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

            # Skip empty lines and lines that look like JSON artifacts
            if cleaned and len(cleaned) > 5 and not cleaned.startswith("{") and not cleaned.startswith("["):
                follow_ups.append(cleaned)

            if len(follow_ups) >= 5:  # Maximum 5 follow-ups
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
        """
        Handle regular chat completions (non-task operations).
        Uses the Digital Ocean agent's OpenAI-compatible API directly.
        """

        if not self.valves.DIGITALOCEAN_FUNCTION_URL:
            raise ValueError("DIGITALOCEAN_FUNCTION_URL valve is not configured.")

        # Build the API URL with the correct endpoint path
        api_url = f"{self.valves.DIGITALOCEAN_FUNCTION_URL.rstrip('/')}/api/v1/chat/completions"

        # Use the OpenAI-compatible payload format
        payload = {
            "messages": body.get("messages", []),
            "stream": body.get("stream", False) and self.valves.ENABLE_STREAMING,
            "model": body.get("model", ""),
        }

        # Add optional parameters if present
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

            # If streaming is enabled, wrap the response to add system notification
            if payload["stream"]:
                if self.valves.ENABLE_SYSTEM_NOTIFICATION:
                    return self._stream_with_system_notification(response.iter_lines(), body)
                else:
                    return response.iter_lines()

            # For non-streaming, get the JSON response
            response_data = response.json()

            # Check if we need to add system notification (only for first assistant message)
            if self.valves.ENABLE_SYSTEM_NOTIFICATION:
                response_data = self._add_system_notification_if_needed(response_data, body)

            return response_data

        except requests.RequestException as exc:
            # Provide more detailed error information
            error_msg = f"DigitalOcean Agent request failed: {exc}"
            if hasattr(exc, 'response') and exc.response is not None:
                try:
                    error_detail = exc.response.json()
                    error_msg += f" - Details: {error_detail}"
                except:
                    error_msg += f" - Response: {exc.response.text[:500]}"
            raise RuntimeError(error_msg) from exc

    def _stream_with_system_notification(
        self,
        stream_iter: Iterator,
        request_body: Dict[str, Any]
    ) -> Iterator:
        """
        Wrap streaming response to append system notification at the end if this is the first assistant message.
        """
        # Count existing assistant messages in the conversation history
        messages = request_body.get("messages", [])
        assistant_count = len([m for m in messages if m.get("role") == "assistant"])

        # Yield all chunks from the original stream
        for chunk in stream_iter:
            yield chunk

        # After stream is done, add the notification if this is the first assistant response
        if assistant_count == 0:
            notification = self.valves.SYSTEM_NOTIFICATION_MESSAGE

            # Send notification as additional streaming chunks
            # Split into smaller chunks to simulate natural streaming
            notification_chunks = [notification[i:i+50] for i in range(0, len(notification), 50)]

            for chunk_text in notification_chunks:
                # Format as SSE (Server-Sent Events) chunk
                chunk_data = {
                    "choices": [{
                        "delta": {"content": chunk_text},
                        "index": 0,
                        "finish_reason": None
                    }]
                }
                chunk_line = f"data: {json.dumps(chunk_data)}\n\n".encode('utf-8')
                yield chunk_line

            if self.valves.DEBUG_MODE:
                print("[DEBUG] Added system notification to streaming response")

    def _add_system_notification_if_needed(
        self,
        response_data: Dict[str, Any],
        request_body: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Add system notification to the response if this is the first assistant message.
        (Used for non-streaming responses only)
        """
        # Count existing assistant messages in the conversation history
        messages = request_body.get("messages", [])
        assistant_count = len([m for m in messages if m.get("role") == "assistant"])

        # If this will be the first assistant response, add the notification
        if assistant_count == 0:
            notification = self.valves.SYSTEM_NOTIFICATION_MESSAGE

            # Add notification to the response content
            if isinstance(response_data, dict) and "choices" in response_data:
                choices = response_data.get("choices", [])
                if choices and isinstance(choices[0], dict):
                    message = choices[0].get("message", {})
                    if "content" in message:
                        original_content = message["content"]
                        message["content"] = original_content + notification

                        if self.valves.DEBUG_MODE:
                            print("[DEBUG] Added system notification to first assistant response")

        return response_data

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
        """
        Invoke the DigitalOcean agent using OpenAI-compatible API format.
        """
        if not self.valves.DIGITALOCEAN_FUNCTION_URL:
            raise ValueError("DIGITALOCEAN_FUNCTION_URL valve is not configured.")

        # Build the API URL with the correct endpoint path
        api_url = f"{self.valves.DIGITALOCEAN_FUNCTION_URL.rstrip('/')}/api/v1/chat/completions"

        # For task operations, modify the messages to ask for specific output
        messages = body.get("messages", [])

        if task == str(TASKS.TITLE_GENERATION):
            # Add a system message to guide title generation
            messages = [
                {"role": "system", "content": "Generate a brief, descriptive title for this conversation. Respond with just the title, no quotes or extra text."},
                *messages
            ]
        elif task == str(TASKS.FOLLOW_UP_GENERATION):
            # Add a system message to guide follow-up generation
            messages = [
                {"role": "system", "content": "Generate 3-5 follow-up questions based on this conversation. Return them as a simple list, one per line."},
                *messages
            ]

        # Use the OpenAI-compatible payload format
        payload = {
            "messages": messages,
            "stream": False,  # Never stream for task operations
            "model": body.get("model", ""),
        }

        # Add optional parameters if present
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
            # Provide more detailed error information
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

    # Extraction helpers -------------------------------------------------
    def _fallback_title(self, task_body: Optional[Dict[str, Any]]) -> str:
        """
        Generate a fallback title from the conversation.
        """
        if not task_body:
            return "New Chat"
        messages = task_body.get("messages") or []
        for message in reversed(messages):
            if isinstance(message, dict) and message.get("role") == "user":
                content = message.get("content")
                if isinstance(content, str) and content.strip():
                    # Take first 100 chars of user message as title
                    title = content.strip()[:100]
                    # Clean up the title
                    title = re.sub(r'\s+', ' ', title)  # Normalize whitespace
                    return title
        return "New Chat"

    @staticmethod
    def _fallback_follow_ups(
        _task_body: Optional[Dict[str, Any]]
    ) -> List[str]:
        """
        Generate fallback follow-up questions.
        """
        return []
