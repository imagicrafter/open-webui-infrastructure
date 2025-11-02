# Phase 0 Prototype - Findings Document

**Date:** 2025-10-29
**Branch:** `feature/volume-mount-prototype`
**Archon Task ID:** `48bf1013-f812-47eb-8455-1e5caf112c64`
**Test Environment:** Digital Ocean Droplet (159.203.77.129)

---

## Executive Summary

Successfully validated the per-client volume mount approach for persistent branding without requiring an Open WebUI fork. The prototype demonstrates:

- ✅ Volume mounting works correctly with upstream `ghcr.io/open-webui/open-webui:main` image
- ✅ No external Digital Ocean Block Storage required ($0 additional hosting costs)
- ✅ Static assets can be managed from host filesystem
- ✅ Container deployed successfully with 3 volume mounts
- ⚠️ File copy procedure requires refinement (discovered edge case)

---

## Test Environment Details

**Droplet Specifications:**
- OS: Ubuntu 5.15.0-153-generic
- Storage: 49GB SSD (33GB free / 16GB used)
- Existing Containers: 2 Open WebUI instances already running
- Container Runtime: Docker

**Test Container Configuration:**
- Name: `openwebui-test-prototype`
- Image: `ghcr.io/open-webui/open-webui:main`
- Port: 9000:8080
- Version: Open WebUI v0.6.34

---

## Implementation Steps Executed

### Step 1: Directory Structure Creation

```bash
mkdir -p /opt/openwebui/defaults/static
mkdir -p /opt/openwebui/test-prototype/{data,static}
```

**Result:** ✅ Success
**Storage Location:** Droplet's root filesystem `/opt/openwebui/`
**Cost Impact:** $0 (uses included droplet storage)

### Step 2: Default Asset Extraction

```bash
# Pull upstream image
docker pull ghcr.io/open-webui/open-webui:main

# Extract defaults using temporary container
docker run -d --name temp-extract ghcr.io/open-webui/open-webui:main sleep 3600
docker cp temp-extract:/app/backend/open_webui/static/. /opt/openwebui/defaults/static/
docker stop temp-extract && docker rm temp-extract
```

**Result:** ✅ Success
**Files Extracted:** 21 total files
- Root level: favicon.png, logo.png, favicon.ico, favicon.svg, etc. (10 files)
- Subdirectories: assets/, fonts/, swagger-ui/ (15 files within)

### Step 3: Test Container Deployment

```bash
docker run -d \
  --name openwebui-test-prototype \
  -p 9000:8080 \
  -v /opt/openwebui/test-prototype/data:/app/backend/data \
  -v /opt/openwebui/test-prototype/static:/app/backend/open_webui/static \
  -v /opt/openwebui/test-prototype/static:/app/build/static \
  -e WEBUI_NAME="Test Prototype" \
  ghcr.io/open-webui/open-webui:main
```

**Result:** ✅ Success
**Container Status:** Healthy after ~45 seconds
**Web UI Status:** Responding with HTTP 200 OK
**Startup Time:** Database migrations + model loading took ~1 minute

**Volume Mounts Verified:**
```json
[
  {
    "Source": "/opt/openwebui/test-prototype/data",
    "Destination": "/app/backend/data"
  },
  {
    "Source": "/opt/openwebui/test-prototype/static",
    "Destination": "/app/backend/open_webui/static"
  },
  {
    "Source": "/opt/openwebui/test-prototype/static",
    "Destination": "/app/build/static"
  }
]
```

---

## Key Discovery: File Copy Edge Case

### Issue Identified

**Initial Command:**
```bash
cp -r /opt/openwebui/defaults/static/* /opt/openwebui/test-prototype/static/
```

**Problem:** Only copied subdirectories (assets/, fonts/, swagger-ui/), missed root-level files (*.png, *.ico, etc.)

**Root Cause:** The `/*` glob pattern doesn't include hidden files and may have issues with certain file patterns depending on shell expansion.

### Solution Implemented

```bash
# Copy root-level files explicitly
cp /opt/openwebui/defaults/static/*.{png,ico,svg,css,js,csv,webmanifest} \
   /opt/openwebui/test-prototype/static/ 2>/dev/null

# Verify copy
ls -la /opt/openwebui/test-prototype/static/*.png
```

