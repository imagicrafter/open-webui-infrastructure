# Digital Ocean Knowledge Base Pipe

A custom OpenWebUI pipe that connects to a Digital Ocean AI agent for knowledge base queries with optional beta warning support.

## Features

- **JSON-Aware Parsing**: Handles both JSON and plain text responses from the DO agent
- **Dual Mode Support**: Works as both chat model and task model (title/follow-up generation)
- **Streaming Support**: Full streaming support with beta warning injection
- **Configurable Beta Warning**: Optional warning message on first response
- **Debug Mode**: Built-in logging for troubleshooting

## Installation

### 1. Add to Open WebUI

1. Go to **Admin Panel → Functions → Pipes**
2. Click **+ Create New Pipe**
3. Copy the contents of `do-function-pipe.py`
4. Paste into the editor
5. Click **Save**
6. Give it a name (e.g., "Engineering Knowledge Base")

### 2. Configure as Chat Model

1. In any chat, click the model selector
2. Find your pipe in the list
3. Select it as your active model

### 3. Configure as Task Model

1. Go to **Settings → Interface**
2. Find **Task Model** dropdown
3. Select your pipe
4. This enables automatic title and follow-up generation

## Configuration (Valves)

Click the settings/gear icon on your pipe to configure:

| Valve | Type | Default | Description |
|-------|------|---------|-------------|
| `DIGITALOCEAN_FUNCTION_URL` | string | (provided) | DO agent endpoint URL |
| `DIGITALOCEAN_FUNCTION_TOKEN` | string | (provided) | DO agent access token |
| `REQUEST_TIMEOUT_SECONDS` | float | 120.0 | Request timeout |
| `VERIFY_SSL` | bool | true | Verify SSL certificates |
| `ENABLE_STREAMING` | bool | true | Enable streaming responses |
| `ENABLE_BETA_WARNING` | bool | true | Show beta warning on first response |
| `BETA_WARNING_MESSAGE` | string | (see below) | Custom warning text |
| `DEBUG_MODE` | bool | false | Enable debug logging |

### Default Beta Warning Message

```markdown
---

🤖 **Assistant In-Training**: I'm still learning to process large technical datasets—I might miss details or make wrong connections.

**Helpful buttons**: Continue 👎 (to report errors) | ▶️ (if I stop mid-thought) | Regenerate 🔄 (for a fresh retry attempt if it looks like I missed something)
```

## How It Works

### Chat Mode (Regular Queries)

1. User sends a message
2. Pipe forwards to Digital Ocean agent
3. Response streams back (if streaming enabled)
4. **If first response in chat**: Beta warning appended (if enabled)
5. Message saved to database with warning included

### Task Mode (Title/Follow-ups)

The pipe automatically handles two special tasks:

**Title Generation:**
- Analyzes conversation
- Extracts or generates a concise title
- Returns as JSON: `{"title": "Chat Title"}`

**Follow-up Generation:**
- Analyzes conversation context
- Generates 3-5 relevant follow-up questions
- Returns as JSON: `{"follow_ups": ["Q1", "Q2", ...]}`

The pipe handles both JSON and plain text responses from the DO agent, automatically parsing and formatting them correctly.

## Beta Warning Feature

### How It Works

The beta warning appears **only on the first assistant response** in each new chat. This helps set user expectations about the assistant's capabilities.

**Streaming Mode** (default):
- Main response streams normally
- After streaming completes, warning appends as additional chunks
- Warning appears and stays visible (no flash/disappear)

**Non-Streaming Mode** (fallback):
- Response received from DO agent
- Warning appended to response content
- Complete response returned to UI

### Customizing the Warning

1. Click settings icon on your pipe
2. Find `BETA_WARNING_MESSAGE` valve
3. Enter your custom text (supports Markdown)
4. Click **Save**

**Example Custom Messages:**

**Short:**
```
⚠️ **Beta Mode**: Please verify all responses
```

**Formal:**
```
---

**Important Notice**: This assistant is in beta testing. Please verify responses before use in production environments.
```

