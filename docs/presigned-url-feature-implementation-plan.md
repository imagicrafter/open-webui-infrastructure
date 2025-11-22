# Presigned URL Support for DO Function Pipe - Implementation Plan (Simplified)

**Project ID**: `76141ec4-6a0b-40d5-bcbd-40d08dd674d0`
**Branch**: `feat/url-signing`
**Version**: 9.0.0
**Date**: 2025-01-21
**Status**: Planning
**Approach**: Balanced (Option B) - No over-engineering

---

## Executive Summary

This feature adds presigned URL generation support to the Digital Ocean function pipe to enable automatic signing of private image URLs from Digital Ocean Spaces. The implementation follows a **balanced approach** that avoids over-engineering while maintaining necessary functionality.

### Key Simplifications from Original Plan
- ❌ **Removed**: `PRIVATE_PATH_PATTERNS` valve (sign all or none based on enable flag)
- ❌ **Removed**: `DO_SPACES_BUCKET` valve (always auto-detect from URLs)
- ❌ **Removed**: Separate README files (documentation in docstring only)
- ❌ **Removed**: Test utility script (manual integration testing only)
- ✅ **Simplified**: Detection logic - if enabled + credentials exist → sign all DO Spaces URLs
- ✅ **Time Reduced**: 9.5 hours → **5.5 hours** (60% time savings)

### Core Features (Unchanged)
- ✅ Automatic presigned URL generation for private images
- ✅ Simple detection (enabled + not already signed + is DO Spaces URL)
- ✅ Configurable expiration (default: 1 hour)
- ✅ Graceful degradation (skips images on signing failures)
- ✅ Backward compatible (disabled by default)
- ✅ Zero impact on existing public URL functionality

---

## Background & Requirements

### Problem Statement
When images are stored in private Digital Ocean Spaces buckets, the pipe cannot display them because:
1. Private URLs return 403 Forbidden without authentication
2. No mechanism exists to generate time-limited access URLs
3. Manual presigned URL generation is not scalable

### Simplified Requirements

#### Functional Requirements
1. **FR-1**: Automatically detect DO Spaces URLs and sign them if enabled
2. **FR-2**: Generate presigned URLs with configurable expiration
3. **FR-3**: Gracefully handle signing failures without breaking pipe
4. **FR-4**: Respect existing presigned URLs (no re-signing)
5. **FR-5**: Simple on/off configuration via valve

#### Non-Functional Requirements
1. **NFR-1**: Zero impact on performance for public URLs
2. **NFR-2**: Minimal latency added for signing (< 100ms per URL)
3. **NFR-3**: Secure credential storage (via valves)
4. **NFR-4**: Backward compatible (feature disabled by default)
5. **NFR-5**: Debug logging for troubleshooting

---

## Technical Architecture

### Simplified Configuration (4 Valves Only)

```python
# Presigned URL Support Configuration
ENABLE_PRESIGNED_URLS: bool = False
DO_SPACES_ACCESS_KEY: str = ""
DO_SPACES_SECRET_KEY: str = ""
DO_SPACES_REGION: str = "nyc3"
PRESIGNED_URL_EXPIRATION: int = 3600  # 1 hour
```

### Simplified Detection Logic

```python
def _needs_signing(self, url: str) -> bool:
    """
    Simple detection: Sign if ALL conditions true:
    1. Feature enabled via valve
    2. Credentials configured
    3. URL not already signed (no X-Amz-* parameters)
    4. URL is from Digital Ocean Spaces
    """
    if not self.valves.ENABLE_PRESIGNED_URLS:
        return False
    if not self.valves.DO_SPACES_ACCESS_KEY or not self.valves.DO_SPACES_SECRET_KEY:
        return False
    if 'X-Amz-' in url:  # Already signed
        return False
    return '.digitaloceanspaces.com' in url  # Simple domain check
```

### Data Flow

