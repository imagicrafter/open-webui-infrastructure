# Open WebUI Infrastructure Segregation - Testing Documentation

**Project:** Open WebUI Infrastructure Segregation
**Archon Project ID:** `70237b92-0cb4-4466-ab9a-5bb2c4d90d4f`
**Document Version:** 1.0
**Date:** 2025-10-29

---

## Overview

This document provides comprehensive testing procedures for validating each task in the infrastructure segregation project. Tests ensure that volume-mounted static assets work correctly, branding persists across container recreation, and the transition from fork to standalone repository is seamless.

---

## Table of Contents

1. [Phase 0: Prototype Testing](#phase-0-prototype-testing)
2. [Phase 1: Volume Mounting Tests](#phase-1-volume-mounting-tests)
3. [Phase 2: Repository Extraction Tests](#phase-2-repository-extraction-tests)
4. [Phase 3: Migration Path Tests](#phase-3-migration-path-tests)
5. [Phase 4: Documentation & Distribution Tests](#phase-4-documentation--distribution-tests)

---

## Phase 0: Prototype Testing

**Archon Task ID:** `48bf1013-f812-47eb-8455-1e5caf112c64`
**Task:** Phase 0: Prototype per-client volume mounts in separate branch

### Test 0.1: Create Prototype Branch

**Objective:** Create isolated branch for testing volume mount approach

**Prerequisites:**
- Clean working directory in open-webui fork
- No uncommitted changes

**Test Steps:**
```bash
# 1. Ensure on main branch
git checkout main
git pull origin main

# 2. Create feature branch
git checkout -b feature/volume-mount-prototype

# 3. Verify branch created
git branch --list | grep volume-mount-prototype

# 4. Push branch to remote
git push -u origin feature/volume-mount-prototype
```

**Expected Results:**
- ✅ Branch `feature/volume-mount-prototype` created
- ✅ Branch pushed to remote
- ✅ Git status shows clean working tree

**Validation:**
```bash
git status
# Output should show: On branch feature/volume-mount-prototype
```

---

### Test 0.2: Manual Volume Mount Prototype

**Objective:** Manually test volume mounting with a single test client before scripting

**Prerequisites:**
- Docker installed and running
- Access to upstream Open WebUI image

**Test Steps:**

**Step 1: Extract default static assets**
```bash
# Create directory structure
mkdir -p /opt/openwebui/defaults/static
mkdir -p /opt/openwebui/test-prototype/{data,static}

# Pull upstream image
docker pull ghcr.io/open-webui/open-webui:main

# Extract defaults (temporary container)
docker run -d --name temp-extract ghcr.io/open-webui/open-webui:main sleep 3600
docker cp temp-extract:/app/backend/open_webui/static/. /opt/openwebui/defaults/static/
docker stop temp-extract && docker rm temp-extract

# Copy defaults to test client
cp -r /opt/openwebui/defaults/static/* /opt/openwebui/test-prototype/static/
```

**Step 2: Deploy test container with volume mounts**
```bash
docker run -d \
  --name openwebui-test-prototype \
  -p 9000:8080 \
  -v /opt/openwebui/test-prototype/data:/app/backend/data \
  -v /opt/openwebui/test-prototype/static:/app/backend/open_webui/static \
  -v /opt/openwebui/test-prototype/static:/app/build/static \
  -e WEBUI_NAME="Test Prototype" \
  ghcr.io/open-webui/open-webui:main

# Wait for startup
sleep 15
```

**Step 3: Verify container is running**
```bash
docker ps | grep openwebui-test-prototype
curl -I http://localhost:9000/
```

**Step 4: Apply custom branding (manual)**
```bash
# Create simple test logo (1x1 pixel PNG for testing)
echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" | base64 -d > /opt/openwebui/test-prototype/static/favicon.png

# Restart container to reload assets
docker restart openwebui-test-prototype
sleep 10
```

**Step 5: Verify branding applied**
```bash
curl -I http://localhost:9000/static/favicon.png
# Should return 200 OK
```

**Step 6: Test persistence across container RECREATION**
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
# Should return 200 OK with custom favicon
```

**Expected Results:**
- ✅ Container deploys successfully with volume mounts
- ✅ Default static assets accessible at startup
- ✅ Custom branding can be applied by modifying host directory
- ✅ Branding persists after container recreation (docker rm + docker run)
- ✅ No hosting costs increased (uses existing droplet storage)

**Validation:**
```bash
# Check volume mounts
docker inspect openwebui-test-prototype | grep -A 10 Mounts

# Should show 3 mounts:
# - /opt/openwebui/test-prototype/data -> /app/backend/data
# - /opt/openwebui/test-prototype/static -> /app/backend/open_webui/static
# - /opt/openwebui/test-prototype/static -> /app/build/static

# Check disk usage (no external volumes used)
df -h /opt/openwebui/
# Should show usage on droplet's root filesystem

# Check branding file exists on host
ls -lh /opt/openwebui/test-prototype/static/favicon.png
```

**Cleanup:**
```bash
docker stop openwebui-test-prototype
docker rm openwebui-test-prototype
rm -rf /opt/openwebui/test-prototype
```

**Success Criteria:**
- ✅ All test steps pass without errors
- ✅ Branding persists across container recreation
- ✅ No Digital Ocean Block Storage required
- ✅ Approach validated for scripting in Phase 1

---

## Phase 1: Volume Mounting Tests

### Test 1.1: Default Asset Extraction Script

**Archon Task ID:** `1b8bcb18-a651-44e0-8377-f853e1a0c702`
**Task:** Task 1.1: Create default asset extraction script

**Test File:** `mt/setup/lib/extract-default-static.sh`

**Test Steps:**

**Test 1.1.1: Script Syntax Validation**
```bash
bash -n mt/setup/lib/extract-default-static.sh
# Should return no errors
```

**Test 1.1.2: Basic Extraction (Default Parameters)**
```bash
# Clean test environment
rm -rf /opt/openwebui/defaults

# Run script with defaults
bash mt/setup/lib/extract-default-static.sh

# Verify extraction
ls -la /opt/openwebui/defaults/static/
```

**Expected Results:**
- ✅ Script executes without errors
- ✅ Directory `/opt/openwebui/defaults/static/` created
- ✅ Files extracted: favicon.png, logo.png, etc.
- ✅ At least 5+ static asset files present

**Test 1.1.3: Extraction with Custom Parameters**
```bash
# Test with custom image and directory
bash mt/setup/lib/extract-default-static.sh \
  ghcr.io/open-webui/open-webui:latest \
  /tmp/test-static

# Verify extraction
ls -la /tmp/test-static/static/

# Cleanup
rm -rf /tmp/test-static
```

**Expected Results:**
- ✅ Script accepts custom parameters
- ✅ Extracts to specified directory
- ✅ Works with different image tags

**Test 1.1.4: Idempotency Test**
```bash
# Run script twice
bash mt/setup/lib/extract-default-static.sh
bash mt/setup/lib/extract-default-static.sh

# Should not fail on second run
echo $?
# Should return 0
```

**Expected Results:**
- ✅ Script can run multiple times safely
- ✅ No errors on subsequent runs
- ✅ Files not corrupted

**Test 1.1.5: Error Handling**
```bash
# Test with invalid image
bash mt/setup/lib/extract-default-static.sh ghcr.io/nonexistent/image:latest 2>&1

# Should show error message
```

**Expected Results:**
- ✅ Graceful error handling
- ✅ Clear error messages
- ✅ Non-zero exit code on failure

**Validation Commands:**
```bash
# Verify file count
file_count=$(ls /opt/openwebui/defaults/static/ | wc -l)
[ "$file_count" -gt 5 ] && echo "✅ PASS" || echo "❌ FAIL"

# Verify favicon exists
[ -f /opt/openwebui/defaults/static/favicon.png ] && echo "✅ PASS" || echo "❌ FAIL"

# Verify logo exists
[ -f /opt/openwebui/defaults/static/logo.png ] && echo "✅ PASS" || echo "❌ FAIL"
```

---

### Test 1.2: start-template.sh Volume Mount Updates

**Archon Task ID:** `1f78c9ff-f144-49e9-bb77-ca64112f69ea`
**Task:** Task 1.2: Update start-template.sh for volume mounts

**Test File:** `mt/start-template.sh`

**Test Steps:**

**Test 1.2.1: Directory Structure Creation**
```bash
# Clean test environment
rm -rf /opt/openwebui/test-client-a

# Run start-template.sh
./mt/start-template.sh test-client-a 9001 test-a.local openwebui-test-a test-a.local

# Verify directories created
ls -la /opt/openwebui/test-client-a/
```

**Expected Results:**
- ✅ `/opt/openwebui/test-client-a/data/` created
- ✅ `/opt/openwebui/test-client-a/static/` created
- ✅ Static directory populated with defaults
- ✅ Container started successfully

**Test 1.2.2: Volume Mount Verification**
```bash
# Check container mounts
docker inspect openwebui-test-a | jq '.[0].Mounts'
```

**Expected Results:**
- ✅ 3 volume mounts present:
  - `/opt/openwebui/test-client-a/data` → `/app/backend/data`
  - `/opt/openwebui/test-client-a/static` → `/app/backend/open_webui/static`
  - `/opt/openwebui/test-client-a/static` → `/app/build/static`

**Test 1.2.3: Application Functionality**
```bash
# Wait for startup
sleep 15

# Test application responds
curl -f http://localhost:9001/
echo $?  # Should return 0

# Test static assets accessible
curl -f http://localhost:9001/static/favicon.png
echo $?  # Should return 0
```

**Expected Results:**
- ✅ Application accessible on specified port
- ✅ Static assets served correctly
- ✅ No errors in container logs

**Test 1.2.4: Static Directory Initialization**
```bash
# Remove static directory
rm -rf /opt/openwebui/test-client-a/static

# Restart container
docker restart openwebui-test-a
sleep 10

# Verify static directory re-initialized
ls -la /opt/openwebui/test-client-a/static/
```

**Expected Results:**
- ✅ Static directory auto-recreated
- ✅ Default assets restored
- ✅ Application continues to function

**Cleanup:**
```bash
docker stop openwebui-test-a && docker rm openwebui-test-a
rm -rf /opt/openwebui/test-client-a
```

---

### Test 1.3: apply-branding.sh Host Mode

**Archon Task ID:** `f7be6963-42c7-41ff-a1e6-0ad05da0e1cc`
**Task:** Task 1.3: Update apply-branding.sh for host directory mode

**Test File:** `mt/setup/scripts/asset_management/apply-branding.sh`

**Test Steps:**

**Test 1.3.1: Host Mode - Apply Branding**
```bash
# Deploy test client
./mt/start-template.sh test-client-b 9002 test-b.local openwebui-test-b test-b.local
sleep 15

# Apply branding in host mode
MODE=host CLIENT_NAME=test-client-b \
  bash mt/setup/scripts/asset_management/apply-branding.sh \
  openwebui-test-b \
  https://upload.wikimedia.org/wikipedia/commons/thumb/2/2f/Google_2015_logo.svg/272px-Google_2015_logo.svg.png

# Verify branding applied to host directory
ls -lh /opt/openwebui/test-client-b/static/favicon.png
ls -lh /opt/openwebui/test-client-b/static/logo.png
```

**Expected Results:**
- ✅ Branding files written to host directory
- ✅ Container restarted automatically
- ✅ Branding visible in browser

**Test 1.3.2: Container Mode - Backward Compatibility**
```bash
# Deploy another test client
./mt/start-template.sh test-client-c 9003 test-c.local openwebui-test-c test-c.local
sleep 15

# Apply branding in container mode (old method)
MODE=container \
  bash mt/setup/scripts/asset_management/apply-branding.sh \
  openwebui-test-c \
  https://upload.wikimedia.org/wikipedia/commons/thumb/2/2f/Google_2015_logo.svg/272px-Google_2015_logo.svg.png

# Verify branding applied
curl -I http://localhost:9003/static/favicon.png
```

**Expected Results:**
- ✅ Container mode still works
- ✅ Branding applied via docker cp
- ✅ Backward compatibility maintained

**Test 1.3.3: Mode Parameter Validation**
```bash
# Test invalid mode
MODE=invalid bash mt/setup/scripts/asset_management/apply-branding.sh openwebui-test-b https://example.com/logo.png 2>&1

# Should show error or default to container mode
```

**Expected Results:**
- ✅ Invalid modes handled gracefully
- ✅ Clear error messages or fallback to default

**Cleanup:**
```bash
docker stop openwebui-test-b openwebui-test-c
docker rm openwebui-test-b openwebui-test-c
rm -rf /opt/openwebui/test-client-b /opt/openwebui/test-client-c
```

---

### Test 1.4: Branding Persistence Comprehensive Test

**Archon Task ID:** `8fa6af3c-9a73-41cc-aa4c-8a144b7a3d07`
**Task:** Task 1.4: Test branding persistence across container recreation

**Test File:** Automated test script to be created

**Test Steps:**

**Test 1.4.1: Full Lifecycle Test**
```bash
#!/bin/bash
# test-branding-persistence.sh

set -e

echo "=== Branding Persistence Test ==="

# 1. Deploy test container
echo "[1/6] Deploying test container..."
./mt/start-template.sh test-persist 9999 test.local openwebui-test-persist test.local
sleep 15

# 2. Verify default branding
echo "[2/6] Verifying default branding..."
curl -f http://localhost:9999/static/favicon.png || { echo "FAIL: Default branding not accessible"; exit 1; }
echo "✅ Default branding accessible"

# 3. Apply custom branding (host mode)
echo "[3/6] Applying custom branding..."
MODE=host CLIENT_NAME=test-persist \
  bash mt/setup/scripts/asset_management/generate-text-logo.sh \
  openwebui-test-persist "TP" "white" "blue"
sleep 5

# 4. Verify custom branding
echo "[4/6] Verifying custom branding..."
curl -f http://localhost:9999/static/favicon.png || { echo "FAIL: Custom branding not accessible"; exit 1; }
echo "✅ Custom branding applied"

# 5. Recreate container (DESTROY and rebuild)
echo "[5/6] Recreating container..."
docker stop openwebui-test-persist
docker rm openwebui-test-persist
./mt/start-template.sh test-persist 9999 test.local openwebui-test-persist test.local
sleep 15

# 6. Verify branding PERSISTS
echo "[6/6] Verifying branding persistence..."
curl -f http://localhost:9999/static/favicon.png || { echo "FAIL: Branding lost after recreation"; exit 1; }

# Check if it's the custom branding (size should be different from default)
CUSTOM_SIZE=$(stat -f%z /opt/openwebui/test-persist/static/favicon.png)
[ "$CUSTOM_SIZE" -gt 0 ] || { echo "FAIL: Branding file empty"; exit 1; }

echo "✅ Branding persisted after container recreation!"

# Cleanup
docker stop openwebui-test-persist && docker rm openwebui-test-persist
rm -rf /opt/openwebui/test-persist

echo ""
echo "=== All Tests Passed ==="
```

**Expected Results:**
- ✅ All 6 test steps pass
- ✅ Branding survives container recreation
- ✅ No manual re-application needed
- ✅ Works with upstream Open WebUI image

**Validation:**
```bash
# Run automated test
bash test-branding-persistence.sh
# Should output: === All Tests Passed ===
```

---

## Phase 2: Repository Extraction Tests

### Test 2.1: Standalone Repository Structure

**Archon Task ID:** `3c52aa90-1a4c-4406-ac5b-a006910186c1`
**Task:** Task 2.1: Create standalone repository structure

**Test Steps:**

**Test 2.1.1: Repository Creation Validation**
```bash
# Clone new repository
git clone https://github.com/yourorg/open-webui-infrastructure.git
cd open-webui-infrastructure

# Verify structure
ls -la
```

**Expected Results:**
- ✅ Repository accessible
- ✅ All mt/ contents present
- ✅ LICENSE file exists (MIT)
- ✅ README.md exists
- ✅ .gitignore configured

**Test 2.1.2: File Integrity Check**
```bash
# Count files (should match original mt/ directory)
find . -type f | wc -l

# Check for critical files
[ -f "client-manager.sh" ] && echo "✅ client-manager.sh present"
[ -f "start-template.sh" ] && echo "✅ start-template.sh present"
[ -d "setup/" ] && echo "✅ setup/ directory present"
[ -d "SYNC/" ] && echo "✅ SYNC/ directory present"
```

**Expected Results:**
- ✅ All critical files present
- ✅ No missing directories
- ✅ Documentation files included

---

### Test 2.2: Central Configuration

**Archon Task ID:** `eb1c00d9-36c5-469f-b914-bf80f106cfd2`
**Task:** Task 2.2: Implement central configuration (config/global.conf)

**Test File:** `config/global.conf`

**Test Steps:**

**Test 2.2.1: Configuration File Syntax**
```bash
# Source configuration
source config/global.conf

# Verify variables set
echo "Image: $OPENWEBUI_FULL_IMAGE"
echo "Base Dir: $BASE_DIR"
echo "Container Prefix: $CONTAINER_PREFIX"
```

**Expected Results:**
- ✅ Configuration sources without errors
- ✅ All required variables defined
- ✅ Sensible default values

**Test 2.2.2: Image Configuration**
```bash
# Test default (upstream)
source config/global.conf
[ "$OPENWEBUI_IMAGE" = "ghcr.io/open-webui/open-webui" ] && echo "✅ Default to upstream"

# Test custom override
export OPENWEBUI_IMAGE="ghcr.io/custom/open-webui"
source config/global.conf
[ "$OPENWEBUI_IMAGE" = "ghcr.io/custom/open-webui" ] && echo "✅ Override works"
```

**Expected Results:**
- ✅ Defaults to upstream image
- ✅ Environment variables can override
- ✅ Easy to switch images

**Test 2.2.3: Script Integration**
```bash
# Verify scripts source configuration
grep -r "source.*config/global.conf" setup/ client-manager.sh start-template.sh

# Should show multiple references
```

**Expected Results:**
- ✅ Scripts reference global configuration
- ✅ Consistent configuration usage
- ✅ No hard-coded values remaining

---

### Test 2.3: Shared Library System

**Archon Task ID:** `5de25402-39fb-4f2f-a260-4e9eb23dff80`
**Task:** Task 2.3: Implement shared library system (Phase 1 refactoring)

**Test Files:** `setup/lib/*.sh`

**Test Steps:**

**Test 2.3.1: Library Files Exist**
```bash
# Check for all library files
[ -f "setup/lib/config.sh" ] && echo "✅ config.sh"
[ -f "setup/lib/colors.sh" ] && echo "✅ colors.sh"
[ -f "setup/lib/docker-helpers.sh" ] && echo "✅ docker-helpers.sh"
[ -f "setup/lib/db-helpers.sh" ] && echo "✅ db-helpers.sh"
[ -f "setup/lib/validation.sh" ] && echo "✅ validation.sh"
[ -f "setup/lib/asset-helpers.sh" ] && echo "✅ asset-helpers.sh"
```

**Expected Results:**
- ✅ All 6 library files present
- ✅ Executable permissions set
- ✅ Proper shebang lines

**Test 2.3.2: Library Function Tests**
```bash
# Test colors library
source setup/lib/colors.sh
print_success "Test message"
print_error "Error message"
print_info "Info message"

# Should output colored text
```

**Expected Results:**
- ✅ Libraries source successfully
- ✅ Functions work as expected
- ✅ No errors when sourced

**Test 2.3.3: Code Duplication Check**
```bash
# Count duplicate code blocks (should be significantly reduced)
# Check for duplicate color definitions
grep -r "RED=.*033" setup/ | wc -l
# Should be 1 (only in colors.sh)

# Check for duplicate docker exec patterns
grep -r "docker exec.*python3 -c" setup/ | wc -l
# Should be minimal (mostly in db-helpers.sh)
```

**Expected Results:**
- ✅ 400+ lines of duplication eliminated
- ✅ Single source of truth for common functions
- ✅ Improved maintainability

---

### Test 2.4: Documentation Updates

**Archon Task ID:** `2e56f14d-3978-4700-8892-ea92a5f56add`
**Task:** Task 2.4: Update documentation for standalone repository

**Test Steps:**

**Test 2.4.1: README Validation**
```bash
# Check README structure
grep -q "Quick Start" README.md && echo "✅ Quick Start section"
grep -q "Requirements" README.md && echo "✅ Requirements section"
grep -q "Features" README.md && echo "✅ Features section"
```

**Expected Results:**
- ✅ README complete and well-structured
- ✅ Installation instructions clear
- ✅ Links to additional documentation

**Test 2.4.2: Architecture Documentation**
```bash
# Verify ARCHITECTURE.md exists and has content
[ -f "ARCHITECTURE.md" ] && echo "✅ ARCHITECTURE.md exists"
wc -l ARCHITECTURE.md
# Should have 100+ lines
```

**Expected Results:**
- ✅ Architecture documented
- ✅ Design decisions explained
- ✅ Integration points described

**Test 2.4.3: Compatibility Matrix**
```bash
# Check COMPATIBILITY.md
[ -f "COMPATIBILITY.md" ] && echo "✅ COMPATIBILITY.md exists"
grep -q "Open WebUI" COMPATIBILITY.md && echo "✅ Version compatibility documented"
```

**Expected Results:**
- ✅ Compatibility matrix present
- ✅ Tested versions documented
- ✅ Known issues listed

---

## Phase 3: Migration Path Tests

### Test 3.1: Migration Script

**Archon Task ID:** `e938b6fd-66e0-4911-8280-c4430f726407`
**Task:** Task 3.1: Create migration script for existing deployments

**Test File:** `migration/migrate-to-standalone.sh`

**Test Steps:**

**Test 3.1.1: Pre-Migration Environment Setup**
```bash
# Create mock old-style deployment
docker run -d --name openwebui-legacy-client \
  -p 8091:8080 \
  -v openwebui-legacy-client-data:/app/backend/data \
  -e WEBUI_NAME="Legacy Client" \
  ghcr.io/imagicrafter/open-webui:main

sleep 15

# Add some test data
docker exec openwebui-legacy-client touch /app/backend/data/test-file.txt

# Apply branding (old method - will be lost on recreation)
docker cp /tmp/test-logo.png openwebui-legacy-client:/app/backend/open_webui/static/favicon.png
```

**Test 3.1.2: Run Migration**
```bash
# Execute migration script
bash migration/migrate-to-standalone.sh

# Should prompt for confirmation - answer 'y'
```

**Expected Results:**
- ✅ Discovers existing container
- ✅ Creates backup automatically
- ✅ Extracts branding from container
- ✅ Exports data to host directory
- ✅ Recreates container with volume mounts

**Test 3.1.3: Post-Migration Validation**
```bash
# Check directory structure created
ls -la /opt/openwebui/legacy-client/
ls -la /opt/openwebui/legacy-client/data/
ls -la /opt/openwebui/legacy-client/static/

# Verify test data preserved
docker exec openwebui-legacy-client ls /app/backend/data/test-file.txt

# Verify branding preserved
curl -I http://localhost:8091/static/favicon.png

# Check volume mounts
docker inspect openwebui-legacy-client | jq '.[0].Mounts'
```

**Expected Results:**
- ✅ Data preserved (test-file.txt exists)
- ✅ Branding preserved
- ✅ Volume mounts configured correctly
- ✅ Container functional

**Test 3.1.4: Backup Verification**
```bash
# Check backup created
ls -lh /opt/openwebui/backups/
# Should show backup file with timestamp

# Verify backup contains data
mkdir /tmp/backup-check
tar -xzf /opt/openwebui/backups/legacy-client-migration-*.tar.gz -C /tmp/backup-check/
ls -la /tmp/backup-check/app/backend/data/
```

**Expected Results:**
- ✅ Backup file created with timestamp
- ✅ Backup contains all data
- ✅ Backup can be extracted successfully

---

### Test 3.2: Rollback Procedure

**Archon Task ID:** `976bd4e0-63bf-4c6d-874b-de86a57fafb6`
**Task:** Task 3.2: Create rollback procedure script

**Test File:** `migration/rollback-migration.sh`

**Test Steps:**

**Test 3.2.1: Execute Rollback**
```bash
# Find backup file
BACKUP_FILE=$(ls -t /opt/openwebui/backups/legacy-client-migration-*.tar.gz | head -1)

# Run rollback
bash migration/rollback-migration.sh legacy-client "$BACKUP_FILE"
```

**Expected Results:**
- ✅ New container stopped and removed
- ✅ Data restored from backup
- ✅ Container recreated with old method
- ✅ Application functional

**Test 3.2.2: Rollback Validation**
```bash
# Check container reverted to Docker volume
docker inspect openwebui-legacy-client | jq '.[0].Mounts'
# Should show Docker volume mount, not host directory

# Verify data integrity
docker exec openwebui-legacy-client ls /app/backend/data/test-file.txt

# Verify application accessible
curl -f http://localhost:8091/
```

**Expected Results:**
- ✅ Container using Docker volume again
- ✅ Data intact after rollback
- ✅ Application continues to function

**Cleanup:**
```bash
docker stop openwebui-legacy-client && docker rm openwebui-legacy-client
docker volume rm openwebui-legacy-client-data
rm -rf /opt/openwebui/legacy-client
```

---

### Test 3.3: client-manager.sh Updates

**Archon Task ID:** `710ff6f6-c130-4af8-8fb5-c6541c2f8f60`
**Task:** Task 3.3: Update client-manager.sh deployment workflow

**Test File:** `client-manager.sh`

**Test Steps:**

**Test 3.3.1: New Deployment Workflow**
```bash
# Run client-manager interactively
./client-manager.sh

# Select: 3) Create New Deployment
# Enter test values and verify volume-based deployment
```

**Expected Results:**
- ✅ Client directory created before container deployment
- ✅ Static assets initialized
- ✅ Volume mounts configured automatically
- ✅ Deployment successful

**Test 3.3.2: Volume Usage Display**
```bash
# Run client-manager
./client-manager.sh

# Select: 4) Manage Client Deployment
# Select client
# Choose option to view volume usage
```

**Expected Results:**
- ✅ Shows disk usage per client
- ✅ Displays directory paths
- ✅ Shows breakdown of data vs static

**Test 3.3.3: Migration Menu Option**
```bash
# Run client-manager
./client-manager.sh

# Verify new menu option exists
# Select: 7) Migrate to Volume-Based Deployment
```

**Expected Results:**
- ✅ Migration option visible in menu
- ✅ Launches migration script correctly
- ✅ Shows progress and results

---

## Phase 4: Documentation & Distribution Tests

### Test 4.1: User Documentation

**Archon Task ID:** `e39acc71-98d2-482e-b5ee-c6e6f53d22f8`
**Task:** Task 4.1: Create comprehensive user documentation

**Test Files:** `QUICK_START.md`, `TROUBLESHOOTING.md`

**Test Steps:**

**Test 4.1.1: Quick Start Validation**
```bash
# Follow QUICK_START.md exactly as written
# Use fresh Ubuntu 22.04 VM or container

# Time the process
time {
  # Step 1: Run quick setup
  curl -fsSL https://raw.githubusercontent.com/yourorg/open-webui-infrastructure/main/setup/quick-setup.sh | bash

  # Step 2: Deploy first client
  ./client-manager.sh
  # Follow prompts

  # Step 3: Access deployment
  curl http://localhost:8081/
}

# Should complete in < 15 minutes
```

**Expected Results:**
- ✅ Instructions are clear and accurate
- ✅ Process completes in 15 minutes or less
- ✅ No missing steps or unclear instructions
- ✅ New user can successfully deploy

**Test 4.1.2: Troubleshooting Guide Validation**
```bash
# Test common issues documented

# Issue 1: Branding not appearing
# Follow troubleshooting steps
# Verify solution works

# Issue 2: Container won't start
# Follow diagnostic steps
# Verify helpful error identification
```

**Expected Results:**
- ✅ Common issues covered
- ✅ Solutions are accurate and helpful
- ✅ Diagnostic commands work as described

---

### Test 4.2: Configuration Examples

**Archon Task ID:** `77db5077-c3d5-4ea1-9688-2f999503485b`
**Task:** Task 4.2: Create configuration examples repository

**Test Directory:** `examples/`

**Test Steps:**

**Test 4.2.1: Basic Deployment Example**
```bash
# Navigate to example
cd examples/basic-deployment/

# Follow example instructions
bash deploy.sh

# Verify deployment
curl http://localhost:8080/
```

**Expected Results:**
- ✅ Example deploys successfully
- ✅ Instructions are clear
- ✅ Easy to understand and adapt

**Test 4.2.2: Example Coverage**
```bash
# Verify all examples present
[ -d "examples/basic-deployment" ] && echo "✅ basic-deployment"
[ -d "examples/multi-client-saas" ] && echo "✅ multi-client-saas"
[ -d "examples/custom-branding" ] && echo "✅ custom-branding"
[ -d "examples/high-availability" ] && echo "✅ high-availability"
[ -d "examples/postgresql-migration" ] && echo "✅ postgresql-migration"
```

**Expected Results:**
- ✅ At least 5 examples present
- ✅ Each example documented
- ✅ README index in examples/

---

### Test 4.3: Automated Test Suite

**Archon Task ID:** `85e426a6-48e6-464d-83ed-5651282d6d58`
**Task:** Task 4.3: Create automated testing and validation suite

**Test File:** `tests/integration/test-full-deployment.sh`

**Test Steps:**

**Test 4.3.1: Run Full Test Suite**
```bash
cd tests/integration/
bash test-full-deployment.sh
```

**Expected Results:**
- ✅ All tests pass (5/5)
- ✅ Clear test output
- ✅ Exit code 0 on success
- ✅ Meaningful error messages on failure

**Test 4.3.2: Individual Test Validation**
```bash
# Test 1: Fresh deployment
# Test 2: Branding application
# Test 3: Container recreation
# Test 4: Volume isolation
# Test 5: Cleanup

# Each test should:
# - Execute independently
# - Have clear pass/fail criteria
# - Clean up after itself
```

**Expected Results:**
- ✅ Each test can run independently
- ✅ Tests are idempotent
- ✅ No leftover artifacts after cleanup

**Test 4.3.3: Version Compatibility Matrix**
```bash
# Test with different Open WebUI versions
for version in main latest v0.3.0; do
  echo "Testing with $version"
  OPENWEBUI_IMAGE_TAG=$version bash test-full-deployment.sh
done
```

**Expected Results:**
- ✅ Tests pass with multiple versions
- ✅ Version-specific issues identified
- ✅ Compatibility matrix updated

---

### Test 4.4: Publication & Distribution

**Archon Task ID:** `88283d5a-db85-4f91-98bc-e6597b00ed81`
**Task:** Task 4.4: Publish repository and create community announcement

**Test Steps:**

**Test 4.4.1: Release Tag Validation**
```bash
# Check release tag
git tag -l | grep v1.0.0

# Check release notes
git show v1.0.0
```

**Expected Results:**
- ✅ v1.0.0 tag created
- ✅ Release notes comprehensive
- ✅ Changelog complete

**Test 4.4.2: Fork Deprecation Notice**
```bash
# Check fork README updated
curl https://raw.githubusercontent.com/yourorg/open-webui/main/README.md | grep -i "deprecation"

# Should show deprecation notice at top
```

**Expected Results:**
- ✅ Deprecation notice visible
- ✅ Links to new repository
- ✅ Migration guide referenced

**Test 4.4.3: Community Announcement**
```bash
# Verify announcement posted
# Check Open WebUI discussions on GitHub
# Verify links work and information accurate
```

**Expected Results:**
- ✅ Announcement posted in appropriate forum
- ✅ Information accurate and helpful
- ✅ Links to repository and documentation work

---

## Testing Summary

### Automated Test Execution

**Run all tests:**
```bash
# From repository root
bash tests/run-all-tests.sh
```

**Expected output:**
```
=== Open WebUI Infrastructure Segregation Tests ===

Phase 0: Prototype Testing
✅ Test 0.1: Create Prototype Branch - PASS
✅ Test 0.2: Manual Volume Mount Prototype - PASS

Phase 1: Volume Mounting Tests
✅ Test 1.1: Default Asset Extraction - PASS
✅ Test 1.2: start-template.sh Updates - PASS
✅ Test 1.3: apply-branding.sh Host Mode - PASS
✅ Test 1.4: Branding Persistence - PASS

Phase 2: Repository Extraction Tests
✅ Test 2.1: Repository Structure - PASS
✅ Test 2.2: Central Configuration - PASS
✅ Test 2.3: Shared Library System - PASS
✅ Test 2.4: Documentation Updates - PASS

Phase 3: Migration Path Tests
✅ Test 3.1: Migration Script - PASS
✅ Test 3.2: Rollback Procedure - PASS
✅ Test 3.3: client-manager Updates - PASS

Phase 4: Documentation & Distribution Tests
✅ Test 4.1: User Documentation - PASS
✅ Test 4.2: Configuration Examples - PASS
✅ Test 4.3: Automated Test Suite - PASS
✅ Test 4.4: Publication - PASS

=== All Tests Passed (16/16) ===
```

### Test Execution Order

Tests must be executed in order as later tests depend on earlier implementations:

1. **Phase 0 → Phase 1** (Prototype validates approach)
2. **Phase 1 → Phase 2** (Volume mounts must work before refactoring)
3. **Phase 2 → Phase 3** (Repository must exist before migration)
4. **Phase 3 → Phase 4** (Migration must work before public release)

### Test Failure Handling

If any test fails:
1. Review test output for error details
2. Check corresponding Archon task for implementation guidance
3. Fix issue and re-run test
4. Document issue in troubleshooting guide
5. Update test if expectations were incorrect

---

## Appendix

### Test Environment Requirements

**Minimum Test Environment:**
- Ubuntu 20.04+ or 22.04
- Docker 20.10+
- 4GB RAM (for running test containers)
- 20GB free disk space
- Network access to Docker Hub and GitHub

**Recommended Test Environment:**
- Fresh Digital Ocean droplet (2GB/50GB)
- Clean slate for accurate testing
- Matches production environment

### Test Data Management

**Test Artifacts:**
```
/opt/openwebui/test-artifacts/
├── backups/          # Test backups
├── logs/             # Test execution logs
├── screenshots/      # Manual test screenshots
└── reports/          # Test reports
```

**Cleanup After Testing:**
```bash
# Remove all test artifacts
rm -rf /opt/openwebui/test-*
docker rm -f $(docker ps -aq --filter name=test)
docker volume prune -f
```

### Continuous Testing

**Pre-Commit Tests:**
```bash
# Run quick tests before committing
bash tests/quick-test.sh
```

**Pre-Release Tests:**
```bash
# Run full test suite before releasing
bash tests/run-all-tests.sh
```

**Version Compatibility Tests:**
```bash
# Test with multiple Open WebUI versions
bash tests/test-compatibility.sh
```

---

**End of Testing Documentation**