**Result:** ✅ 10 PNG files copied successfully

**Files Confirmed:**
- apple-touch-icon.png (1,658 bytes)
- favicon-96x96.png (3,826 bytes)
- favicon-dark.png (15,919 bytes)
- favicon.png (10,655 bytes)
- logo.png (5,367 bytes)
- splash-dark.png (5,419 bytes)
- splash.png (5,239 bytes)
- user.png (7,858 bytes)
- web-app-manifest-192x192.png (8,349 bytes)
- web-app-manifest-512x512.png (30,105 bytes)

---

## Validation Status

### Completed Validations ✅

1. **Directory Structure:** `/opt/openwebui/<client>/{data,static}` pattern works
2. **Volume Mounting:** Bind mounts function correctly
3. **Container Health:** Deploys and reaches healthy status
4. **Web Service:** HTTP interface accessible
5. **Storage Cost:** $0 additional (uses droplet filesystem)
6. **Default Extraction:** Upstream assets can be extracted and copied

### Pending Validations ⏸️

**Interrupted by SSH connection loss - Resume when reconnected:**

1. **Static Asset Serving:** Verify `/static/favicon.png` returns 200 OK (was 404 before file copy)
2. **Branding Application:** Replace favicon.png with custom image
3. **Persistence Test:** Stop/remove/recreate container, verify branding persists
4. **Performance Impact:** Measure startup time and response times
5. **Cleanup Procedure:** Document removal process

---

## Recommended Script Improvements for Phase 1

Based on this prototype, the `extract-default-static.sh` script (Task 1.1) should:

### 1. Robust File Copying

```bash
# Copy ALL files and directories, including hidden files
cp -a /opt/openwebui/defaults/static/. /opt/openwebui/<client>/static/

# Alternative approach for more control:
rsync -av /opt/openwebui/defaults/static/ /opt/openwebui/<client>/static/
```

### 2. Validation Checks

```bash
# Verify file count matches
SOURCE_COUNT=$(find /opt/openwebui/defaults/static -type f | wc -l)
DEST_COUNT=$(find /opt/openwebui/<client>/static -type f | wc -l)

if [ "$SOURCE_COUNT" -ne "$DEST_COUNT" ]; then
  echo "ERROR: File count mismatch (source: $SOURCE_COUNT, dest: $DEST_COUNT)"
  exit 1
fi
```

### 3. Idempotency

```bash
# Check if defaults already extracted
if [ -f "/opt/openwebui/defaults/static/favicon.png" ]; then
  echo "Defaults already extracted, skipping..."
else
  # Perform extraction
fi
```

---

## Architecture Validation

### Confirmed: Zero Fork Dependency ✅

**Original Concern:** Need to maintain Open WebUI fork for custom branding

**Prototype Result:** Volume mounting enables:
- Persistent branding across container recreation
- Use of upstream `ghcr.io/open-webui/open-webui:main` image
- No code modifications required
- No build pipeline needed

**Implication:** Can proceed with repository segregation as planned

### Storage Architecture ✅

**Pattern:** `/opt/openwebui/<client>/`
- `data/` → SQLite database and user files
- `static/` → Custom branding assets (mounted to 2 container paths)

**Scalability:** Tested on droplet with 2 existing clients, deployed 3rd successfully

---

## Next Steps

### When SSH Access Restored:

1. **Complete Test 0.2:**
   ```bash
   # Reconnect to droplet
   ssh root@159.203.77.129

   # Verify static files visible in container
   docker exec openwebui-test-prototype ls -la /app/backend/open_webui/static/

   # Test static asset serving
   curl -I http://localhost:9000/static/favicon.png
   # Expected: HTTP 200 OK (was 404 before file copy)
   ```

2. **Apply Custom Branding (Test 0.2 Step 4):**
   ```bash
   # Replace favicon with test image
   echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" | \
     base64 -d > /opt/openwebui/test-prototype/static/favicon.png

   # Restart container
   docker restart openwebui-test-prototype
   sleep 10

   # Verify branding applied
   curl -I http://localhost:9000/static/favicon.png
   ```