```
1. Agent Response with Image URLs
   ↓
2. _extract_image_urls() extracts URLs
   ↓
3. For each URL:
   ├─▶ _needs_signing(url)
   │   ├─▶ Check ENABLE_PRESIGNED_URLS
   │   ├─▶ Check credentials exist
   │   ├─▶ Check not already signed (X-Amz-*)
   │   └─▶ Check is DO Spaces domain
   │
   ├─▶ If needs signing:
   │   └─▶ _generate_presigned_url(url)
   │       ├─▶ _get_s3_client() (lazy init)
   │       ├─▶ _extract_bucket_and_key(url)
   │       ├─▶ boto3.generate_presigned_url()
   │       └─▶ Return signed URL or None
   │
   └─▶ If signing failed: skip image
   ↓
4. Append valid URLs to image_urls list
   ↓
5. Format as markdown and return to user
```

---

## Implementation Phases

### Total Estimated Time: **5.5 hours**

| Phase | Tasks | Time | Notes |
|-------|-------|------|-------|
| **Phase 1: Setup** | Tasks 1-2 | 20 min | Configuration + dependencies |
| **Phase 2: Core Logic** | Tasks 3-5 | 2.5 hr | S3 client, detection, signing |
| **Phase 3: Integration** | Task 6 | 45 min | Wire into existing workflow |
| **Phase 4: Documentation** | Task 7 | 1 hr | Docstring updates only |
| **Phase 5: Testing** | Task 8 | 2 hr | Manual integration testing |

---

## Task Breakdown

### Task 1: Add Simplified Configuration Valves
**Archon Task ID**: `b25592eb-b1c0-4a76-abb4-0d132eec50eb`
**Estimated Time**: 10 minutes

Add to `Pipe.Valves` class (4 valves only):

```python
# Presigned URL Support Configuration
ENABLE_PRESIGNED_URLS: bool = Field(
    default=False,
    description="Enable automatic signing of Digital Ocean Spaces image URLs"
)

DO_SPACES_ACCESS_KEY: str = Field(
    default="",
    description="Digital Ocean Spaces access key (required if presigned URLs enabled)"
)

DO_SPACES_SECRET_KEY: str = Field(
    default="",
    description="Digital Ocean Spaces secret key (required if presigned URLs enabled)"
)

DO_SPACES_REGION: str = Field(
    default="nyc3",
    description="Digital Ocean Spaces region (e.g., nyc3, sfo3, ams3, sgp1, fra1)"
)

PRESIGNED_URL_EXPIRATION: int = Field(
    default=3600,
    description="Presigned URL expiration in seconds (default: 3600 = 1 hour, max: 604800 = 7 days)"
)
```

**Testing**:
- Load pipe in Open WebUI
- Verify all valves appear correctly
- Check default values

---

### Task 2: Update Dependencies and Imports
**Archon Task ID**: `5b48c9af-0607-41a7-a36a-94720153521d`
**Estimated Time**: 10 minutes

Update docstring requirements:
```python
requirements: requests, boto3
```

Add imports:
```python
import boto3
from botocore.exceptions import ClientError, BotoCoreError
```

**Testing**:
- Import pipe in Python interpreter
- Verify no ImportError exceptions

---

### Task 3: Implement S3 Client Initialization
**Archon Task ID**: `9e059f0f-e103-48b6-a603-b2d8a03b6842`
**Estimated Time**: 30 minutes

Modify `__init__`:
```python
def __init__(self) -> None:
    self.type = "pipe"
    self.id = "do_function_pipe_kb_images"
    self.name = "DO Function Pipe (KB Images)"
    self.valves = self.Valves()
    self._s3_client = None  # Lazy initialization
```

Add method:
```python
def _get_s3_client(self):
    """Lazy-load S3 client for presigned URL generation."""
    if self._s3_client is not None:
        return self._s3_client

    # Only initialize if credentials are configured
    if not self.valves.DO_SPACES_ACCESS_KEY or not self.valves.DO_SPACES_SECRET_KEY:
        if self.valves.DEBUG_MODE:
            print("[DEBUG] S3 client not initialized: credentials missing")
        return None

    try:
        self._s3_client = boto3.client(
            's3',
            region_name=self.valves.DO_SPACES_REGION,
            endpoint_url=f'https://{self.valves.DO_SPACES_REGION}.digitaloceanspaces.com',
            aws_access_key_id=self.valves.DO_SPACES_ACCESS_KEY,
            aws_secret_access_key=self.valves.DO_SPACES_SECRET_KEY,
        )

        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] S3 client initialized successfully (region: {self.valves.DO_SPACES_REGION})")

        return self._s3_client
    except Exception as e:
        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] Failed to initialize S3 client: {e}")
        return None
```

