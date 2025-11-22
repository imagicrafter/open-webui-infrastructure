# Preprocessing App Integration Guide
## Digital Ocean Spaces Private Bucket Support

**Document Version**: 1.0
**Date**: 2025-01-22
**Related Feature**: Presigned URL Support (Pipe v9.0.0)
**Target App**: Document Preprocessing & Knowledge Base Indexing App

---

## Overview

This guide provides specifications for the preprocessing app to properly store images in **private Digital Ocean Spaces buckets** while ensuring the Open WebUI pipe can automatically generate presigned URLs for display.

### What Changed

**Previous (Public Buckets)**:
- Images stored in public Digital Ocean Spaces buckets
- URLs directly accessible without authentication
- Image URLs stored in chunk metadata worked immediately

**New (Private Buckets)**:
- Images stored in private Digital Ocean Spaces buckets
- URLs require AWS Signature V4 for temporary access
- Pipe automatically generates presigned URLs when configured
- **NO CHANGES REQUIRED** to preprocessing app code!

---

## Key Insight: Zero Code Changes Required

**The preprocessing app does NOT need to change how it stores image URLs!**

### Why?

The Open WebUI pipe (v9.0.0+) now has built-in presigned URL generation that:
1. **Detects** Digital Ocean Spaces URLs automatically
2. **Checks** if signing is enabled via valves
3. **Generates** presigned URLs transparently
4. **Falls back** gracefully if signing fails or is disabled

### Workflow

```
Preprocessing App                    DO Spaces              Open WebUI Pipe
─────────────────                    ─────────              ───────────────
1. Generate image
   from document

2. Upload to private  ──────────▶   Store in
   DO Spaces bucket                 private bucket

3. Get standard URL
   (no presigning)     ◀──────────  Return URL

4. Store plain URL
   in chunk metadata

5. Index chunk in
   knowledge base

                       [User queries knowledge base]

                                                    6. Extract URL
                                                       from chunk

                                                    7. Detect private
                                                       DO Spaces URL

                                                    8. Generate
                                                       presigned URL

                                                    9. Display image
                                                       to user
```

---

## Bucket Configuration Requirements

### Digital Ocean Spaces Setup

#### 1. Create Private Bucket

```bash
# Via DO Console or API
bucket_name="your-knowledge-base-images"
region="nyc3"  # or sfo3, ams3, etc.
acl="private"  # IMPORTANT: Must be private
```

#### 2. Create Read-Only Access Keys

Generate dedicated Spaces access keys for Open WebUI:

```bash
# Via Digital Ocean Console:
# API → Spaces Keys → Generate New Key

# Permissions: Read-only (GET objects only)
# Scope: Limited to specific bucket (recommended)

DO_SPACES_ACCESS_KEY="DO00XXXXXXXXXXXXXXXXXXXX"
DO_SPACES_SECRET_KEY="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

#### 3. Bucket CORS Configuration (Optional)

If serving images to web browsers:

```json
{
  "CORSRules": [
    {
      "AllowedOrigins": ["https://your-openwebui-domain.com"],
      "AllowedMethods": ["GET", "HEAD"],
      "AllowedHeaders": ["*"],
      "MaxAgeSeconds": 3600
    }
  ]
}
```

---

## Image URL Format Requirements

### Standard DO Spaces URL Format

The preprocessing app should store URLs in this format:

```
https://{BUCKET}.{REGION}.digitaloceanspaces.com/{OBJECT_KEY}
```

### Examples

✅ **Correct Formats** (pipe will auto-detect and sign):

```
https://kb-images.nyc3.digitaloceanspaces.com/docs/chart-123.png
https://knowledge-base.sfo3.digitaloceanspaces.com/images/2024/diagram.jpg
https://my-bucket.ams3.digitaloceanspaces.com/uploads/screenshot.png
```

❌ **Incorrect Formats** (pipe will not process):

```
# Path-style URLs (not supported)
https://nyc3.digitaloceanspaces.com/kb-images/chart.png

# Missing region
https://kb-images.digitaloceanspaces.com/chart.png

# Non-DO Spaces domains
https://s3.amazonaws.com/bucket/file.png
```

### URL Structure Breakdown

```
https://kb-images.nyc3.digitaloceanspaces.com/docs/20240122/chart-sales.png
       └────┬────┘ └┬┘ └────────┬──────────┘ └──────────┬──────────────┘
         bucket   region      domain                object key