**Detailed:**
```
---

🧪 **Testing Phase**: This AI is being evaluated for accuracy and completeness.

- Report issues with the 👎 button
- Use ▶️ if response stops mid-thought
- Try 🔄 to regenerate if needed
```

### Disabling the Warning

To turn off the beta warning:
1. Click settings icon on your pipe
2. Set `ENABLE_BETA_WARNING` to `false`
3. Click **Save**

## Troubleshooting

### No response from the pipe

**Check:**
1. `DIGITALOCEAN_FUNCTION_URL` is correctly set
2. `DIGITALOCEAN_FUNCTION_TOKEN` is valid
3. Network connectivity to Digital Ocean
4. Enable `DEBUG_MODE` and check server logs

### Warning doesn't appear

**Check:**
1. `ENABLE_BETA_WARNING` is set to `true`
2. Testing in a **new chat** (warning only on first response)
3. Enable `DEBUG_MODE` to see: `[DEBUG] Added beta warning to streaming response`

### Warning appears on every message

This shouldn't happen - the pipe counts assistant messages and only adds warning when count is 0. If this occurs:
1. Enable `DEBUG_MODE`
2. Check logs for assistant message count
3. Report as a bug

### Streaming not working

**Check:**
1. `ENABLE_STREAMING` is set to `true`
2. Browser supports Server-Sent Events (SSE)
3. No proxy/firewall blocking streaming connections

### Title/follow-ups not generating

**Check:**
1. Pipe is selected as Task Model (Settings → Interface)
2. `DEBUG_MODE` enabled - look for task model logs
3. DO agent is responding correctly

## Debug Mode

Enable `DEBUG_MODE` to see detailed logging in the server console:

```
[DEBUG] Task model call: title_generation
[DEBUG] DO agent response content: {"title": "..."}
[DEBUG] Extracted title from JSON: ...
[DEBUG] Returning title JSON: {"title": "..."}
[DEBUG] Added beta warning to streaming response
```

**To view logs:**
```bash
docker logs <open-webui-container-name> -f
```

## Technical Details

### JSON Parsing Logic

The pipe tries JSON parsing FIRST, then falls back to plain text:

**For titles:**
1. Look for JSON: `{"title": "..."}`
2. Fallback: Use entire response as title
3. Limit to 100 characters

**For follow-ups:**
1. Look for JSON: `{"follow_ups": ["Q1", "Q2"]}`
2. Fallback: Parse as plain text lines (numbered/bulleted)
3. Limit to 5 questions

This handles the case where the DO agent returns JSON directly instead of formatted text.

### Streaming Implementation

The pipe wraps the DO agent's streaming response:

1. **Original chunks** → Yielded as-is
2. **After stream completes** → Warning chunks appended (if enabled)
3. **Warning format** → Split into 50-character chunks as SSE (Server-Sent Events)

Format:
```
data: {"choices":[{"delta":{"content":"chunk"},"index":0,"finish_reason":null}]}
```

### Message Counting

The pipe counts existing assistant messages in the conversation:
```python
messages = request_body.get("messages", [])
assistant_count = len([m for m in messages if m.get("role") == "assistant"])

if assistant_count == 0:  # First response
    # Add warning
```

This ensures the warning only appears once per chat.

## File Structure

```
mt/pipes/
├── do-function-pipe.py          # Main pipe implementation
├── README.md                     # This file
└── filters/                      # (empty - filters not needed)
```

## Version History

- **v3 with Beta Warning** (Current):
  - Configurable beta warning message via valve
  - Full streaming support for warning injection
  - JSON-aware parsing for title/follow-ups
  - Debug mode for troubleshooting

- **v3 JSON-Aware**:
  - Added JSON parsing for DO agent responses
  - Fixed double-nesting issues

- **v2**:
  - Dual mode support (chat + task model)

- **v1**:
  - Basic pipe functionality

## Support

For issues or questions:
1. Enable `DEBUG_MODE` and check logs
2. Review this README for common solutions
3. Check Open WebUI documentation for pipe-specific guidance

## License

This pipe is provided as-is for use with Open WebUI and Digital Ocean AI agents.