**Testing**:
- Initialize with valid credentials → client created
- Initialize with missing credentials → returns None
- Check debug logs

---

### Task 4: Implement Simplified URL Detection Logic
**Archon Task ID**: `78f70915-c244-4d98-b8ee-ec3d20efcab5`
**Estimated Time**: 45 minutes

Add methods:

```python
def _needs_signing(self, url: str) -> bool:
    """
    Simple detection: Sign if enabled + credentials exist + not already signed + is DO Spaces.

    Returns True if ALL conditions met:
    1. ENABLE_PRESIGNED_URLS valve is True
    2. Credentials are configured
    3. URL is not already signed (no X-Amz-* parameters)
    4. URL is from Digital Ocean Spaces domain

    Args:
        url: Image URL to check

    Returns:
        True if URL should be signed, False otherwise
    """
    # Feature disabled
    if not self.valves.ENABLE_PRESIGNED_URLS:
        return False

    # No credentials configured
    if not self.valves.DO_SPACES_ACCESS_KEY or not self.valves.DO_SPACES_SECRET_KEY:
        if self.valves.DEBUG_MODE:
            print("[DEBUG] Cannot sign URLs: credentials not configured")
        return False

    # Already has presigned parameters
    if 'X-Amz-' in url:
        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] URL already signed, skipping: {url[:80]}...")
        return False

    # Check if URL is from Digital Ocean Spaces
    is_do_spaces = '.digitaloceanspaces.com' in url

    if self.valves.DEBUG_MODE:
        if is_do_spaces:
            print(f"[DEBUG] DO Spaces URL needs signing: {url[:80]}...")
        else:
            print(f"[DEBUG] Not a DO Spaces URL, skipping: {url[:80]}...")

    return is_do_spaces

def _extract_bucket_and_key(self, url: str) -> tuple:
    """
    Extract bucket name and object key from Digital Ocean Spaces URL.

    Supports format: https://BUCKET.REGION.digitaloceanspaces.com/path/to/file.png

    Args:
        url: Full Digital Ocean Spaces URL

    Returns:
        Tuple of (bucket_name, object_key) or (None, None) if parsing fails
    """
    try:
        # Remove protocol
        url_parts = url.replace('https://', '').replace('http://', '')

        # Check for virtual-hosted style: BUCKET.REGION.digitaloceanspaces.com/KEY
        if '.digitaloceanspaces.com' in url_parts:
            parts = url_parts.split('.digitaloceanspaces.com/', 1)
            if len(parts) == 2:
                # Extract bucket from subdomain
                bucket = parts[0].split('.')[0]

                # Extract key and remove query params
                key = parts[1].split('?')[0]

                if self.valves.DEBUG_MODE:
                    print(f"[DEBUG] Extracted bucket: {bucket}, key: {key}")

                return bucket, key

        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] Failed to parse bucket/key from URL: {url[:80]}...")

        return None, None

    except Exception as e:
        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] Error parsing URL: {e}")
        return None, None
```

**Testing**:
- Test with DO Spaces URL → returns True
- Test with non-DO Spaces URL → returns False
- Test with already-signed URL → returns False
- Test bucket/key extraction with various URL formats
- Verify debug logs

---

### Task 5: Implement Presigned URL Generation
**Archon Task ID**: `5e3ced78-22cf-4856-801c-13280059262d`
**Estimated Time**: 45 minutes

