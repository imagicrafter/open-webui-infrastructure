# Presigned URL Support for DO Function Pipe - Implementation Plan

**Project ID**: `76141ec4-6a0b-40d5-bcbd-40d08dd674d0`
**Branch**: `feat/url-signing`
**Version**: 9.0.0
**Date**: 2025-01-21
**Status**: Planning

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Background & Requirements](#background--requirements)
3. [Technical Architecture](#technical-architecture)
4. [Implementation Phases](#implementation-phases)
5. [Task Breakdown](#task-breakdown)
6. [Security Considerations](#security-considerations)
7. [Testing Strategy](#testing-strategy)
8. [Deployment Plan](#deployment-plan)
9. [Rollback Procedure](#rollback-procedure)
10. [Success Criteria](#success-criteria)

---

## Executive Summary

This feature adds presigned URL generation support to the Digital Ocean function pipe (`do-function-pipe-with-kb-images.py`) to enable automatic signing of private image URLs from Digital Ocean Spaces. This allows the pipe to handle both public and private images seamlessly, with intelligent detection and graceful error handling.

### Key Features
- ✅ Automatic presigned URL generation for private images
- ✅ Smart detection (checks for existing signatures, path patterns)
- ✅ Configurable expiration (default: 1 hour)
- ✅ Graceful degradation (skips images on signing failures)
- ✅ Backward compatible (disabled by default)
- ✅ Zero impact on existing public URL functionality

### Business Value
- Enables secure access to private knowledge base images
- Maintains security by limiting URL validity window
- Provides flexibility for mixed public/private content
- Reduces manual URL management overhead

---

## Background & Requirements

### Current State
The DO function pipe currently extracts and displays image URLs from agent responses. It works well with public Digital Ocean Spaces URLs but cannot access private images that require authentication.

### Problem Statement
When images are stored in private Digital Ocean Spaces buckets (for security/compliance), the pipe cannot display them because:
1. Private URLs return 403 Forbidden without authentication
2. No mechanism exists to generate time-limited access URLs
3. Manual presigned URL generation is not scalable

### Requirements

#### Functional Requirements
1. **FR-1**: Automatically detect which URLs need presigned signatures
2. **FR-2**: Generate presigned URLs with configurable expiration
3. **FR-3**: Support both public and private URLs in same response
4. **FR-4**: Gracefully handle signing failures without breaking pipe
5. **FR-5**: Respect existing presigned URLs (no re-signing)
6. **FR-6**: Provide configuration via Open WebUI valves

#### Non-Functional Requirements
1. **NFR-1**: Zero impact on performance for public URLs
2. **NFR-2**: Minimal latency added for private URLs (< 100ms per URL)
3. **NFR-3**: Secure credential storage (via valves, not hardcoded)
4. **NFR-4**: Backward compatible (feature disabled by default)
5. **NFR-5**: Comprehensive debug logging for troubleshooting

### User Stories

**US-1**: As an Open WebUI administrator, I want to configure presigned URL generation via valves so that I can control the feature without code changes.

**US-2**: As an end user, I want to see private knowledge base images in chat responses so that I have complete context for the information.

**US-3**: As a security officer, I want presigned URLs to expire after a reasonable time so that shared links don't remain valid indefinitely.

**US-4**: As a developer, I want clear debug logging so that I can troubleshoot URL signing issues quickly.

---

## Technical Architecture

### Components

```
┌─────────────────────────────────────────────────────────┐
│  Open WebUI Function Pipe                               │
│  (do-function-pipe-with-kb-images.py)                   │
│                                                          │
│  ┌────────────────────────────────────────────────┐    │
│  │  Pipe.Valves (Configuration)                   │    │
│  │  - ENABLE_PRESIGNED_URLS                       │    │
│  │  - DO_SPACES_ACCESS_KEY                        │    │
│  │  - DO_SPACES_SECRET_KEY                        │    │
│  │  - DO_SPACES_REGION                            │    │
│  │  - PRESIGNED_URL_EXPIRATION                    │    │
│  │  - PRIVATE_PATH_PATTERNS                       │    │
│  └────────────────────────────────────────────────┘    │
│                                                          │
│  ┌────────────────────────────────────────────────┐    │
│  │  _extract_image_urls()                         │    │
│  │  - Extract URLs from agent response            │    │
│  │  - Deduplicate embedded images                 │    │
│  │  - Check if signing needed                     │    │
│  │  - Generate presigned URLs                     │    │
│  └────────────────────────────────────────────────┘    │
│                          │                              │
│                          ▼                              │
│  ┌────────────────────────────────────────────────┐    │
│  │  _needs_signing(url)                           │    │
│  │  - Check valve enabled                         │    │
│  │  - Check credentials configured                │    │
│  │  - Detect existing X-Amz-* parameters          │    │
│  │  - Match against PRIVATE_PATH_PATTERNS         │    │
│  └────────────────────────────────────────────────┘    │
│                          │                              │
│                          ▼                              │
│  ┌────────────────────────────────────────────────┐    │
│  │  _generate_presigned_url(url)                  │    │
│  │  - Initialize S3 client (lazy load)            │    │
│  │  - Extract bucket and key from URL             │    │
│  │  - Call boto3 generate_presigned_url()         │    │
│  │  - Return signed URL or None on failure        │    │
│  └────────────────────────────────────────────────┘    │
│                          │                              │
│                          ▼                              │
│  ┌────────────────────────────────────────────────┐    │
│  │  boto3 S3 Client                               │    │
│  │  - Endpoint: DO Spaces API                     │    │
│  │  - Credentials: Access/Secret Keys             │    │
│  │  - Region: nyc3/sfo3/etc.                      │    │
│  └────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  Digital Ocean Spaces API                               │
│  - S3-compatible object storage                         │
│  - Validates presigned URL signature                    │
│  - Returns image content if valid                       │
└─────────────────────────────────────────────────────────┘
```

### Data Flow

```
1. Agent Response with Image URLs
   │
   ▼
2. _extract_image_urls() extracts URLs
   │
   ▼
3. For each URL:
   │
   ├─▶ _needs_signing(url)
   │   │
   │   ├─▶ Check ENABLE_PRESIGNED_URLS valve
   │   ├─▶ Check credentials configured
   │   ├─▶ Check for existing X-Amz-* params
   │   └─▶ Check PRIVATE_PATH_PATTERNS
   │
   ├─▶ If needs signing:
   │   │
   │   └─▶ _generate_presigned_url(url)
   │       │
   │       ├─▶ _get_s3_client() (lazy init)
   │       ├─▶ _extract_bucket_and_key(url)
   │       ├─▶ boto3.generate_presigned_url()
   │       │   - Bucket: extracted or configured
   │       │   - Key: object path
   │       │   - ExpiresIn: valve setting
   │       │
   │       └─▶ Return signed URL or None
   │
   └─▶ If signing failed (None returned):
       └─▶ Skip image (continue to next)
   │
   ▼
4. Append valid URLs to image_urls list
   │
   ▼
5. Format as markdown and return to user
```

### URL Detection Logic (Smart Detection)

```python
def _needs_signing(url: str) -> bool:
    """
    Decision tree for URL signing:

    1. Is ENABLE_PRESIGNED_URLS enabled?
       NO  → Return False (skip signing)
       YES → Continue

    2. Are credentials configured?
       NO  → Return False (can't sign)
       YES → Continue

    3. Does URL have X-Amz-* parameters?
       YES → Return False (already signed)
       NO  → Continue

    4. Does URL match PRIVATE_PATH_PATTERNS?
       YES → Return True (sign it)
       NO  → Return False (public URL)
    """
```

### Presigned URL Format

**Input URL:**
```
https://my-bucket.nyc3.digitaloceanspaces.com/private/docs/chart.png
```

**Output Presigned URL:**
```
https://my-bucket.nyc3.digitaloceanspaces.com/private/docs/chart.png?
  X-Amz-Algorithm=AWS4-HMAC-SHA256&
  X-Amz-Credential=ACCESS_KEY%2F20250121%2Fnyc3%2Fs3%2Faws4_request&
  X-Amz-Date=20250121T120000Z&
  X-Amz-Expires=3600&
  X-Amz-SignedHeaders=host&
  X-Amz-Signature=abc123...
```

---

## Implementation Phases

### Phase 1: Configuration & Setup (Tasks 1-2)
**Duration**: 30 minutes
**Archon Tasks**:
- `b25592eb-b1c0-4a76-abb4-0d132eec50eb` - Add configuration valves
- `5b48c9af-0607-41a7-a36a-94720153521d` - Update dependencies

**Deliverables**:
- New Valves fields added to Pipe class
- boto3 dependency added to requirements
- Imports updated with boto3 and botocore

**Validation**:
- Valves appear in Open WebUI admin interface
- No import errors when loading pipe

---

### Phase 2: Core Infrastructure (Task 3)
**Duration**: 45 minutes
**Archon Task**:
- `9e059f0f-e103-48b6-a603-b2d8a03b6842` - Implement S3 client initialization

**Deliverables**:
- `_s3_client` property in `__init__`
- `_get_s3_client()` method with lazy loading
- Credential validation logic
- Debug logging for initialization

**Validation**:
- S3 client initializes successfully with valid credentials
- Returns None gracefully with missing credentials
- Debug logs show initialization status

---

### Phase 3: Detection Logic (Task 4)
**Duration**: 1 hour
**Archon Task**:
- `78f70915-c244-4d98-b8ee-ec3d20efcab5` - Implement smart URL detection

**Deliverables**:
- `_needs_signing(url)` method
- `_extract_bucket_and_key(url)` method
- Comprehensive debug logging

**Validation**:
- Correctly identifies private URLs
- Skips already-signed URLs
- Parses bucket/key from various URL formats
- Debug logs show decision points

---

### Phase 4: Signing Implementation (Task 5)
**Duration**: 1 hour
**Archon Task**:
- `5e3ced78-22cf-4856-801c-13280059262d` - Implement presigned URL generation

**Deliverables**:
- `_generate_presigned_url(url)` method
- Error handling for boto3 exceptions
- Debug logging for signing operations

**Validation**:
- Generates valid presigned URLs
- Handles ClientError/BotoCoreError gracefully
- Returns None on failures
- Debug logs show signing details

---

### Phase 5: Integration (Task 6)
**Duration**: 45 minutes
**Archon Task**:
- `590ef8da-5b6d-48cc-9cbd-7f08ec85465b` - Integrate signing into workflow

**Deliverables**:
- Modified `_extract_image_urls()` method
- Signing logic integrated into deduplication loop
- Existing functionality preserved

**Validation**:
- Private URLs get signed
- Public URLs pass through unchanged
- Mixed URLs work correctly
- Deduplication still functions

---

### Phase 6: Documentation (Tasks 7-8)
**Duration**: 2 hours
**Archon Tasks**:
- `6a8ae888-2ff3-4f00-8cc6-b5b82a44595e` - Update pipe documentation
- `4e66b339-959d-4cfc-b386-c19b738a7de2` - Create testing documentation

**Deliverables**:
- Updated docstring in pipe file (version 9.0.0)
- New `pipes/README-URL-SIGNING.md` file
- Configuration examples
- Troubleshooting guide

**Validation**:
- Documentation is clear and comprehensive
- Examples are accurate and runnable
- All new valves documented

---

### Phase 7: Testing (Tasks 9-10)
**Duration**: 2 hours
**Archon Tasks**:
- `b9b930bd-df5d-4061-80fa-adfd9f2ebf41` - Create test utility script
- `9a8576e9-80eb-4578-85a1-bcba0e30a774` - Perform integration testing

**Deliverables**:
- `pipes/test-presigned-urls.py` utility
- Test results documentation
- Bug fixes for any issues found

**Validation**:
- All test scenarios pass
- No regressions detected
- Performance is acceptable

---

## Task Breakdown

### Task 1: Add Configuration Valves
**Archon Task ID**: `b25592eb-b1c0-4a76-abb4-0d132eec50eb`
**Priority**: 100
**Estimated Time**: 15 minutes

**Implementation Details**:

Add to `Pipe.Valves` class:

```python
# Presigned URL Support Configuration
ENABLE_PRESIGNED_URLS: bool = Field(
    default=False,
    description="Enable automatic signing of private image URLs from Digital Ocean Spaces"
)

DO_SPACES_ACCESS_KEY: str = Field(
    default="",
    description="Digital Ocean Spaces access key for presigned URL generation (leave empty to disable)"
)

DO_SPACES_SECRET_KEY: str = Field(
    default="",
    description="Digital Ocean Spaces secret key for presigned URL generation (leave empty to disable)"
)

DO_SPACES_REGION: str = Field(
    default="nyc3",
    description="Digital Ocean Spaces region (e.g., nyc3, sfo3, ams3, sgp1, fra1)"
)

DO_SPACES_BUCKET: str = Field(
    default="",
    description="Digital Ocean Spaces bucket name (optional, auto-detected from URLs if empty)"
)

PRESIGNED_URL_EXPIRATION: int = Field(
    default=3600,
    description="Presigned URL expiration time in seconds (default: 3600 = 1 hour, max: 604800 = 7 days)"
)

PRIVATE_PATH_PATTERNS: str = Field(
    default="/private/,/protected/,/docs/",
    description="Comma-separated path patterns that indicate private URLs needing signatures (e.g., /private/,/protected/)"
)
```

**Testing**:
- Load pipe in Open WebUI
- Verify all valves appear in admin interface
- Check default values are correct

---

### Task 2: Update Dependencies and Imports
**Archon Task ID**: `5b48c9af-0607-41a7-a36a-94720153521d`
**Priority**: 90
**Estimated Time**: 15 minutes

**Implementation Details**:

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
- Check boto3 version compatibility

---

### Task 3: Implement S3 Client Initialization
**Archon Task ID**: `9e059f0f-e103-48b6-a603-b2d8a03b6842`
**Priority**: 80
**Estimated Time**: 45 minutes

**Implementation Details**:

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
            print(f"[DEBUG] S3 client initialized successfully")
            print(f"[DEBUG] Region: {self.valves.DO_SPACES_REGION}")
            print(f"[DEBUG] Endpoint: https://{self.valves.DO_SPACES_REGION}.digitaloceanspaces.com")

        return self._s3_client
    except Exception as e:
        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] Failed to initialize S3 client: {e}")
        return None
```

**Testing**:
- Initialize with valid credentials → client created
- Initialize with missing credentials → returns None
- Initialize with invalid region → logs error, returns None
- Check debug logs show correct information

---

### Task 4: Implement Smart URL Detection Logic
**Archon Task ID**: `78f70915-c244-4d98-b8ee-ec3d20efcab5`
**Priority**: 70
**Estimated Time**: 1 hour

**Implementation Details**:

Add methods:

```python
def _needs_signing(self, url: str) -> bool:
    """
    Smart detection: Determine if URL needs presigned signature.

    Returns True if:
    1. Presigned URLs are enabled via valve
    2. URL is not already signed (no X-Amz-* parameters)
    3. URL matches private path patterns

    Args:
        url: Image URL to check

    Returns:
        True if URL should be signed, False otherwise
    """
    # Feature disabled
    if not self.valves.ENABLE_PRESIGNED_URLS:
        if self.valves.DEBUG_MODE:
            print("[DEBUG] Presigned URLs disabled via valve")
        return False

    # No credentials configured
    if not self.valves.DO_SPACES_ACCESS_KEY or not self.valves.DO_SPACES_SECRET_KEY:
        if self.valves.DEBUG_MODE:
            print("[DEBUG] Cannot sign URLs: credentials not configured")
        return False

    # Already has presigned parameters
    x_amz_params = ['X-Amz-Algorithm', 'X-Amz-Credential', 'X-Amz-Signature',
                    'X-Amz-Date', 'X-Amz-Expires', 'X-Amz-SignedHeaders']
    if any(param in url for param in x_amz_params):
        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] URL already signed, skipping: {url[:80]}...")
        return False

    # Check if URL matches private path patterns
    private_patterns = [p.strip() for p in self.valves.PRIVATE_PATH_PATTERNS.split(',')]
    is_private = any(pattern in url for pattern in private_patterns if pattern)

    if self.valves.DEBUG_MODE:
        if is_private:
            print(f"[DEBUG] URL matches private pattern, needs signing: {url[:80]}...")
        else:
            print(f"[DEBUG] URL is public, no signing needed: {url[:80]}...")

    return is_private

def _extract_bucket_and_key(self, url: str) -> tuple:
    """
    Extract bucket name and object key from Digital Ocean Spaces URL.

    Supports formats:
    - https://BUCKET.REGION.digitaloceanspaces.com/path/to/file.png
    - https://BUCKET.REGION.digitaloceanspaces.com/path/to/file.png?existing=params

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
                    print(f"[DEBUG] Extracted bucket: {bucket}")
                    print(f"[DEBUG] Extracted key: {key}")

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
- Test with public URL → returns False
- Test with private URL → returns True
- Test with already-signed URL → returns False
- Test bucket/key extraction with various URL formats
- Verify debug logs are comprehensive

---

### Task 5: Implement Presigned URL Generation
**Archon Task ID**: `5e3ced78-22cf-4856-801c-13280059262d`
**Priority**: 60
**Estimated Time**: 1 hour

**Implementation Details**:

```python
def _generate_presigned_url(self, url: str) -> Optional[str]:
    """
    Generate presigned URL for private Digital Ocean Spaces object.

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

    # Use configured bucket if specified, otherwise use extracted bucket
    target_bucket = self.valves.DO_SPACES_BUCKET if self.valves.DO_SPACES_BUCKET else bucket

    if self.valves.DEBUG_MODE:
        print(f"[DEBUG] Generating presigned URL for: {target_bucket}/{key}")
        print(f"[DEBUG] Expiration: {self.valves.PRESIGNED_URL_EXPIRATION} seconds")

    try:
        presigned_url = s3_client.generate_presigned_url(
            ClientMethod='get_object',
            Params={
                'Bucket': target_bucket,
                'Key': key,
            },
            ExpiresIn=self.valves.PRESIGNED_URL_EXPIRATION
        )

        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] Successfully generated presigned URL")
            print(f"[DEBUG] URL length: {len(presigned_url)} characters")

        return presigned_url

    except ClientError as e:
        if self.valves.DEBUG_MODE:
            error_code = e.response.get('Error', {}).get('Code', 'Unknown')
            error_msg = e.response.get('Error', {}).get('Message', str(e))
            print(f"[DEBUG] AWS ClientError generating presigned URL: {error_code} - {error_msg}")
        return None

    except BotoCoreError as e:
        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] BotoCoreError generating presigned URL: {str(e)}")
        return None

    except Exception as e:
        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] Unexpected error generating presigned URL: {type(e).__name__} - {str(e)}")
        return None
```

**Testing**:
- Generate presigned URL with valid credentials → success
- Generate with invalid credentials → returns None, logs error
- Generate with malformed URL → returns None
- Verify generated URL contains X-Amz-* parameters
- Test with configured bucket override
- Check expiration time is correct

---

### Task 6: Integrate Signing into Image Extraction
**Archon Task ID**: `590ef8da-5b6d-48cc-9cbd-7f08ec85465b`
**Priority**: 50
**Estimated Time**: 45 minutes

**Implementation Details**:

Modify `_extract_image_urls()` method (starting around line 530):

```python
def _extract_image_urls(self, text: str) -> List[str]:
    """
    Extract image URLs from text using configured pattern.

    Supports:
    - Plain URLs in text
    - URLs in markdown links: [text](url)
    - URLs in markdown images: ![alt](url)
    - Presigned URLs with query parameters
    - **NEW: Automatic presigned URL generation for private images**

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
                        print(f"[DEBUG] Attempting to sign private URL: {url[:80]}...")

                    signed_url = self._generate_presigned_url(url)

                    # Skip image if signing failed (per error handling strategy)
                    if signed_url is None:
                        if self.valves.DEBUG_MODE:
                            print(f"[DEBUG] Signing failed, skipping image: {url[:80]}...")
                        continue

                    # Use signed URL
                    if self.valves.DEBUG_MODE:
                        print(f"[DEBUG] Using presigned URL for private image")
                    url = signed_url

                seen.add(url)
                image_urls.append(url)

                # Respect max images limit
                if len(image_urls) >= self.valves.MAX_IMAGES_PER_RESPONSE:
                    break

        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] Extracted {len(image_urls)} image URLs (after deduplication and signing)")
            if image_urls:
                print(f"[DEBUG] First URL: {image_urls[0][:100]}...")

    except Exception as e:
        if self.valves.DEBUG_MODE:
            print(f"[DEBUG] Error extracting image URLs: {type(e).__name__} - {str(e)}")

    return image_urls
```

**Testing**:
- Test with all public URLs → no signing, all displayed
- Test with all private URLs → all signed, all displayed
- Test with mixed public/private → correct URLs signed
- Test with signing failure → image skipped, pipe continues
- Verify deduplication still works
- Check max images limit still applies

---

### Task 7: Update Pipe Documentation
**Archon Task ID**: `6a8ae888-2ff3-4f00-8cc6-b5b82a44595e`
**Priority**: 40
**Estimated Time**: 1 hour

**Implementation Details**:

Update docstring at top of file:

```python
"""
title: Digital Ocean Function Pipe with KB Image Support
author: open-webui
date: 2025-01-21
version: 9.0.0
license: MIT
description: Full-featured DO pipe with automatic image URL extraction, display, and presigned URL support for private images
required_open_webui_version: 0.3.9
requirements: requests, boto3

KEY FEATURES:
- JSON-aware task handling (title/follow-up generation)
- Streaming and non-streaming support
- Optional system notification on first response
- **Automatic image URL detection from agent responses**
- **Smart deduplication prevents duplicate images** (always enabled)
- **NEW: Presigned URL generation for private Digital Ocean Spaces images**
- Extracts DO Spaces URLs (public and presigned) from text
- Displays images as markdown at end of response
- Works with OpenSearch knowledge base image metadata

PRESIGNED URL SUPPORT (NEW IN v9.0):
1. Enable via ENABLE_PRESIGNED_URLS valve (default: False)
2. Configure Digital Ocean Spaces credentials:
   - DO_SPACES_ACCESS_KEY: Your Spaces access key
   - DO_SPACES_SECRET_KEY: Your Spaces secret key
   - DO_SPACES_REGION: Region (default: nyc3)
   - DO_SPACES_BUCKET: Bucket name (optional, auto-detected)
3. Define private path patterns via PRIVATE_PATH_PATTERNS valve
   - Default: "/private/,/protected/,/docs/"
   - URLs matching these patterns will be signed
4. Set expiration time via PRESIGNED_URL_EXPIRATION valve
   - Default: 3600 seconds (1 hour)
   - Max: 604800 seconds (7 days)

Smart Detection Features:
- Automatically skips URLs already signed (with X-Amz-* parameters)
- Only signs URLs matching PRIVATE_PATH_PATTERNS
- Gracefully handles errors by skipping failed images
- Zero impact on public URLs when disabled

HOW IT WORKS:
1. DO agent queries OpenSearch knowledge base
2. Retrieves chunks with image_url in metadata
3. Agent includes image URLs in response text (e.g., "See chart at https://...")
4. Pipe extracts URLs using regex pattern
5. **NEW: Pipe checks if URLs need presigned signatures via _needs_signing()**
6. **NEW: Generates presigned URLs for private images with _generate_presigned_url()**
7. Pipe checks if URLs are already embedded by agent (smart deduplication)
8. Converts non-embedded URLs to markdown images
9. Appends images to response (no duplicates)

CONFIGURATION VALVES:

Image Detection:
- ENABLE_KB_IMAGE_DETECTION: Toggle automatic image detection (default: True)
- IMAGE_URL_PATTERN: Regex for detecting image URLs (default: DO Spaces URLs)
- MAX_IMAGES_PER_RESPONSE: Limit number of images displayed (default: 10)

Presigned URLs (NEW):
- ENABLE_PRESIGNED_URLS: Toggle presigned URL generation (default: False)
- DO_SPACES_ACCESS_KEY: Access key for signing (required if enabled)
- DO_SPACES_SECRET_KEY: Secret key for signing (required if enabled)
- DO_SPACES_REGION: Spaces region (default: nyc3)
- DO_SPACES_BUCKET: Bucket name (optional, auto-detected from URLs)
- PRESIGNED_URL_EXPIRATION: URL expiration in seconds (default: 3600)
- PRIVATE_PATH_PATTERNS: Comma-separated path patterns requiring signatures

Other:
- DIGITALOCEAN_FUNCTION_URL: DO agent endpoint URL
- DIGITALOCEAN_FUNCTION_TOKEN: DO agent access token
- REQUEST_TIMEOUT_SECONDS: Request timeout (default: 120)
- VERIFY_SSL: Verify SSL certificates (default: True)
- ENABLE_STREAMING: Enable streaming responses (default: True)
- ENABLE_SYSTEM_NOTIFICATION: Show system notification on first response (default: False)
- SYSTEM_NOTIFICATION_MESSAGE: Custom notification message
- DEBUG_MODE: Enable debug logging (default: False)

SECURITY NOTES:
- Access/secret keys are stored securely in Open WebUI valves
- Presigned URLs expire after configured time (default: 1 hour)
- Only GET operations supported (no PUT/DELETE)
- Failed signing attempts are logged in DEBUG_MODE
- URLs are never signed twice (existing signatures preserved)

Note: Smart deduplication is always enabled - images embedded by the agent will not be duplicated.
"""
```

**Testing**:
- Documentation is accurate and complete
- All valves are documented
- Examples are clear
- Security notes are present

---

### Task 8: Create Testing Documentation
**Archon Task ID**: `4e66b339-959d-4cfc-b386-c19b738a7de2`
**Priority**: 30
**Estimated Time**: 1 hour

**Implementation Details**:

Create `pipes/README-URL-SIGNING.md` - see separate file creation below.

**Testing**:
- Follow documentation to configure feature
- Run example scenarios
- Verify troubleshooting guide is helpful

---

### Task 9: Create Test Utility Script
**Archon Task ID**: `b9b930bd-df5d-4061-80fa-adfd9f2ebf41`
**Priority**: 20
**Estimated Time**: 1 hour

**Implementation Details**:

Create `pipes/test-presigned-urls.py` - see separate file creation below.

**Testing**:
- Run script with various inputs
- Verify all test cases pass
- Check error messages are clear

---

### Task 10: Perform Comprehensive Integration Testing
**Archon Task ID**: `9a8576e9-80eb-4578-85a1-bcba0e30a774`
**Priority**: 10
**Estimated Time**: 2 hours

**Test Scenarios**:

#### Scenario 1: Public URLs (No Signing)
**Setup**:
- ENABLE_PRESIGNED_URLS = False

**Test**:
- Agent returns public image URLs
- Expected: URLs pass through unchanged
- Expected: Images display correctly

#### Scenario 2: Private URLs (Signing Enabled)
**Setup**:
- ENABLE_PRESIGNED_URLS = True
- Valid credentials configured
- URLs match PRIVATE_PATH_PATTERNS

**Test**:
- Agent returns private image URLs
- Expected: URLs get signed with X-Amz-* parameters
- Expected: Signed URLs load images successfully
- Expected: URLs expire after configured time

#### Scenario 3: Already Signed URLs
**Setup**:
- ENABLE_PRESIGNED_URLS = True
- Agent returns URLs with existing X-Amz-* parameters

**Test**:
- Expected: URLs are NOT re-signed
- Expected: Original URLs used as-is
- Expected: Images display correctly

#### Scenario 4: Mixed Public/Private
**Setup**:
- ENABLE_PRESIGNED_URLS = True
- Agent returns both public and private URLs

**Test**:
- Expected: Only private URLs (matching patterns) get signed
- Expected: Public URLs pass through unchanged
- Expected: All images display correctly

#### Scenario 5: Error Handling - Invalid Credentials
**Setup**:
- ENABLE_PRESIGNED_URLS = True
- Invalid credentials configured

**Test**:
- Agent returns private URLs
- Expected: Signing fails gracefully
- Expected: Images are skipped (not displayed)
- Expected: Pipe continues to function
- Expected: No exceptions thrown

#### Scenario 6: Error Handling - Malformed URLs
**Setup**:
- ENABLE_PRESIGNED_URLS = True
- Valid credentials
- Agent returns malformed URLs

**Test**:
- Expected: Bucket/key extraction fails
- Expected: Images skipped
- Expected: Other valid images still displayed

#### Scenario 7: URL Expiration
**Setup**:
- ENABLE_PRESIGNED_URLS = True
- PRESIGNED_URL_EXPIRATION = 60 (1 minute for testing)

**Test**:
- Generate presigned URL
- Test: Access immediately → 200 OK
- Wait 2 minutes
- Test: Access again → 403 Forbidden

#### Scenario 8: Debug Mode
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

#### Scenario 9: Performance
**Setup**:
- Response with 10 private images

**Test**:
- Measure time to process response
- Expected: < 1 second total signing time
- Expected: ~100ms per URL
- Expected: No timeout errors

#### Scenario 10: Valve Changes
**Setup**:
- Initial: ENABLE_PRESIGNED_URLS = True

**Test**:
- Change to False in admin UI
- Expected: Feature disables immediately
- Expected: No restart required
- Expected: URLs pass through unsigned

**Test Results Documentation Template**:

```markdown
# Presigned URL Feature Test Results

**Date**: YYYY-MM-DD
**Tester**: Name
**Environment**: Production/Test

## Test Summary
- Total Scenarios: 10
- Passed: X
- Failed: Y
- Blocked: Z

## Detailed Results

### Scenario 1: Public URLs
- Status: PASS/FAIL
- Notes: ...

### Scenario 2: Private URLs
- Status: PASS/FAIL
- Notes: ...

[... continue for all scenarios ...]

## Issues Found
1. Issue description
   - Severity: Critical/High/Medium/Low
   - Steps to reproduce: ...
   - Expected: ...
   - Actual: ...

## Performance Metrics
- Average signing time per URL: Xms
- Total response processing time: Xms
- Memory usage: XMB

## Recommendations
- ...
```

---

## Security Considerations

### Credential Management
**Risk**: Credentials stored in valves could be exposed
**Mitigation**:
- Valves are stored encrypted in Open WebUI database
- Only admins can view/edit valve values
- Credentials never logged (even in DEBUG_MODE)
- Use read-only Spaces keys (no PUT/DELETE permissions needed)

### URL Expiration
**Risk**: Long expiration times increase exposure window
**Mitigation**:
- Default expiration: 1 hour (reasonable for typical use)
- Maximum expiration: 7 days (AWS S3 limitation)
- Recommend shortest practical expiration for use case
- Document expiration best practices

### Least Privilege
**Risk**: Overly permissive access keys
**Mitigation**:
- Only GET operations used (get_object only)
- No PUT/DELETE presigned URLs generated
- Recommend creating dedicated read-only Spaces keys
- Document principle of least privilege in README

### URL Leakage
**Risk**: Presigned URLs are bearer tokens
**Mitigation**:
- URLs only visible to authenticated Open WebUI users
- URLs transmitted over HTTPS only
- Expiration limits exposure window
- Document: treat URLs as sensitive

### Error Information Disclosure
**Risk**: Error messages leak sensitive information
**Mitigation**:
- Generic error messages to users
- Detailed errors only in DEBUG_MODE
- No credentials in error messages
- Sanitize URLs in logs (truncate to 80 chars)

### Dependency Vulnerabilities
**Risk**: boto3 vulnerabilities
**Mitigation**:
- Document minimum boto3 version
- Recommend regular dependency updates
- Monitor security advisories

---

## Testing Strategy

### Unit Tests
**Scope**: Individual methods in isolation

**Tests**:
1. `_needs_signing()` returns correct boolean for various inputs
2. `_extract_bucket_and_key()` parses URLs correctly
3. `_generate_presigned_url()` creates valid signatures
4. `_get_s3_client()` initializes correctly or returns None

**Tools**: Python unittest or pytest

### Integration Tests
**Scope**: End-to-end feature functionality

**Tests**:
1. Public URLs pass through unchanged
2. Private URLs get signed
3. Mixed URLs handled correctly
4. Error conditions handled gracefully
5. Deduplication still works
6. Max images limit respected

**Tools**: Manual testing in Open WebUI

### Performance Tests
**Scope**: Latency and resource usage

**Metrics**:
- Time to sign single URL
- Time to sign 10 URLs
- Memory usage increase
- No timeout errors with slow network

**Acceptance Criteria**:
- < 100ms per URL signing
- < 50MB memory increase
- No timeouts with 120s request timeout

### Security Tests
**Scope**: Credential security and access control

**Tests**:
1. Invalid credentials fail gracefully
2. Expired URLs return 403
3. No credentials leaked in logs
4. Least privilege verified (GET only)

---

## Deployment Plan

### Pre-Deployment Checklist
- [ ] All Archon tasks completed
- [ ] Code review completed
- [ ] All tests passing
- [ ] Documentation updated
- [ ] Security review completed
- [ ] Performance benchmarks acceptable

### Deployment Steps

#### Step 1: Branch Merge
```bash
# Ensure all changes committed
git status

# Switch to main branch
git checkout main

# Merge feature branch
git merge feat/url-signing

# Push to remote
git push origin main
```

#### Step 2: Tag Release
```bash
# Create version tag
git tag -a v9.0.0 -m "Add presigned URL support for private images"

# Push tag
git push origin v9.0.0
```

#### Step 3: Update Production Pipe
1. Copy updated `do-function-pipe-with-kb-images.py` to Open WebUI
2. In Open WebUI admin:
   - Navigate to Functions
   - Update existing function or create new
   - Paste updated code
   - Save

#### Step 4: Configure Valves (Production)
1. Open function settings in Open WebUI admin
2. Configure valves:
   ```
   ENABLE_PRESIGNED_URLS: False (initially disabled)
   DO_SPACES_ACCESS_KEY: <production_key>
   DO_SPACES_SECRET_KEY: <production_secret>
   DO_SPACES_REGION: nyc3
   DO_SPACES_BUCKET: <optional>
   PRESIGNED_URL_EXPIRATION: 3600
   PRIVATE_PATH_PATTERNS: /private/,/protected/,/docs/
   DEBUG_MODE: False
   ```
3. Save configuration

#### Step 5: Smoke Test (Production)
1. Test with public URLs (feature disabled)
2. Enable ENABLE_PRESIGNED_URLS valve
3. Test with private URLs
4. Verify images display correctly
5. Check no errors in logs

#### Step 6: Gradual Rollout
- Week 1: Enable for test users only
- Week 2: Enable for 50% of users
- Week 3: Enable for all users
- Monitor: Error rates, performance, user feedback

---

## Rollback Procedure

### Quick Rollback (Emergency)
If critical issues discovered:

1. **Disable Feature**:
   - Open WebUI admin → Function settings
   - Set `ENABLE_PRESIGNED_URLS = False`
   - Save
   - Feature immediately disabled, no restart needed

2. **Verify**: Public URLs still work correctly

### Full Rollback
If valve disable insufficient:

1. **Restore Previous Version**:
   ```bash
   # Checkout previous tag
   git checkout v8.1.0

   # Copy previous version
   cp pipes/do-function-pipe-with-kb-images.py /path/to/openwebui/
   ```

2. **Update Function**: Paste v8.1.0 code in Open WebUI admin

3. **Test**: Verify basic functionality restored

### Rollback Communication
- Notify users of temporary feature unavailability
- Document issue for post-mortem
- Create bug report with details

---

## Success Criteria

### Functional Success
- ✅ Private image URLs are automatically signed
- ✅ Public image URLs work without changes
- ✅ Mixed public/private URLs handled correctly
- ✅ Already-signed URLs not re-signed
- ✅ Error conditions handled gracefully
- ✅ Feature can be enabled/disabled via valve

### Technical Success
- ✅ All 10 Archon tasks completed
- ✅ All test scenarios pass
- ✅ Zero regressions in existing functionality
- ✅ Code follows existing patterns and style
- ✅ Debug logging comprehensive and useful
- ✅ Documentation complete and accurate

### Performance Success
- ✅ < 100ms per URL signing operation
- ✅ < 1 second total for 10 URLs
- ✅ No increase in error rate
- ✅ No timeout issues

### Security Success
- ✅ Credentials stored securely (valves)
- ✅ No credentials in logs or error messages
- ✅ Least privilege verified (GET only)
- ✅ URL expiration configurable
- ✅ Security review completed

### User Success
- ✅ Private images display correctly for users
- ✅ No manual URL management required
- ✅ Feature is transparent to end users
- ✅ Clear documentation for administrators

---

## Appendix A: Configuration Examples

### Example 1: Development Environment
```python
ENABLE_PRESIGNED_URLS: True
DO_SPACES_ACCESS_KEY: "DO00XXXXXXXXXXXX"
DO_SPACES_SECRET_KEY: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
DO_SPACES_REGION: "nyc3"
DO_SPACES_BUCKET: "dev-bucket"
PRESIGNED_URL_EXPIRATION: 7200  # 2 hours for development
PRIVATE_PATH_PATTERNS: "/private/,/test/"
DEBUG_MODE: True  # Enable detailed logging
```

### Example 2: Production Environment
```python
ENABLE_PRESIGNED_URLS: True
DO_SPACES_ACCESS_KEY: "DO00YYYYYYYYYYYY"
DO_SPACES_SECRET_KEY: "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy"
DO_SPACES_REGION: "nyc3"
DO_SPACES_BUCKET: "prod-kb-images"
PRESIGNED_URL_EXPIRATION: 3600  # 1 hour for production
PRIVATE_PATH_PATTERNS: "/private/,/protected/,/confidential/"
DEBUG_MODE: False  # Disable debug logging in production
```

### Example 3: Multi-Region Setup
```python
# Region auto-detected from URLs, no BUCKET override
ENABLE_PRESIGNED_URLS: True
DO_SPACES_ACCESS_KEY: "DO00ZZZZZZZZZZZZ"
DO_SPACES_SECRET_KEY: "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"
DO_SPACES_REGION: "nyc3"  # Default region
DO_SPACES_BUCKET: ""  # Auto-detect from URLs
PRESIGNED_URL_EXPIRATION: 3600
PRIVATE_PATH_PATTERNS: "/secure/,/internal/"
DEBUG_MODE: False
```

---

## Appendix B: Troubleshooting Guide

### Issue: Images not displaying

**Symptom**: Private images show broken image icon

**Diagnosis**:
1. Check DEBUG_MODE logs for signing errors
2. Verify ENABLE_PRESIGNED_URLS = True
3. Verify credentials configured
4. Check URL matches PRIVATE_PATH_PATTERNS

**Resolution**:
- Ensure valid credentials configured
- Verify bucket/region settings
- Check URL patterns match

### Issue: "S3 client not initialized"

**Symptom**: Debug logs show S3 client initialization failure

**Diagnosis**:
- Check DO_SPACES_ACCESS_KEY is set
- Check DO_SPACES_SECRET_KEY is set
- Verify credentials format (starts with "DO00")

**Resolution**:
- Generate new Spaces access keys from DO dashboard
- Update valves with correct credentials

### Issue: "403 Forbidden" on image load

**Symptom**: Presigned URL generates but image fails to load

**Diagnosis**:
1. Check if URL expired (compare timestamp to PRESIGNED_URL_EXPIRATION)
2. Verify bucket permissions (must allow public GET with signature)
3. Check CORS settings on bucket

**Resolution**:
- Increase expiration time if URLs expire too quickly
- Verify bucket CORS allows image loading from Open WebUI domain

### Issue: URLs being re-signed unnecessarily

**Symptom**: Already-signed URLs getting new signatures

**Diagnosis**:
- Check if X-Amz-* parameters present in original URL
- Review _needs_signing() logic

**Resolution**:
- Verify detection logic checks for X-Amz-* params
- Report bug if detection fails

### Issue: Performance degradation

**Symptom**: Slow response times with signing enabled

**Diagnosis**:
1. Enable DEBUG_MODE to measure signing time per URL
2. Check network latency to DO Spaces API
3. Verify no timeout errors in logs

**Resolution**:
- Use same region as Open WebUI deployment
- Consider caching signed URLs (future enhancement)
- Report issue if signing takes > 100ms per URL

---

## Appendix C: Related Resources

### Digital Ocean Documentation
- [Spaces Access Keys](https://docs.digitalocean.com/products/spaces/how-to/manage-access/)
- [S3 SDK Compatibility](https://docs.digitalocean.com/products/spaces/how-to/use-aws-sdks/)
- [Presigned URLs](https://docs.digitalocean.com/products/spaces/how-to/set-file-permissions/)

### boto3 Documentation
- [generate_presigned_url API](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/s3/client/generate_presigned_url.html)
- [S3 Client Configuration](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/s3.html)

### Open WebUI Documentation
- [Function Pipes](https://docs.openwebui.com/pipelines/)
- [Valve Configuration](https://docs.openwebui.com/pipelines/valves/)

### Security Best Practices
- [AWS S3 Presigned URL Security](https://docs.aws.amazon.com/prescriptive-guidance/latest/presigned-url-best-practices/)
- [Least Privilege Access](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html#grant-least-privilege)

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-01-21 | Claude | Initial plan created |

---

**End of Implementation Plan**