```

**Components**:
- **bucket**: Your Spaces bucket name
- **region**: DO region (nyc3, sfo3, ams3, sgp1, fra1, etc.)
- **domain**: Always `digitaloceanspaces.com`
- **object_key**: File path within bucket (can include subdirectories)

---

## Chunk Metadata Specification

### Image URL Storage in Chunks

Store the image URL in chunk metadata exactly as returned from DO Spaces:

```python
# Preprocessing app code example
chunk = {
    "content": "This chart shows sales data for Q4 2024...",
    "metadata": {
        "source": "sales-report-2024.pdf",
        "page": 5,
        "image_url": "https://kb-images.nyc3.digitaloceanspaces.com/docs/20240122/chart-sales.png",
        "image_description": "Bar chart showing Q4 2024 sales by region",
        "chunk_type": "image_description"
    }
}
```

### Metadata Field Naming

The pipe regex pattern looks for URLs in the response text. The agent should include the URL in its response when referencing images:

**Agent Response Format**:
```
Based on the sales data, Q4 showed strong growth.
You can see the breakdown here: https://kb-images.nyc3.digitaloceanspaces.com/docs/20240122/chart-sales.png
```

### Multiple Images per Chunk

If a chunk references multiple images:

```python
chunk = {
    "content": "The report contains both sales and revenue charts...",
    "metadata": {
        "source": "financial-report-2024.pdf",
        "page": 10,
        "images": [
            {
                "url": "https://kb-images.nyc3.digitaloceanspaces.com/docs/charts/sales.png",
                "description": "Sales chart",
                "position": "top"
            },
            {
                "url": "https://kb-images.nyc3.digitaloceanspaces.com/docs/charts/revenue.png",
                "description": "Revenue chart",
                "position": "bottom"
            }
        ]
    }
}
```

---

## Open WebUI Pipe Configuration

### Required Valve Settings

Once images are in private buckets, configure the Open WebUI pipe:

```python
# In Open WebUI Function Settings

# Enable presigned URL generation
ENABLE_PRESIGNED_URLS = True

# Digital Ocean Spaces credentials (read-only keys)
DO_SPACES_ACCESS_KEY = "DO00XXXXXXXXXXXXXXXXXXXX"
DO_SPACES_SECRET_KEY = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Region where bucket is located
DO_SPACES_REGION = "nyc3"

# URL expiration (in seconds)
PRESIGNED_URL_EXPIRATION = 3600  # 1 hour

# Optional: Enable debug logging
DEBUG_MODE = False
```

### Valve Descriptions

| Valve | Type | Default | Description |
|-------|------|---------|-------------|
| `ENABLE_PRESIGNED_URLS` | bool | False | Master switch for presigned URL generation |
| `DO_SPACES_ACCESS_KEY` | str | "" | Spaces access key (read-only recommended) |
| `DO_SPACES_SECRET_KEY` | str | "" | Spaces secret key |
| `DO_SPACES_REGION` | str | "nyc3" | Region where bucket is located |
| `PRESIGNED_URL_EXPIRATION` | int | 3600 | URL expiration in seconds (max: 604800 = 7 days) |

---

## Testing & Validation

### Test Checklist for Preprocessing App

#### 1. Upload Test Image

```python
# Test that image uploads to private bucket
import boto3

s3_client = boto3.client(
    's3',
    region_name='nyc3',
    endpoint_url='https://nyc3.digitaloceanspaces.com',
    aws_access_key_id='YOUR_UPLOAD_KEY',
    aws_secret_access_key='YOUR_UPLOAD_SECRET'
)

# Upload test image
s3_client.upload_file(
    'test-chart.png',
    'kb-images',
    'test/chart-001.png',
    ExtraArgs={'ACL': 'private'}  # IMPORTANT: private ACL
)

# Get URL (without presigning)
url = f"https://kb-images.nyc3.digitaloceanspaces.com/test/chart-001.png"
print(f"Stored URL: {url}")
```

#### 2. Verify Image is Private

```bash
# This should return 403 Forbidden
curl -I https://kb-images.nyc3.digitaloceanspaces.com/test/chart-001.png