```python
def _generate_presigned_url(self, url: str) -> Optional[str]:
    """
    Generate presigned URL for Digital Ocean Spaces object.

    Args:
        url: Original URL to sign

    Returns:
        Presigned URL if successful, None if signing fails
    """
    # Get S3 client (lazy initialization)
    s3_client = self._get_s3_client()
    if s3_client is None:
        if self.valves.DEBUG_MODE:
            print("[DEBUG] S3 client not available, cannot sign URL")
        return None

    # Extract bucket and key from URL
    bucket, key = self._extract_bucket_and_key(url)
    if not bucket or not key:
        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] Failed to extract bucket/key, cannot sign: {url[:80]}...")
        return None

    if self.valves.DEBUG_MODE:
        print(f"[DEBUG] Generating presigned URL for: {bucket}/{key}")
        print(f"[DEBUG] Expiration: {self.valves.PRESIGNED_URL_EXPIRATION} seconds")

    try:
        presigned_url = s3_client.generate_presigned_url(
            ClientMethod='get_object',
            Params={
                'Bucket': bucket,
                'Key': key,
            },
            ExpiresIn=self.valves.PRESIGNED_URL_EXPIRATION
        )

        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] Successfully generated presigned URL")

        return presigned_url

    except ClientError as e:
        if self.valves.DEBUG_MODE:
            error_code = e.response.get('Error', {}).get('Code', 'Unknown')
            error_msg = e.response.get('Error', {}).get('Message', str(e))
            print(f"[DEBUG] AWS ClientError: {error_code} - {error_msg}")
        return None

    except BotoCoreError as e:
        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] BotoCoreError: {str(e)}")
        return None

    except Exception as e:
        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] Unexpected error: {type(e).__name__} - {str(e)}")
        return None
```

**Testing**:
- Generate presigned URL with valid credentials → success
- Generate with invalid credentials → returns None, logs error
- Generate with malformed URL → returns None
- Verify generated URL contains X-Amz-* parameters
- Check expiration time is correct

---

### Task 6: Integrate Signing into Image Extraction
**Archon Task ID**: `590ef8da-5b6d-48cc-9cbd-7f08ec85465b`
**Estimated Time**: 45 minutes

Modify `_extract_image_urls()` method:

```python
def _extract_image_urls(self, text: str) -> List[str]:
    """
    Extract image URLs from text using configured pattern.

    Supports:
    - Plain URLs in text
    - URLs in markdown links: [text](url)
    - URLs in markdown images: ![alt](url)
    - **NEW: Automatic presigned URL generation for DO Spaces images**

    Smart deduplication (always enabled):
    - Excludes URLs already embedded as markdown images
    - Only adds images mentioned but not displayed
    - Prevents duplicate images in response
    """
    if not text:
        return []

    image_urls = []

    try:
        # Compile regex pattern from valve
        pattern = re.compile(self.valves.IMAGE_URL_PATTERN, re.IGNORECASE)

        # Find all matches
        matches = pattern.findall(text)

        # Detect URLs already embedded as markdown images
        embedded_pattern = r'!\[.*?\]\((' + self.valves.IMAGE_URL_PATTERN + r')\)'
        embedded_matches = re.findall(embedded_pattern, text, re.IGNORECASE)
        embedded_urls = set(embedded_matches)

        if self.valves.DEBUG_MODE and embedded_urls:
            print(f"[DEBUG] Found {len(embedded_urls)} images already embedded in response")

        # Deduplicate and apply presigned URL signing
        seen = set()
        for url in matches:
            if url not in seen and url not in embedded_urls:
                # Check if URL needs signing
                if self._needs_signing(url):
                    if self.valves.DEBUG_MODE:
                        print(f"[DEBUG] Attempting to sign URL: {url[:80]}...")

                    signed_url = self._generate_presigned_url(url)

                    # Skip image if signing failed
                    if signed_url is None:
                        if self.valves.DEBUG_MODE:
                            print(f"[DEBUG] Signing failed, skipping image: {url[:80]}...")
                        continue

                    # Use signed URL
                    if self.valves.DEBUG_MODE:
                        print(f"[DEBUG] Using presigned URL")
                    url = signed_url

                seen.add(url)
                image_urls.append(url)

                # Respect max images limit
                if len(image_urls) >= self.valves.MAX_IMAGES_PER_RESPONSE:
                    break

        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] Extracted {len(image_urls)} image URLs (after deduplication and signing)")

    except Exception as e:
        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] Error extracting image URLs: {type(e).__name__} - {str(e)}")

    return image_urls
```