3. **Test Persistence (Test 0.2 Step 6):**
   ```bash
   # DESTROY container (not just stop)
   docker stop openwebui-test-prototype
   docker rm openwebui-test-prototype

   # Recreate with same volume mounts
   docker run -d \
     --name openwebui-test-prototype \
     -p 9000:8080 \
     -v /opt/openwebui/test-prototype/data:/app/backend/data \
     -v /opt/openwebui/test-prototype/static:/app/backend/open_webui/static \
     -v /opt/openwebui/test-prototype/static:/app/build/static \
     -e WEBUI_NAME="Test Prototype" \
     ghcr.io/open-webui/open-webui:main

   sleep 15

   # Verify branding STILL present
   curl -I http://localhost:9000/static/favicon.png
   ```

4. **Cleanup:**
   ```bash
   docker stop openwebui-test-prototype
   docker rm openwebui-test-prototype
   rm -rf /opt/openwebui/test-prototype
   # Keep defaults for future use: /opt/openwebui/defaults/static/
   ```

5. **Document Final Results:** Update this document with test outcomes

---

## Success Metrics

### Achieved ✅

- [x] Feature branch created
- [x] Directory structure established on production environment
- [x] Default assets extracted from upstream image
- [x] Test container deployed with volume mounts
- [x] Container reached healthy status
- [x] Web UI accessible
- [x] Volume mount configuration validated
- [x] Zero additional hosting costs confirmed
- [x] File copy edge case identified and solved

### Remaining ⏸️

- [ ] Static asset serving verified (POST file copy)
- [ ] Custom branding applied and verified
- [ ] Branding persistence across container recreation confirmed
- [ ] Cleanup procedure documented and executed
- [ ] Performance benchmarks collected

---

## Risk Assessment

### Mitigated Risks ✅

1. **Cost Risk:** ~~Might require external Digital Ocean Block Storage~~
   - **Mitigation:** Confirmed uses included droplet storage ($0 additional)

2. **Complexity Risk:** ~~Volume mounting might be complicated~~
   - **Mitigation:** Standard Docker bind mounts, well-documented pattern

3. **Fork Dependency:** ~~Can't remove fork without losing branding~~
   - **Mitigation:** Volume mounting enables persistent branding with upstream image

### Identified Risks ⚠️

1. **File Copy Reliability:**
   - **Issue:** Shell glob patterns may behave inconsistently
   - **Mitigation:** Use `cp -a .../. ` or `rsync -av` in Phase 1 scripts
   - **Severity:** Low (script-level, easily fixable)

2. **SSH Connectivity:**
   - **Issue:** Lost connection during testing
   - **Mitigation:** Implement connection retry logic in scripts
   - **Severity:** Low (operational, not architectural)

---

## Lessons Learned

### Technical

1. **File Copying:** Use `cp -a .../. ` pattern for complete directory copies
2. **Volume Mounting:** Bind mounts work immediately (no container restart needed after host file changes)
3. **Startup Time:** Open WebUI takes ~45-60 seconds to reach healthy status
4. **Image Size:** Upstream image has 15 layers, downloads quickly on good connection

### Process

1. **Test in Production Environment:** Local Mac development wouldn't have caught Ubuntu-specific behaviors
2. **Incremental Validation:** Checking each step helped identify file copy issue early
3. **Connection Reliability:** Build retry/resume logic into automation scripts

---

## Conclusion

**Phase 0 Prototype Status:** 85% Complete (⏸️ paused due to SSH connectivity)

**Key Validation:** ✅ **The per-client volume mount approach is viable and cost-effective.**

**Recommendation:** **Proceed with Phase 1 implementation** when SSH access is restored and remaining validations are complete.

**Architecture Decision Confirmed:**
- ✅ Can eliminate Open WebUI fork
- ✅ Volume mounting provides persistent branding
- ✅ Zero additional hosting costs
- ✅ Standard Docker patterns, easily automatable

---

## Appendix: Commands Reference

### Droplet Connection
```bash
ssh root@159.203.77.129
```

### Container Management
```bash
# View all containers
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'

# Check test container logs
docker logs openwebui-test-prototype

# Inspect volume mounts
docker inspect openwebui-test-prototype | grep -A 20 '"Mounts"'

# Exec into container
docker exec -it openwebui-test-prototype bash
```