# Expected response:
# HTTP/1.1 403 Forbidden
```

#### 3. Test Chunk Creation

```python
chunk = {
    "content": "Test chart shows data trends",
    "metadata": {
        "image_url": "https://kb-images.nyc3.digitaloceanspaces.com/test/chart-001.png",
        "image_description": "Test chart"
    }
}

# Index chunk in knowledge base
index_chunk(chunk)
```

#### 4. Test in Open WebUI

1. Enable presigned URL feature in pipe valves
2. Add read-only Spaces credentials
3. Query knowledge base: "Show me the test chart"
4. Verify agent response includes URL
5. Verify pipe automatically signs URL
6. Verify image displays in Open WebUI

### Expected Debug Output

With `DEBUG_MODE = True`:

```
[DEBUG] DO Spaces URL needs signing: https://kb-images.nyc3.digitaloceanspaces.com/test/chart-001.png...
[DEBUG] Attempting to sign URL: https://kb-images.nyc3.digitaloceanspaces.com/test/chart-001.png...
[DEBUG] S3 client initialized successfully (region: nyc3)
[DEBUG] Extracted bucket: kb-images, key: test/chart-001.png
[DEBUG] Generating presigned URL for: kb-images/test/chart-001.png
[DEBUG] Expiration: 3600 seconds
[DEBUG] Successfully generated presigned URL
[DEBUG] Using presigned URL
```

---

## Migration Guide

### Migrating from Public to Private Buckets

#### Step 1: Backup Existing Data

```bash
# Export all existing image URLs from knowledge base
# Keep list for verification after migration
```

#### Step 2: Create Private Bucket

```bash
# Create new private bucket in DO Spaces
# Do NOT make existing bucket private (breaks old URLs)
```

#### Step 3: Copy Images to Private Bucket

```python
# Copy images from public to private bucket
import boto3

source_bucket = "kb-images-public"
dest_bucket = "kb-images-private"

# Copy with private ACL
s3_client.copy_object(
    CopySource={'Bucket': source_bucket, 'Key': 'path/to/image.png'},
    Bucket=dest_bucket,
    Key='path/to/image.png',
    ACL='private'
)
```

#### Step 4: Update Chunk Metadata

```python
# Update URLs in existing chunks to point to private bucket
old_url = "https://kb-images-public.nyc3.digitaloceanspaces.com/chart.png"
new_url = "https://kb-images-private.nyc3.digitaloceanspaces.com/chart.png"

# Update in knowledge base
update_chunk_metadata(chunk_id, {"image_url": new_url})
```

#### Step 5: Configure Pipe

```python
# Enable presigned URLs in Open WebUI pipe
ENABLE_PRESIGNED_URLS = True
DO_SPACES_ACCESS_KEY = "read_only_key"
DO_SPACES_SECRET_KEY = "read_only_secret"
DO_SPACES_REGION = "nyc3"
```

#### Step 6: Test & Verify

```bash
# Test queries return images correctly
# Verify presigned URLs are generated
# Check images display in Open WebUI
```

#### Step 7: Clean Up

```bash
# Once verified, optionally delete old public bucket
# Or keep for rollback capability
```

---

## Troubleshooting

### Issue: Images Not Displaying

**Symptoms**: Agent returns URLs but images don't show in Open WebUI

**Diagnosis**:
1. Check pipe valves: `ENABLE_PRESIGNED_URLS = True`
2. Verify credentials are set: `DO_SPACES_ACCESS_KEY` and `DO_SPACES_SECRET_KEY`
3. Enable `DEBUG_MODE = True` and check logs

**Common Causes**:
- Feature not enabled (valve `ENABLE_PRESIGNED_URLS = False`)
- Missing or incorrect credentials
- Wrong region setting
- Bucket name mismatch

### Issue: 403 Forbidden Errors

**Symptoms**: Presigned URLs still return 403 Forbidden

**Diagnosis**:
1. Check access key has GET permissions on bucket
2. Verify region matches bucket location
3. Check bucket name in URL matches actual bucket

**Resolution**:
```python
# Verify credentials with boto3
import boto3

client = boto3.client(
    's3',
    region_name='nyc3',
    endpoint_url='https://nyc3.digitaloceanspaces.com',
    aws_access_key_id='YOUR_KEY',
    aws_secret_access_key='YOUR_SECRET'
)

# Test access
try:
    client.head_object(Bucket='kb-images', Key='test/chart.png')
    print("✓ Access works")