**Testing**:
- Test with all public URLs → no signing
- Test with DO Spaces URLs → all signed
- Test with mixed URLs → correct URLs signed
- Test with signing failure → image skipped, pipe continues
- Verify deduplication still works
- Check max images limit still applies

---

### Task 7: Update Pipe Documentation (Docstring Only)
**Archon Task ID**: `6a8ae888-2ff3-4f00-8cc6-b5b82a44595e`
**Estimated Time**: 1 hour

Update docstring at top of file:

```python
"""
title: Digital Ocean Function Pipe with KB Image Support
author: open-webui
date: 2025-01-21
version: 9.0.0
license: MIT
description: Full-featured DO pipe with automatic image URL extraction and presigned URL support
required_open_webui_version: 0.3.9
requirements: requests, boto3

KEY FEATURES:
- JSON-aware task handling (title/follow-up generation)
- Streaming and non-streaming support
- Optional system notification on first response
- **Automatic image URL detection from agent responses**
- **Smart deduplication prevents duplicate images** (always enabled)
- **NEW: Presigned URL generation for Digital Ocean Spaces images**
- Works with OpenSearch knowledge base image metadata

PRESIGNED URL SUPPORT (NEW IN v9.0):
This feature allows the pipe to automatically sign private Digital Ocean Spaces URLs
so they can be displayed in Open WebUI without manual URL generation.

Configuration (5 valves):
1. ENABLE_PRESIGNED_URLS (bool, default: False)
   - Master switch for the feature

2. DO_SPACES_ACCESS_KEY (str)
   - Your Spaces access key (required if enabled)

3. DO_SPACES_SECRET_KEY (str)
   - Your Spaces secret key (required if enabled)

4. DO_SPACES_REGION (str, default: "nyc3")
   - Region where your Spaces bucket is located
   - Options: nyc3, sfo3, ams3, sgp1, fra1

5. PRESIGNED_URL_EXPIRATION (int, default: 3600)
   - How long signed URLs remain valid (in seconds)
   - Default: 3600 seconds (1 hour)
   - Maximum: 604800 seconds (7 days)

How It Works (Simplified):
1. When ENABLE_PRESIGNED_URLS = True and credentials are configured:
   - All Digital Ocean Spaces URLs (*.digitaloceanspaces.com) are signed
   - URLs with existing signatures (X-Amz-* params) are NOT re-signed
   - Non-DO-Spaces URLs pass through unchanged

2. If signing fails (invalid credentials, network error, etc.):
   - Image is skipped gracefully
   - Other images continue to display
   - No error shown to user

3. Debug logging available via DEBUG_MODE valve

Simple Setup:
1. Get Spaces access keys from Digital Ocean dashboard
2. Enable ENABLE_PRESIGNED_URLS valve
3. Add DO_SPACES_ACCESS_KEY and DO_SPACES_SECRET_KEY
4. Set DO_SPACES_REGION to match your bucket
5. Done! All DO Spaces URLs will be signed automatically

Security Notes:
- Access/secret keys stored securely in Open WebUI valves
- Presigned URLs expire after configured time (default: 1 hour)
- Only GET operations supported (read-only)
- URLs are never signed twice (existing signatures preserved)
- Use read-only Spaces keys for least privilege

CONFIGURATION VALVES:

Image Detection:
- ENABLE_KB_IMAGE_DETECTION: Toggle automatic image detection (default: True)
- IMAGE_URL_PATTERN: Regex for detecting image URLs
- MAX_IMAGES_PER_RESPONSE: Limit images displayed (default: 10)

Presigned URLs:
- ENABLE_PRESIGNED_URLS: Toggle presigned URL generation (default: False)
- DO_SPACES_ACCESS_KEY: Access key for signing
- DO_SPACES_SECRET_KEY: Secret key for signing
- DO_SPACES_REGION: Spaces region (default: nyc3)
- PRESIGNED_URL_EXPIRATION: URL expiration in seconds (default: 3600)

Other:
- DIGITALOCEAN_FUNCTION_URL: DO agent endpoint URL
- DIGITALOCEAN_FUNCTION_TOKEN: DO agent access token
- REQUEST_TIMEOUT_SECONDS: Request timeout (default: 120)
- VERIFY_SSL: Verify SSL certificates (default: True)
- ENABLE_STREAMING: Enable streaming responses (default: True)
- ENABLE_SYSTEM_NOTIFICATION: Show system notification (default: False)
- SYSTEM_NOTIFICATION_MESSAGE: Custom notification message
- DEBUG_MODE: Enable debug logging (default: False)

Note: Smart deduplication is always enabled - images embedded by the agent
will not be duplicated.
"""
```