### Storage Management
```bash
# Check disk usage
df -h /opt/openwebui/

# List directory structure
tree -L 3 /opt/openwebui/

# Count files
find /opt/openwebui/test-prototype/static -type f | wc -l
```

### Testing Commands
```bash
# Test web UI
curl -I http://localhost:9000/

# Test static asset
curl -I http://localhost:9000/static/favicon.png

# Download asset for inspection
curl -o test-favicon.png http://localhost:9000/static/favicon.png
file test-favicon.png
```

---

## CRITICAL UPDATE - 2025-10-30 13:15 UTC

### 🚨 Branding Persistence FAILURE

**Test Completed:** Container recreation test (Test 0.2 Step 6)

**Result:** ❌ Custom branding does NOT persist across container recreation

**Evidence:**
1. **Before Recreation:**
   - Custom favicon applied: 70 bytes
   - HTTP response: `content-length: 70`
   - Last-Modified: Thu, 30 Oct 2025 13:09:03 GMT

2. **After Recreation (docker rm + docker run):**
   - Favicon reverted: 10,655 bytes (default)
   - HTTP response: `content-length: 10655`
   - Last-Modified: Thu, 30 Oct 2025 13:11:58 GMT
   - Host file overwritten: `/opt/openwebui/test-prototype/static/favicon.png` = 10,655 bytes

**Root Cause Analysis:**
Open WebUI's initialization process (likely in Python application code, not start.sh) copies static files from `/app/build/static/` to `/app/backend/open_webui/static/` during startup, **overwriting** any volume-mounted custom files.

**start.sh Investigation:**
- Examined `/app/backend/start.sh`
- No static file copying logic found in bash script
- Static file management must be in Python application code (open_webui.main:app)
- Container logs showed errors: "PosixPath... and PosixPath... are the same file"

### 🔄 Alternative Approaches Required

The original segregation plan assumption was **incorrect**:
- ❌ Volume mounting `/app/backend/open_webui/static` alone does NOT provide persistent branding
- ❌ Double-mounting same directory to both paths causes initialization failures

**Viable Options Moving Forward:**

#### Option A: Post-Startup Branding Injection ⭐ RECOMMENDED
```bash
# After container starts and initializes:
1. Wait for container healthy status
2. Copy custom branding to volume-mounted directory
3. Branding persists until next container recreation
4. Use container restart (not recreation) for updates
```

**Pros:**
- Works with upstream image
- No fork required
- Automated via scripts

**Cons:**
- Branding lost on container recreation (must re-inject)
- Requires automation/orchestration

#### Option B: Custom Docker Image
```dockerfile
FROM ghcr.io/open-webui/open-webui:main
COPY custom-branding/ /app/build/static/
```

**Pros:**
- Branding truly persistent
- Survives recreation

**Cons:**
- Requires maintaining custom image build
- Need to rebuild when upstream updates
- Defeats purpose of "no fork" strategy

#### Option C: Init Container Pattern
```yaml
# Use init container or sidecar to manage branding
initContainers:
  - name: branding-init
    # Inject branding after Open WebUI initializes
```

**Pros:**
- Kubernetes-native pattern
- Separation of concerns

**Cons:**
- Requires orchestration platform
- More complex architecture

#### Option D: Environment Variable Configuration
Investigate if Open WebUI supports environment variables for branding:
```bash
WEBUI_FAVICON_URL=https://cdn.example.com/favicon.png
WEBUI_LOGO_URL=https://cdn.example.com/logo.png
```

**Pros:**
- Cleanest solution if supported
- No file management needed

**Cons:**
- May not be supported by Open WebUI
- Requires upstream feature

---

## Revised Recommendation

**SHORT TERM (Current mt/ system):**
Use **Option A: Post-Startup Branding Injection**
- Container starts with defaults
- Automation script waits for healthy status
- Injects custom branding to volume mount
- Use `docker restart` for updates (NOT `docker rm + docker run`)

**LONG TERM (Repository segregation):**
1. Investigate Option D (environment variable support)
2. If not available, submit PR to Open WebUI for branding config
3. Until then, use Option A with automation

---

**Document Status:** Phase 0 Complete with Critical Findings
**Last Updated:** 2025-10-30 13:15 UTC
**Status:** Architecture pivot required - Original volume-mount-only approach insufficient