except Exception as e:
    print(f"✗ Access failed: {e}")
```

### Issue: URLs Expire Too Quickly

**Symptoms**: Images load initially but fail after some time

**Diagnosis**: Presigned URLs have expired

**Resolution**:
```python
# Increase expiration time in pipe valves
PRESIGNED_URL_EXPIRATION = 7200  # 2 hours instead of 1 hour

# Maximum allowed: 604800 seconds (7 days)
```

### Issue: Wrong Region in Generated URLs

**Symptoms**: Presigned URLs point to wrong region endpoint

**Diagnosis**: `DO_SPACES_REGION` valve doesn't match bucket location

**Resolution**:
```python
# Set correct region in pipe valves
DO_SPACES_REGION = "sfo3"  # Match your bucket's region
```

---

## Security Features

### Private URL Protection (v9.0.0)

**CRITICAL SECURITY FEATURE**: The pipe automatically removes private URLs from agent responses.

#### How It Works

When presigned URLs are generated:
1. Agent response includes private URL: `https://bucket.nyc3.digitaloceanspaces.com/chart.png`
2. Pipe generates signed URL: `https://...?X-Amz-Signature=...`
3. **Pipe removes original private URL from agent text**
4. Replaces with: `[image will be displayed below]`
5. Displays image using signed URL in markdown

#### What Users See

**Before (Insecure)**:
```
Agent: "See the chart: https://private-bucket.nyc3.digitaloceanspaces.com/secret/chart.png"

[Image displays below using presigned URL]
```
**Problem**: Private URL visible, could be copied/shared

**After v9.0.0 (Secure)**:
```
Agent: "See the chart: [image will be displayed below]"

[Image displays below using presigned URL]
```
**Secure**: Private URL never visible to user

#### Streaming Mode Security Limitation

⚠️ **IMPORTANT**: When using streaming mode (`ENABLE_STREAMING=True`):
- Agent response is streamed in real-time
- Private URLs are streamed BEFORE the pipe can remove them
- Users may see private URLs briefly in the UI

**Recommendation for Private Images**:
```python
# Open WebUI Pipe Configuration
ENABLE_STREAMING = False  # Disable for maximum security with private images
ENABLE_PRESIGNED_URLS = True
```

This ensures private URLs are removed before any content is shown to users.

## Security Best Practices

### 1. Use Read-Only Access Keys

Generate dedicated keys for Open WebUI with minimal permissions:

```
Permissions: READ only
Scope: Specific bucket(s) only
Not: Account-wide access
```

### 2. Limit URL Expiration

Use shortest practical expiration time:

```python
# Development/Testing
PRESIGNED_URL_EXPIRATION = 3600  # 1 hour

# Production
PRESIGNED_URL_EXPIRATION = 1800  # 30 minutes
```

### 3. Rotate Access Keys Regularly

```bash
# Generate new keys every 90 days
# Update pipe valves with new credentials
# Revoke old keys after verification
```

### 4. Monitor Access Logs

Enable DO Spaces access logging:

```python
# Track:
# - Presigned URL generation frequency
# - Failed access attempts
# - Unusual access patterns
```

### 5. Use HTTPS Only

```python
# Preprocessing app: Always use HTTPS URLs
url = f"https://{bucket}.{region}.digitaloceanspaces.com/{key}"

# NOT: http:// (insecure)
```

---

## Performance Considerations

### URL Signing Latency

- **Typical**: < 100ms per URL
- **Cached client**: < 50ms per subsequent URL
- **Network latency**: Depends on DO region proximity

### Optimization Tips

1. **Batch Processing**: Pipe signs URLs concurrently during response processing
2. **Client Caching**: S3 client initialized once and reused
3. **Region Selection**: Choose DO region closest to Open WebUI deployment

### Expected Performance

```
Scenario                     Time
────────────────────────     ─────
Single image                 < 100ms
5 images                     < 500ms
10 images (max default)      < 1000ms
```

---

## API Reference

### Preprocessing App Required Functions

#### Image Upload