**Testing**:
- Documentation is accurate and complete
- All valves are documented
- Setup instructions are clear

---

### Task 8: Perform Integration Testing
**Archon Task ID**: `9a8576e9-80eb-4578-85a1-bcba0e30a774`
**Estimated Time**: 2 hours

**Test Scenarios**:

#### Scenario 1: Feature Disabled (Default)
**Setup**: ENABLE_PRESIGNED_URLS = False

**Test**:
- Agent returns DO Spaces URLs
- Expected: URLs pass through unchanged
- Expected: Images display correctly

#### Scenario 2: Feature Enabled - Public/Private Mix
**Setup**:
- ENABLE_PRESIGNED_URLS = True
- Valid credentials configured

**Test**:
- Agent returns mix of DO Spaces and non-DO Spaces URLs
- Expected: Only DO Spaces URLs get signed
- Expected: All images display correctly

#### Scenario 3: Already Signed URLs
**Setup**:
- ENABLE_PRESIGNED_URLS = True
- Agent returns URLs with existing X-Amz-* parameters

**Test**:
- Expected: URLs are NOT re-signed
- Expected: Original URLs used as-is
- Expected: Images display correctly

#### Scenario 4: Error Handling - Invalid Credentials
**Setup**:
- ENABLE_PRESIGNED_URLS = True
- Invalid credentials configured

**Test**:
- Agent returns DO Spaces URLs
- Expected: Signing fails gracefully
- Expected: Images are skipped
- Expected: No exceptions thrown

#### Scenario 5: Debug Mode
**Setup**:
- DEBUG_MODE = True
- ENABLE_PRESIGNED_URLS = True

**Test**:
- Check logs show:
  - S3 client initialization
  - URL detection decisions
  - Bucket/key extraction
  - Signing operations
  - Success/failure status

#### Scenario 6: Performance
**Setup**: Response with 5 DO Spaces images

**Test**:
- Measure time to process response
- Expected: < 500ms total signing time
- Expected: ~100ms per URL
- Expected: No timeout errors

**Test Results Documentation**:

Create `docs/presigned-url-test-results.md`:

```markdown
# Presigned URL Feature Test Results

**Date**: YYYY-MM-DD
**Tester**: Name
**Environment**: Test/Production

## Test Summary
- Total Scenarios: 6
- Passed: X
- Failed: Y
- Notes: ...

## Scenario Results

### 1. Feature Disabled
- Status: PASS/FAIL
- Notes: ...

### 2. Public/Private Mix
- Status: PASS/FAIL
- Notes: ...

[... continue for all scenarios ...]

## Issues Found
1. Issue description (if any)

## Performance Metrics
- Average signing time per URL: Xms
- Total response time: Xms

## Recommendations
- Ready for production: YES/NO
- Additional testing needed: ...
```

---

## Security Considerations

### Credential Management
**Mitigation**:
- Valves encrypted in Open WebUI database
- Only admins can view/edit valve values
- Credentials never logged
- Use read-only Spaces keys

### URL Expiration
**Mitigation**:
- Default: 1 hour (reasonable for typical use)
- Maximum: 7 days (AWS S3 limitation)
- Recommend shortest practical expiration

### Least Privilege
**Mitigation**:
- Only GET operations used
- No PUT/DELETE presigned URLs generated
- Recommend dedicated read-only Spaces keys

---

## Deployment Plan

### Pre-Deployment Checklist
- [ ] All 8 tasks completed
- [ ] Code review completed
- [ ] All test scenarios passing
- [ ] Documentation updated
- [ ] Security review completed

### Deployment Steps