```python
def upload_image_to_spaces(
    file_path: str,
    bucket: str,
    object_key: str,
    region: str = "nyc3"
) -> str:
    """
    Upload image to private DO Spaces bucket.

    Args:
        file_path: Local path to image file
        bucket: DO Spaces bucket name
        object_key: Destination path in bucket
        region: DO Spaces region

    Returns:
        Standard DO Spaces URL (NOT presigned)
    """
    # Implementation
    s3_client.upload_file(
        file_path,
        bucket,
        object_key,
        ExtraArgs={'ACL': 'private'}
    )

    return f"https://{bucket}.{region}.digitaloceanspaces.com/{object_key}"
```

#### Chunk Creation

```python
def create_chunk_with_image(
    content: str,
    image_url: str,
    image_description: str,
    metadata: dict
) -> dict:
    """
    Create chunk with image reference.

    Args:
        content: Text content of chunk
        image_url: Standard DO Spaces URL
        image_description: Description of image
        metadata: Additional metadata

    Returns:
        Chunk ready for indexing
    """
    return {
        "content": content,
        "metadata": {
            **metadata,
            "image_url": image_url,
            "image_description": image_description
        }
    }
```

---

## Examples

### Complete Workflow Example

```python
# 1. Extract image from PDF
image = extract_image_from_pdf("sales-report.pdf", page=5)

# 2. Upload to private DO Spaces bucket
image_url = upload_image_to_spaces(
    file_path="/tmp/chart-sales.png",
    bucket="kb-images",
    object_key="docs/2024/sales-q4-chart.png",
    region="nyc3"
)
# Returns: https://kb-images.nyc3.digitaloceanspaces.com/docs/2024/sales-q4-chart.png

# 3. Create chunk with image reference
chunk = {
    "content": "Q4 2024 sales reached $2.5M, up 15% from Q3. Regional breakdown shows strongest growth in APAC.",
    "metadata": {
        "source": "sales-report-2024.pdf",
        "page": 5,
        "image_url": image_url,
        "image_description": "Bar chart showing Q4 2024 sales by region",
        "document_type": "financial_report",
        "quarter": "Q4",
        "year": 2024
    }
}

# 4. Index chunk in knowledge base
index_chunk(chunk)

# 5. Agent retrieves chunk and includes URL in response
# Agent: "Q4 sales data shows strong growth. See the chart: https://kb-images.nyc3.digitaloceanspaces.com/docs/2024/sales-q4-chart.png"

# 6. Pipe automatically detects DO Spaces URL and generates presigned URL
# Pipe: Converts to "https://nyc3.digitaloceanspaces.com/kb-images/docs/2024/sales-q4-chart.png?X-Amz-Algorithm=..."

# 7. User sees image in Open WebUI
```

---

## Summary Checklist

### Preprocessing App Checklist

- [ ] Images uploaded to **private** DO Spaces buckets
- [ ] Image ACL set to `private`
- [ ] Standard DO Spaces URLs stored (not presigned)
- [ ] URL format: `https://{bucket}.{region}.digitaloceanspaces.com/{key}`
- [ ] Image URLs stored in chunk metadata
- [ ] Agent configured to include URLs in responses

### Open WebUI Pipe Checklist

- [ ] Pipe updated to v9.0.0 or later
- [ ] `ENABLE_PRESIGNED_URLS = True`
- [ ] Read-only access keys configured
- [ ] Correct region set in `DO_SPACES_REGION`
- [ ] Appropriate expiration time set
- [ ] Debug mode enabled for testing

### Testing Checklist

- [ ] Test image upload to private bucket
- [ ] Verify image is private (403 without signature)
- [ ] Test chunk creation with image URL
- [ ] Test agent query returns image URL
- [ ] Verify pipe generates presigned URL
- [ ] Verify image displays in Open WebUI
- [ ] Test URL expiration behavior
- [ ] Test multiple images per response

---

## Support & Resources

### Documentation Links

- [Digital Ocean Spaces Documentation](https://docs.digitalocean.com/products/spaces/)
- [AWS Signature Version 4](https://docs.aws.amazon.com/general/latest/gr/signature-version-4.html)
- [Boto3 Presigned URLs](https://boto3.amazonaws.com/v1/documentation/api/latest/guide/s3-presigned-urls.html)

### Contact

For issues with:
- **Preprocessing App**: [Your team/repository]
- **Open WebUI Pipe**: [Open WebUI Infrastructure repository]
- **Digital Ocean Spaces**: [DO Support](https://www.digitalocean.com/support/)

---

**Document End**