#### Step 1: Merge to Main
```bash
git status
git checkout main
git merge feat/url-signing
git push origin main
```

#### Step 2: Tag Release
```bash
git tag -a v9.0.0 -m "Add presigned URL support for DO Spaces images"
git push origin v9.0.0
```

#### Step 3: Update Production Pipe
1. Copy updated `do-function-pipe-with-kb-images.py` to Open WebUI
2. In Open WebUI admin:
   - Navigate to Functions
   - Update existing function
   - Paste updated code
   - Save

#### Step 4: Configure Valves (Initially Disabled)
```
ENABLE_PRESIGNED_URLS: False (start disabled)
DO_SPACES_ACCESS_KEY: <production_key>
DO_SPACES_SECRET_KEY: <production_secret>
DO_SPACES_REGION: nyc3
PRESIGNED_URL_EXPIRATION: 3600
DEBUG_MODE: False
```

#### Step 5: Smoke Test
1. Test with feature disabled (default)
2. Enable ENABLE_PRESIGNED_URLS valve
3. Test with DO Spaces URLs
4. Verify images display correctly
5. Check no errors in logs

---

## Rollback Procedure

### Quick Rollback (Emergency)
1. **Disable Feature**:
   - Open WebUI admin → Function settings
   - Set `ENABLE_PRESIGNED_URLS = False`
   - Save (immediate effect, no restart needed)

2. **Verify**: Public URLs still work correctly

### Full Rollback
If valve disable insufficient:
1. Restore previous pipe version
2. Update function in Open WebUI admin
3. Test basic functionality

---

## Success Criteria

### Functional Success
- ✅ DO Spaces URLs are automatically signed when enabled
- ✅ Non-DO Spaces URLs work without changes
- ✅ Already-signed URLs not re-signed
- ✅ Error conditions handled gracefully
- ✅ Feature can be enabled/disabled via valve

### Technical Success
- ✅ All 8 tasks completed
- ✅ All test scenarios pass
- ✅ Zero regressions in existing functionality
- ✅ Code follows existing patterns
- ✅ Debug logging comprehensive

### Performance Success
- ✅ < 100ms per URL signing operation
- ✅ < 500ms total for 5 URLs
- ✅ No timeout issues

### Security Success
- ✅ Credentials stored securely
- ✅ No credentials in logs
- ✅ Least privilege verified (GET only)
- ✅ URL expiration configurable

---

## Configuration Examples

### Development Environment
```python
ENABLE_PRESIGNED_URLS: True
DO_SPACES_ACCESS_KEY: "DO00XXXXXXXXXXXX"
DO_SPACES_SECRET_KEY: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
DO_SPACES_REGION: "nyc3"
PRESIGNED_URL_EXPIRATION: 7200  # 2 hours for development
DEBUG_MODE: True
```

### Production Environment
```python
ENABLE_PRESIGNED_URLS: True
DO_SPACES_ACCESS_KEY: "DO00YYYYYYYYYYYY"
DO_SPACES_SECRET_KEY: "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy"
DO_SPACES_REGION: "nyc3"
PRESIGNED_URL_EXPIRATION: 3600  # 1 hour
DEBUG_MODE: False
```

---

## Troubleshooting

### Issue: Images not displaying
**Diagnosis**:
1. Check DEBUG_MODE logs for signing errors
2. Verify ENABLE_PRESIGNED_URLS = True
3. Verify credentials configured correctly

**Resolution**:
- Ensure valid credentials
- Verify region setting matches bucket location

### Issue: "S3 client not initialized"
**Diagnosis**:
- Check DO_SPACES_ACCESS_KEY is set
- Check DO_SPACES_SECRET_KEY is set

**Resolution**:
- Generate new Spaces access keys from DO dashboard
- Update valves with correct credentials

### Issue: "403 Forbidden" on image load
**Diagnosis**:
1. Check if URL expired
2. Verify bucket permissions

**Resolution**:
- Increase expiration time if needed
- Verify bucket allows GET with signature

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-01-21 | Claude | Initial plan (full version) |
| 2.0 | 2025-01-21 | Claude | Simplified to Option B (balanced approach) |

---

**End of Implementation Plan**
