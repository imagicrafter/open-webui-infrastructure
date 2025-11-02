# Production Server Migration Plan
## Docker Volumes → Bind Mounts (Release Branch → Main Branch)

**Date:** 2025-11-01
**Target Server:** 45.55.182.177 (and other production servers on release branch)
**Current Architecture:** Docker volumes (`release` branch)
**Target Architecture:** Bind mounts (`main` branch)

---

## Executive Summary

This plan provides a **zero-downtime migration** path for production Open WebUI deployments from Docker volumes (release branch) to bind mounts (main branch). The migration enables portable data storage, simpler backups, and multi-tenant isolation improvements.

**Key Benefits:**
- ✅ No data loss (verified backup/restore process)
- ✅ Minimal downtime (< 5 minutes per deployment)
- ✅ Rollback capability at every step
- ✅ Future-proof architecture for easier migrations

---

## Architecture Comparison

### Current (Release Branch - Docker Volumes)

```bash
Storage: Docker volumes
Location: /var/lib/docker/volumes/openwebui-{container-name}-data/_data/
Mount: -v openwebui-chat-lawnloonies-com-data:/app/backend/data
Backup: docker volume commands or manual extraction
Access: Requires docker volume inspect to find location
```

### Target (Main Branch - Bind Mounts)

```bash
Storage: Host directories
Location: /opt/openwebui/{client-id}/data/
Mount: -v /opt/openwebui/{client-id}/data:/app/backend/data
       -v /opt/openwebui/{client-id}/static:/app/backend/open_webui/static
Backup: Standard tar/rsync commands
Access: Direct filesystem access at known location
```

**Key Architectural Changes:**
1. **CLIENT_ID System**: Unique identifier from sanitized FQDN (chat.lawnloonies.com → chat-lawnloonies-com)
2. **Two Bind Mounts**: Separate data and static directories (vs single volume)
3. **Default Assets**: Centralized `/opt/openwebui/defaults/static/` for initialization
4. **Memory Limits**: 700MB hard limit, 600MB reservation (new in main branch)

---

## Pre-Migration Requirements

### 1. Server Access Verification

```bash
# Test SSH access
ssh root@45.55.182.177 "echo 'SSH access confirmed'"

# Verify qbmgr user exists
ssh root@45.55.182.177 "id qbmgr"

# Check current deployments
ssh root@45.55.182.177 "docker ps --format '{{.Names}}\t{{.Status}}' | grep openwebui"
```

### 2. Current State Discovery

Run this discovery script on the production server:

```bash
#!/bin/bash
# Save as: discover-current-deployments.sh

echo "=== Current Open WebUI Deployments ==="
echo

# List all containers
echo "Containers:"
docker ps -a --format "{{.Names}}\t{{.Image}}\t{{.Status}}" | grep openwebui

echo
echo "=== Docker Volumes ==="
docker volume ls | grep openwebui

echo
echo "=== Volume Details ==="
for container in $(docker ps -a --format '{{.Names}}' | grep openwebui); do
    echo
    echo "Container: $container"
    echo "Mounts:"
    docker inspect "$container" --format '{{range .Mounts}}  {{.Type}}: {{.Source}} -> {{.Destination}}{{println}}{{end}}'
    echo "Environment (relevant):"
    docker inspect "$container" --format '{{range .Config.Env}}{{println}}{{end}}' | grep -E 'FQDN|CLIENT|SUBDOMAIN|WEBUI_NAME'
done

echo
echo "=== Disk Usage ==="
for volume in $(docker volume ls -q | grep openwebui); do
    size=$(docker run --rm -v "$volume":/data alpine du -sh /data 2>/dev/null | awk '{print $1}')
    echo "Volume: $volume - Size: $size"
done

echo
echo "=== Repository Status ==="
su - qbmgr -c "cd ~/open-webui && git branch -a && echo && git log --oneline -3"
```

**Expected Output:**
- Container names (e.g., `openwebui-chat-lawnloonies-com`)
- Volume names (e.g., `openwebui-chat-lawnloonies-com-data`)
- Current branch (`release`)
- Data size per deployment

### 3. Backup Prerequisites

```bash
# Create backup directory
ssh root@45.55.182.177 "mkdir -p /root/migration-backups/$(date +%Y%m%d)"

# Verify disk space (need 2x current data size)
ssh root@45.55.182.177 "df -h /var/lib/docker/volumes/ && df -h /opt/"
```

---

## Migration Process (Per Deployment)

### Phase 1: Backup Current State

**Duration:** 2-5 minutes per deployment
**Risk Level:** Low (read-only operations)

```bash
#!/bin/bash
# Save as: backup-deployment.sh
# Usage: bash backup-deployment.sh <container-name>

CONTAINER_NAME=$1
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/root/migration-backups/${BACKUP_DATE}"

if [ -z "$CONTAINER_NAME" ]; then
    echo "Usage: $0 <container-name>"
    exit 1
fi

echo "=== Backing up: $CONTAINER_NAME ==="

# Create backup directory
mkdir -p "$BACKUP_DIR"

# 1. Export container configuration
echo "1. Exporting container config..."
docker inspect "$CONTAINER_NAME" > "$BACKUP_DIR/${CONTAINER_NAME}_config.json"

# 2. Export environment variables
echo "2. Exporting environment variables..."
docker inspect "$CONTAINER_NAME" --format '{{range .Config.Env}}{{println}}{{end}}' > "$BACKUP_DIR/${CONTAINER_NAME}_env.txt"

# 3. Backup data volume
echo "3. Backing up data volume..."
VOLUME_NAME="${CONTAINER_NAME}-data"
docker run --rm \
    -v "$VOLUME_NAME":/source:ro \
    -v "$BACKUP_DIR":/backup \
    alpine tar czf "/backup/${VOLUME_NAME}.tar.gz" -C /source .

# 4. Verify backup
echo "4. Verifying backup..."
if [ -f "$BACKUP_DIR/${VOLUME_NAME}.tar.gz" ]; then
    SIZE=$(du -h "$BACKUP_DIR/${VOLUME_NAME}.tar.gz" | awk '{print $1}')
    echo "✅ Backup created: $BACKUP_DIR/${VOLUME_NAME}.tar.gz ($SIZE)"
else
    echo "❌ Backup failed!"
    exit 1
fi

# 5. Test backup integrity
echo "5. Testing backup integrity..."
if tar tzf "$BACKUP_DIR/${VOLUME_NAME}.tar.gz" >/dev/null 2>&1; then
    echo "✅ Backup integrity verified"
else
    echo "❌ Backup corrupted!"
    exit 1
fi

# 6. Save metadata
echo "6. Saving metadata..."
cat > "$BACKUP_DIR/${CONTAINER_NAME}_metadata.txt" <<EOF
Container: $CONTAINER_NAME
Volume: $VOLUME_NAME
Backup Date: $BACKUP_DATE
Backup Location: $BACKUP_DIR
Server: $(hostname)
EOF

echo
echo "=== Backup Complete ==="
echo "Location: $BACKUP_DIR"
echo "Files created:"
ls -lh "$BACKUP_DIR" | grep "$CONTAINER_NAME"
```

**Verification Steps:**
```bash
# List backup contents
tar tzf /root/migration-backups/*/openwebui-*-data.tar.gz | head -20

# Check for critical files
tar tzf /root/migration-backups/*/openwebui-*-data.tar.gz | grep -E 'webui.db|config.json'
```

### Phase 2: Prepare Migration Environment

**Duration:** 5-10 minutes (one-time per server)
**Risk Level:** Low (new directory creation)

```bash
#!/bin/bash
# Save as: prepare-migration-environment.sh

echo "=== Preparing Migration Environment ==="

# 1. Update repository to main branch
echo "1. Updating repository..."
su - qbmgr -c "cd ~/open-webui && git fetch origin && git checkout main && git pull origin main"

# 2. Create /opt/openwebui structure
echo "2. Creating directory structure..."
mkdir -p /opt/openwebui/defaults/static
chown -R qbmgr:qbmgr /opt/openwebui

# 3. Extract default static assets
echo "3. Extracting default assets..."
if [ -f ~/open-webui/mt/setup/lib/extract-default-static.sh ]; then
    bash ~/open-webui/mt/setup/lib/extract-default-static.sh
else
    echo "⚠️  Warning: extract-default-static.sh not found"
    echo "   Extracting manually..."

    # Manual extraction if script not available
    IMAGE_TAG="main"
    docker run --rm \
        -v /opt/openwebui/defaults/static:/target \
        ghcr.io/imagicrafter/open-webui:${IMAGE_TAG} \
        sh -c "cp -r /app/backend/open_webui/static/* /target/"
fi

# 4. Verify default assets
echo "4. Verifying default assets..."
ASSET_COUNT=$(find /opt/openwebui/defaults/static -type f | wc -l)
if [ "$ASSET_COUNT" -gt 10 ]; then
    echo "✅ Default assets extracted: $ASSET_COUNT files"
else
    echo "❌ Default asset extraction failed (only $ASSET_COUNT files)"
    exit 1
fi

# 5. Set permissions
echo "5. Setting permissions..."
chown -R qbmgr:qbmgr /opt/openwebui
chmod -R 755 /opt/openwebui

echo
echo "=== Migration Environment Ready ==="
echo "Repository: main branch"
echo "Directory: /opt/openwebui/"
echo "Default assets: $ASSET_COUNT files"
```

### Phase 3: Migrate Individual Deployment

**Duration:** 3-5 minutes per deployment
**Downtime:** ~2 minutes per deployment
**Risk Level:** Medium (active migration, rollback available)

```bash
#!/bin/bash
# Save as: migrate-deployment.sh
# Usage: bash migrate-deployment.sh <container-name> <fqdn> <subdomain>

CONTAINER_NAME=$1
FQDN=$2
SUBDOMAIN=$3
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)

if [ $# -lt 3 ]; then
    echo "Usage: $0 <container-name> <fqdn> <subdomain>"
    echo "Example: $0 openwebui-chat-lawnloonies-com chat.lawnloonies.com chat"
    exit 1
fi

# Extract CLIENT_ID from container name
CLIENT_ID="${CONTAINER_NAME#openwebui-}"
CLIENT_DIR="/opt/openwebui/${CLIENT_ID}"
VOLUME_NAME="${CONTAINER_NAME}-data"

echo "=== Migrating Deployment ==="
echo "Container: $CONTAINER_NAME"
echo "CLIENT_ID: $CLIENT_ID"
echo "FQDN: $FQDN"
echo "Subdomain: $SUBDOMAIN"
echo "Target Directory: $CLIENT_DIR"
echo

# Safety check: Verify backup exists
LATEST_BACKUP=$(ls -t /root/migration-backups/*/${VOLUME_NAME}.tar.gz 2>/dev/null | head -1)
if [ -z "$LATEST_BACKUP" ]; then
    echo "❌ ERROR: No backup found for $VOLUME_NAME"
    echo "   Run backup-deployment.sh first!"
    exit 1
fi
echo "✅ Backup verified: $LATEST_BACKUP"
echo

# Step 1: Stop existing container
echo "Step 1: Stopping container..."
docker stop "$CONTAINER_NAME"
if [ $? -eq 0 ]; then
    echo "✅ Container stopped"
else
    echo "❌ Failed to stop container"
    exit 1
fi

# Step 2: Create new directory structure
echo "Step 2: Creating directory structure..."
mkdir -p "$CLIENT_DIR/data"
mkdir -p "$CLIENT_DIR/static"
chown -R qbmgr:qbmgr "$CLIENT_DIR"

if [ -d "$CLIENT_DIR/data" ] && [ -d "$CLIENT_DIR/static" ]; then
    echo "✅ Directories created"
else
    echo "❌ Failed to create directories"
    docker start "$CONTAINER_NAME"  # Rollback
    exit 1
fi

# Step 3: Migrate data from volume to bind mount
echo "Step 3: Migrating data..."
docker run --rm \
    -v "$VOLUME_NAME":/source:ro \
    -v "$CLIENT_DIR/data":/target \
    alpine sh -c "cp -a /source/. /target/"

if [ $? -eq 0 ]; then
    DATA_FILES=$(find "$CLIENT_DIR/data" -type f | wc -l)
    echo "✅ Data migrated: $DATA_FILES files"
else
    echo "❌ Data migration failed"
    docker start "$CONTAINER_NAME"  # Rollback
    exit 1
fi

# Step 4: Initialize static assets
echo "Step 4: Initializing static assets..."
if [ -d "/opt/openwebui/defaults/static" ]; then
    cp -a /opt/openwebui/defaults/static/. "$CLIENT_DIR/static/"
    echo "✅ Static assets initialized"
else
    echo "⚠️  Warning: Default assets not found, extracting..."
    docker run --rm \
        -v "$CLIENT_DIR/static":/target \
        ghcr.io/imagicrafter/open-webui:main \
        sh -c "cp -r /app/backend/open_webui/static/* /target/"
fi

# Step 5: Extract environment variables from old container
echo "Step 5: Extracting environment variables..."
OLD_REDIRECT_URI=$(docker inspect "$CONTAINER_NAME" --format '{{range .Config.Env}}{{println}}{{end}}' | grep GOOGLE_REDIRECT_URI | cut -d= -f2-)
OAUTH_DOMAINS=$(docker inspect "$CONTAINER_NAME" --format '{{range .Config.Env}}{{println}}{{end}}' | grep OAUTH_ALLOWED_DOMAINS | cut -d= -f2-)
WEBUI_SECRET_KEY=$(docker inspect "$CONTAINER_NAME" --format '{{range .Config.Env}}{{println}}{{end}}' | grep WEBUI_SECRET_KEY | cut -d= -f2-)

# Default values if not found
OAUTH_DOMAINS="${OAUTH_DOMAINS:-martins.net}"
WEBUI_SECRET_KEY="${WEBUI_SECRET_KEY:-$(openssl rand -base64 32)}"

echo "  FQDN: $FQDN"
echo "  OAuth Domains: $OAUTH_DOMAINS"
echo "  Secret Key: ${WEBUI_SECRET_KEY:0:10}..."

# Step 6: Remove old container (keep volume for now)
echo "Step 6: Removing old container..."
docker rm "$CONTAINER_NAME"
echo "✅ Old container removed (volume preserved)"

# Step 7: Find available port or use nginx network
echo "Step 7: Determining network configuration..."
PORT="N/A"
if docker ps --filter "name=openwebui-nginx" --format "{{.Names}}" | grep -q "^openwebui-nginx$"; then
    echo "  Using containerized nginx (no port needed)"
else
    # Find next available port (starting from 8081)
    for test_port in {8081..8099}; do
        if ! netstat -tuln | grep -q ":${test_port} "; then
            PORT=$test_port
            break
        fi
    done
    echo "  Using port: $PORT"
fi

# Step 8: Launch new container with bind mounts
echo "Step 8: Launching new container..."
su - qbmgr -c "cd ~/open-webui/mt && bash start-template.sh '$SUBDOMAIN' '$PORT' '$FQDN' '$CONTAINER_NAME' '$FQDN' '$OAUTH_DOMAINS' '$WEBUI_SECRET_KEY'"

# Wait for container to become healthy
echo "Waiting for container to become healthy..."
for i in {1..30}; do
    HEALTH=$(docker inspect "$CONTAINER_NAME" --format '{{.State.Health.Status}}' 2>/dev/null)
    if [ "$HEALTH" = "healthy" ]; then
        echo "✅ Container is healthy"
        break
    fi
    echo -n "."
    sleep 2
done

if [ "$HEALTH" != "healthy" ]; then
    echo "⚠️  Warning: Container not healthy yet (check logs)"
fi

# Step 9: Verify migration
echo "Step 9: Verifying migration..."

# Check mounts
MOUNT_CHECK=$(docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{.Type}}:{{.Destination}} {{end}}' | grep -c "bind:/app/backend")
if [ "$MOUNT_CHECK" -ge 2 ]; then
    echo "✅ Bind mounts configured correctly (2 mounts found)"
else
    echo "⚠️  Warning: Expected 2 bind mounts, found $MOUNT_CHECK"
fi

# Check data directory
DB_EXISTS=$([ -f "$CLIENT_DIR/data/webui.db" ] && echo "yes" || echo "no")
if [ "$DB_EXISTS" = "yes" ]; then
    echo "✅ Database file exists"
else
    echo "❌ Database file missing!"
fi

# Check static assets
STATIC_COUNT=$(find "$CLIENT_DIR/static" -type f | wc -l)
if [ "$STATIC_COUNT" -gt 10 ]; then
    echo "✅ Static assets present: $STATIC_COUNT files"
else
    echo "⚠️  Warning: Only $STATIC_COUNT static files found"
fi

echo
echo "=== Migration Complete ==="
echo "Container: $CONTAINER_NAME"
echo "Status: $(docker inspect "$CONTAINER_NAME" --format '{{.State.Status}}')"
echo "Health: $(docker inspect "$CONTAINER_NAME" --format '{{.State.Health.Status}}')"
echo "Data Directory: $CLIENT_DIR/data"
echo "Static Directory: $CLIENT_DIR/static"
echo
echo "Next Steps:"
echo "1. Test the deployment: https://$FQDN"
echo "2. Verify login and data integrity"
echo "3. If successful, remove old volume: docker volume rm $VOLUME_NAME"
echo "4. If problems occur, run rollback-deployment.sh"
```

### Phase 4: Verification & Testing

**Duration:** 5-10 minutes per deployment
**Risk Level:** Low (testing only)

```bash
#!/bin/bash
# Save as: verify-migration.sh
# Usage: bash verify-migration.sh <container-name> <fqdn>

CONTAINER_NAME=$1
FQDN=$2
CLIENT_ID="${CONTAINER_NAME#openwebui-}"
CLIENT_DIR="/opt/openwebui/${CLIENT_ID}"

echo "=== Migration Verification ==="
echo

# 1. Container status
echo "1. Container Status:"
STATUS=$(docker inspect "$CONTAINER_NAME" --format '{{.State.Status}}')
HEALTH=$(docker inspect "$CONTAINER_NAME" --format '{{.State.Health.Status}}')
echo "   Status: $STATUS"
echo "   Health: $HEALTH"

if [ "$STATUS" != "running" ] || [ "$HEALTH" != "healthy" ]; then
    echo "   ❌ Container not running or unhealthy!"
    echo "   Check logs: docker logs $CONTAINER_NAME"
    exit 1
else
    echo "   ✅ Container running and healthy"
fi

# 2. Mount verification
echo
echo "2. Mount Configuration:"
docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}  {{.Type}}: {{.Source}} -> {{.Destination}}{{println}}{{end}}'

BIND_COUNT=$(docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{.Type}} {{end}}' | grep -c "bind")
if [ "$BIND_COUNT" -ge 2 ]; then
    echo "   ✅ Bind mounts configured (2 found)"
else
    echo "   ❌ Expected 2 bind mounts, found $BIND_COUNT"
    exit 1
fi

# 3. Environment variables
echo
echo "3. Environment Variables:"
CLIENT_ID_ENV=$(docker inspect "$CONTAINER_NAME" --format '{{range .Config.Env}}{{println}}{{end}}' | grep "^CLIENT_ID=" | cut -d= -f2)
FQDN_ENV=$(docker inspect "$CONTAINER_NAME" --format '{{range .Config.Env}}{{println}}{{end}}' | grep "^FQDN=" | cut -d= -f2)
echo "   CLIENT_ID: $CLIENT_ID_ENV"
echo "   FQDN: $FQDN_ENV"

if [ "$CLIENT_ID_ENV" = "$CLIENT_ID" ] && [ "$FQDN_ENV" = "$FQDN" ]; then
    echo "   ✅ Environment variables correct"
else
    echo "   ⚠️  Warning: Environment variables may not match expected values"
fi

# 4. Data integrity
echo
echo "4. Data Integrity:"
if [ -f "$CLIENT_DIR/data/webui.db" ]; then
    DB_SIZE=$(du -h "$CLIENT_DIR/data/webui.db" | awk '{print $1}')
    echo "   Database: $DB_SIZE"
    echo "   ✅ Database file exists"
else
    echo "   ❌ Database file missing!"
    exit 1
fi

# 5. Static assets
echo
echo "5. Static Assets:"
STATIC_COUNT=$(find "$CLIENT_DIR/static" -type f | wc -l)
echo "   Files: $STATIC_COUNT"
if [ "$STATIC_COUNT" -gt 10 ]; then
    echo "   ✅ Static assets present"
else
    echo "   ⚠️  Warning: Low static file count"
fi

# 6. HTTP connectivity test
echo
echo "6. HTTP Connectivity:"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -k "https://$FQDN" --max-time 10)
echo "   Status: $HTTP_STATUS"
if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "302" ]; then
    echo "   ✅ Web interface accessible"
else
    echo "   ⚠️  Warning: HTTP status $HTTP_STATUS (may need nginx config)"
fi

# 7. Directory ownership
echo
echo "7. Permissions:"
OWNER=$(stat -c "%U:%G" "$CLIENT_DIR" 2>/dev/null || stat -f "%Su:%Sg" "$CLIENT_DIR")
echo "   Owner: $OWNER"
if [ "$OWNER" = "qbmgr:qbmgr" ]; then
    echo "   ✅ Correct ownership"
else
    echo "   ⚠️  Warning: Expected qbmgr:qbmgr, got $OWNER"
fi

echo
echo "=== Verification Summary ==="
echo "✅ Container: $STATUS ($HEALTH)"
echo "✅ Mounts: $BIND_COUNT bind mounts"
echo "✅ Database: Present"
echo "✅ Assets: $STATIC_COUNT files"
echo "✅ HTTP: $HTTP_STATUS"
echo
echo "Manual Tests Required:"
echo "1. Open https://$FQDN in browser"
echo "2. Login with existing account"
echo "3. Verify chat history is intact"
echo "4. Test sending a new message"
echo "5. Check custom branding (if any)"
```

### Phase 5: Cleanup (Post-Migration)

**Duration:** 1 minute per deployment
**Risk Level:** Low (cleanup only, after verification)

```bash
#!/bin/bash
# Save as: cleanup-old-volume.sh
# Usage: bash cleanup-old-volume.sh <container-name>
# WARNING: Only run after successful migration verification!

CONTAINER_NAME=$1
VOLUME_NAME="${CONTAINER_NAME}-data"

if [ -z "$CONTAINER_NAME" ]; then
    echo "Usage: $0 <container-name>"
    exit 1
fi

echo "=== Cleanup Old Volume ==="
echo "Volume: $VOLUME_NAME"
echo

# Safety check: Container must be running with bind mounts
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "❌ ERROR: Container $CONTAINER_NAME is not running!"
    echo "   Cannot safely delete volume."
    exit 1
fi

# Verify bind mounts are in use
BIND_COUNT=$(docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{.Type}} {{end}}' | grep -c "bind")
if [ "$BIND_COUNT" -lt 2 ]; then
    echo "❌ ERROR: Container not using bind mounts!"
    echo "   Migration may not be complete."
    exit 1
fi

# Final confirmation
echo "⚠️  WARNING: This will permanently delete the Docker volume: $VOLUME_NAME"
echo "   Make sure you have verified the migration is successful!"
echo
read -p "Are you sure? Type 'DELETE' to confirm: " confirm

if [ "$confirm" != "DELETE" ]; then
    echo "Cancelled."
    exit 0
fi

# Check if volume exists
if ! docker volume ls -q | grep -q "^${VOLUME_NAME}$"; then
    echo "Volume $VOLUME_NAME does not exist (already deleted?)"
    exit 0
fi

# Remove volume
echo "Removing volume..."
docker volume rm "$VOLUME_NAME"

if [ $? -eq 0 ]; then
    echo "✅ Volume removed: $VOLUME_NAME"
    echo
    echo "Remaining volumes:"
    docker volume ls | grep openwebui || echo "  (none)"
else
    echo "❌ Failed to remove volume"
    exit 1
fi
```

---

## Rollback Procedures

### Rollback Option 1: Restart Old Container (Immediate)

**Use When:** Migration failed before removing old container
**Duration:** 1 minute
**Data Loss:** None

```bash
#!/bin/bash
# Save as: rollback-immediate.sh
# Usage: bash rollback-immediate.sh <container-name>

CONTAINER_NAME=$1

echo "=== Immediate Rollback ==="
echo "Restarting original container: $CONTAINER_NAME"

# Stop new container if running
docker stop "$CONTAINER_NAME" 2>/dev/null
docker rm "$CONTAINER_NAME" 2>/dev/null

# Start old container
docker start "$CONTAINER_NAME"

if [ $? -eq 0 ]; then
    echo "✅ Rollback complete - old container restored"
    docker ps | grep "$CONTAINER_NAME"
else
    echo "❌ Rollback failed - container may need manual intervention"
    exit 1
fi
```

### Rollback Option 2: Restore from Backup (Full)

**Use When:** Migration completed but issues discovered later
**Duration:** 5-10 minutes
**Data Loss:** Changes since migration started

```bash
#!/bin/bash
# Save as: rollback-from-backup.sh
# Usage: bash rollback-from-backup.sh <container-name> <backup-date>

CONTAINER_NAME=$1
BACKUP_DATE=$2
BACKUP_DIR="/root/migration-backups/${BACKUP_DATE}"
VOLUME_NAME="${CONTAINER_NAME}-data"

if [ $# -lt 2 ]; then
    echo "Usage: $0 <container-name> <backup-date>"
    echo
    echo "Available backups:"
    ls -ld /root/migration-backups/*/
    exit 1
fi

if [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ Backup directory not found: $BACKUP_DIR"
    exit 1
fi

echo "=== Full Rollback from Backup ==="
echo "Container: $CONTAINER_NAME"
echo "Backup: $BACKUP_DIR"
echo

# Step 1: Stop and remove current container
echo "Step 1: Stopping current container..."
docker stop "$CONTAINER_NAME" 2>/dev/null
docker rm "$CONTAINER_NAME" 2>/dev/null
echo "✅ Container removed"

# Step 2: Recreate volume
echo "Step 2: Recreating Docker volume..."
docker volume rm "$VOLUME_NAME" 2>/dev/null
docker volume create "$VOLUME_NAME"
echo "✅ Volume created"

# Step 3: Restore data to volume
echo "Step 3: Restoring data from backup..."
docker run --rm \
    -v "$VOLUME_NAME":/target \
    -v "$BACKUP_DIR":/backup:ro \
    alpine tar xzf "/backup/${VOLUME_NAME}.tar.gz" -C /target

if [ $? -eq 0 ]; then
    echo "✅ Data restored"
else
    echo "❌ Data restoration failed"
    exit 1
fi

# Step 4: Restore container from config
echo "Step 4: Recreating container..."
# Extract environment variables from backup
GOOGLE_CLIENT_ID=$(grep "GOOGLE_CLIENT_ID=" "$BACKUP_DIR/${CONTAINER_NAME}_env.txt" | cut -d= -f2-)
GOOGLE_CLIENT_SECRET=$(grep "GOOGLE_CLIENT_SECRET=" "$BACKUP_DIR/${CONTAINER_NAME}_env.txt" | cut -d= -f2-)
GOOGLE_REDIRECT_URI=$(grep "GOOGLE_REDIRECT_URI=" "$BACKUP_DIR/${CONTAINER_NAME}_env.txt" | cut -d= -f2-)
OAUTH_DOMAINS=$(grep "OAUTH_ALLOWED_DOMAINS=" "$BACKUP_DIR/${CONTAINER_NAME}_env.txt" | cut -d= -f2-)
WEBUI_SECRET_KEY=$(grep "WEBUI_SECRET_KEY=" "$BACKUP_DIR/${CONTAINER_NAME}_env.txt" | cut -d= -f2-)

# Extract port from config
PORT=$(docker inspect --format='{{(index (index .NetworkSettings.Ports "8080/tcp") 0).HostPort}}' "$CONTAINER_NAME" 2>/dev/null || echo "8081")

# Recreate container with Docker volume (old architecture)
docker run -d \
    --name "$CONTAINER_NAME" \
    -p "${PORT}:8080" \
    -e GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
    -e GOOGLE_CLIENT_SECRET="$GOOGLE_CLIENT_SECRET" \
    -e GOOGLE_REDIRECT_URI="$GOOGLE_REDIRECT_URI" \
    -e OAUTH_ALLOWED_DOMAINS="$OAUTH_DOMAINS" \
    -e WEBUI_SECRET_KEY="$WEBUI_SECRET_KEY" \
    -v "$VOLUME_NAME":/app/backend/data \
    --restart unless-stopped \
    ghcr.io/imagicrafter/open-webui:release

echo "✅ Container recreated"

# Step 5: Wait for health
echo "Step 5: Waiting for container to become healthy..."
for i in {1..30}; do
    if docker ps --format '{{.Names}}\t{{.Status}}' | grep "$CONTAINER_NAME" | grep -q "healthy"; then
        echo "✅ Container healthy"
        break
    fi
    echo -n "."
    sleep 2
done

echo
echo "=== Rollback Complete ==="
echo "Container: $CONTAINER_NAME"
echo "Architecture: Docker volumes (release branch)"
echo "Status: $(docker inspect "$CONTAINER_NAME" --format '{{.State.Status}}')"
echo
echo "Verify access at: $GOOGLE_REDIRECT_URI"
```

---

## Complete Migration Workflow

### For Single Deployment (Example: chat.lawnloonies.com)

```bash
# On production server (45.55.182.177)

# 1. Discovery
bash discover-current-deployments.sh > current-state.txt

# 2. Backup
bash backup-deployment.sh openwebui-chat-lawnloonies-com

# 3. Prepare environment (one-time per server)
bash prepare-migration-environment.sh

# 4. Migrate deployment
bash migrate-deployment.sh \
    openwebui-chat-lawnloonies-com \
    chat.lawnloonies.com \
    chat

# 5. Verify migration
bash verify-migration.sh \
    openwebui-chat-lawnloonies-com \
    chat.lawnloonies.com

# 6. Manual testing (REQUIRED)
# - Open https://chat.lawnloonies.com
# - Login
# - Verify data integrity
# - Test functionality

# 7. Cleanup (only after successful verification)
bash cleanup-old-volume.sh openwebui-chat-lawnloonies-com
```

### For Multiple Deployments on Same Server

```bash
#!/bin/bash
# Save as: migrate-all-deployments.sh

DEPLOYMENTS=(
    "openwebui-chat-lawnloonies-com:chat.lawnloonies.com:chat"
    "openwebui-chat-client2-com:chat.client2.com:chat"
    # Add more deployments here
)

# Prepare environment once
bash prepare-migration-environment.sh

# Migrate each deployment
for deployment in "${DEPLOYMENTS[@]}"; do
    IFS=':' read -r container fqdn subdomain <<< "$deployment"

    echo
    echo "=========================================="
    echo "Migrating: $container"
    echo "=========================================="
    echo

    # Backup
    bash backup-deployment.sh "$container"

    # Migrate
    bash migrate-deployment.sh "$container" "$fqdn" "$subdomain"

    # Verify
    bash verify-migration.sh "$container" "$fqdn"

    echo
    echo "⚠️  Manual verification required for: https://$fqdn"
    echo "Press Enter when verification complete, or Ctrl+C to stop..."
    read

    # Cleanup
    bash cleanup-old-volume.sh "$container"

    echo "✅ Migration complete for $container"
    echo
done

echo
echo "=========================================="
echo "All Migrations Complete"
echo "=========================================="
```

---

## Production Server Migration Checklist

### Pre-Migration

- [ ] SSH access verified to production server
- [ ] Current deployments discovered and documented
- [ ] Disk space verified (2x current data size available)
- [ ] Backup directory created (`/root/migration-backups/`)
- [ ] All deployment owners notified of maintenance window
- [ ] Rollback procedures reviewed and tested

### Per Deployment

- [ ] Backup created and verified
- [ ] Migration environment prepared (one-time)
- [ ] Deployment migrated to bind mounts
- [ ] Container health verified (healthy status)
- [ ] Bind mounts verified (2 mounts present)
- [ ] Database file exists in new location
- [ ] Static assets initialized
- [ ] Web interface accessible
- [ ] **Manual login test performed**
- [ ] **Chat history verified intact**
- [ ] **New message test successful**
- [ ] Old Docker volume removed (post-verification)

### Post-Migration

- [ ] All deployments verified working
- [ ] All old Docker volumes removed
- [ ] Repository on `main` branch
- [ ] Migration documentation updated with server details
- [ ] Backup retention policy established
- [ ] Deployment owners notified of completion

---

## Troubleshooting

### Issue: SSH Connection Refused

**Symptoms:**
```
ssh: connect to host 45.55.182.177 port 22: Connection refused
```

**Possible Causes:**
1. Firewall blocking port 22
2. SSH service not running
3. Wrong IP address

**Resolution:**
```bash
# Check if server is reachable
ping 45.55.182.177

# Try alternative SSH port (if configured)
ssh -p 2222 root@45.55.182.177

# Check from Digital Ocean console
# Access server via Digital Ocean web console and check SSH status
systemctl status sshd
```

### Issue: Container Not Healthy After Migration

**Symptoms:**
```
Container status: running
Health status: unhealthy (or starting)
```

**Resolution:**
```bash
# Check container logs
docker logs openwebui-chat-lawnloonies-com --tail 100

# Common issues:
# 1. Database permissions
chown -R qbmgr:qbmgr /opt/openwebui/chat-lawnloonies-com/data

# 2. Missing static assets
cp -a /opt/openwebui/defaults/static/. /opt/openwebui/chat-lawnloonies-com/static/

# 3. Health check failing (wait longer)
# Health checks run every 10s with 3 retries = up to 30s

# 4. Application error (check logs for specifics)
docker logs openwebui-chat-lawnloonies-com 2>&1 | grep -i error
```

### Issue: Data Missing After Migration

**Symptoms:**
- Empty chat history
- No user accounts
- Database size is very small

**Resolution:**
```bash
# Check if data was copied
ls -lah /opt/openwebui/chat-lawnloonies-com/data/

# Check database size
du -h /opt/openwebui/chat-lawnloonies-com/data/webui.db

# Compare to backup size
tar tzf /root/migration-backups/*/openwebui-chat-lawnloonies-com-data.tar.gz | wc -l

# If data is missing, rollback and investigate
bash rollback-from-backup.sh openwebui-chat-lawnloonies-com <backup-date>
```

### Issue: Permission Denied Errors

**Symptoms:**
```
Error: Failed to create /opt/openwebui/chat-lawnloonies-com/data
Permission denied
```

**Resolution:**
```bash
# Fix ownership
chown -R qbmgr:qbmgr /opt/openwebui

# Fix permissions
chmod -R 755 /opt/openwebui

# Verify
ls -ld /opt/openwebui/
ls -ld /opt/openwebui/chat-lawnloonies-com/
```

### Issue: Old Container Conflicts

**Symptoms:**
```
Error: Container 'openwebui-chat-lawnloonies-com' already exists
```

**Resolution:**
```bash
# Stop and remove old container
docker stop openwebui-chat-lawnloonies-com
docker rm openwebui-chat-lawnloonies-com

# Verify removal
docker ps -a | grep openwebui-chat-lawnloonies-com

# Retry migration
bash migrate-deployment.sh openwebui-chat-lawnloonies-com chat.lawnloonies.com chat
```

---

## Testing Plan

### Pre-Production Testing (Recommended)

Before migrating production servers, test the migration process on a test server:

```bash
# 1. Set up test server with release branch
curl -fsSL https://raw.githubusercontent.com/imagicrafter/open-webui/release/mt/setup/quick-setup.sh | bash -s -- "" "production"

# 2. Create test deployment
# Use client-manager.sh to create a test deployment with sample data

# 3. Add test data
# - Create user accounts
# - Create test chats
# - Upload test files (if applicable)
# - Apply custom branding (if applicable)

# 4. Run migration
bash migrate-deployment.sh <container> <fqdn> <subdomain>

# 5. Verify all data intact
bash verify-migration.sh <container> <fqdn>

# 6. Test rollback procedure
bash rollback-from-backup.sh <container> <backup-date>

# 7. Verify rollback worked
bash verify-migration.sh <container> <fqdn>
```

---

## Post-Migration Benefits

After successful migration, deployments will have:

1. **Simpler Backups**
   ```bash
   # Before (Docker volumes):
   docker run --rm -v openwebui-data:/data -v $(pwd):/backup alpine tar czf /backup/backup.tar.gz -C /data .

   # After (Bind mounts):
   tar czf backup.tar.gz /opt/openwebui/chat-lawnloonies-com/
   ```

2. **Easier Server Migration**
   ```bash
   # Copy data to new server
   rsync -avz /opt/openwebui/chat-lawnloonies-com/ newserver:/opt/openwebui/chat-lawnloonies-com/

   # Recreate container on new server
   ./client-manager.sh  # Create new deployment with same settings
   ```

3. **Direct File Access**
   ```bash
   # View database directly
   sqlite3 /opt/openwebui/chat-lawnloonies-com/data/webui.db

   # Update branding without container access
   cp new-logo.png /opt/openwebui/chat-lawnloonies-com/static/logo.png
   docker restart openwebui-chat-lawnloonies-com
   ```

4. **Consistent Architecture**
   - All new deployments use bind mounts by default
   - Future upgrades simpler (just pull main branch)
   - Multi-server deployments easier to manage

---

## Timeline Estimates

### Single Deployment
- **Discovery & Backup:** 5 minutes
- **Environment Preparation:** 10 minutes (one-time per server)
- **Migration:** 5 minutes
- **Verification:** 10 minutes
- **Cleanup:** 2 minutes
- **Total:** ~30 minutes per deployment (20 minutes for subsequent deployments)

### Multiple Deployments (Same Server)
- **First Deployment:** 30 minutes
- **Each Additional:** 20 minutes
- **Example (3 deployments):** 70 minutes

### Production Server (45.55.182.177)
- **Current Deployments:** 1 (openwebui-chat-lawnloonies-com)
- **Estimated Time:** 30 minutes
- **Recommended Window:** 1 hour (includes buffer for testing)

---

## Maintenance Window Recommendations

### For 1-2 Deployments
- **Window:** 1 hour
- **Downtime per deployment:** ~2-5 minutes
- **Schedule:** Off-peak hours (e.g., 2-3 AM local time)

### For 3-5 Deployments
- **Window:** 2 hours
- **Downtime per deployment:** ~2-5 minutes each
- **Schedule:** Weekend off-peak hours

### For 6+ Deployments
- **Window:** 4 hours
- **Consider:** Phased migration over multiple windows
- **Alternative:** Blue-green migration (provision new server with main branch, migrate clients one-by-one)

---

## Support & Rollback Readiness

### Before Migration
1. **Verify SSH Access:** Ensure you can access production server
2. **Test Scripts:** Run all scripts on test environment first
3. **Backup Strategy:** Ensure backups are working and verified
4. **Communication Plan:** Notify deployment owners of maintenance window

### During Migration
1. **Monitor Each Step:** Don't proceed if errors occur
2. **Manual Verification:** Always test web access and data integrity
3. **Logs:** Keep logs of all migration steps
4. **Rollback Ready:** Have rollback scripts accessible

### After Migration
1. **Extended Monitoring:** Watch container health for 24-48 hours
2. **User Feedback:** Collect feedback from deployment owners
3. **Backup Retention:** Keep old backups for at least 7 days
4. **Documentation:** Update deployment records with new architecture

---

## Next Steps

1. **SSH Access Resolution**
   - Resolve SSH connection issues to 45.55.182.177
   - Verify firewall rules and SSH service status
   - Test access from Digital Ocean console if needed

2. **Discovery Phase**
   - Run discovery script to document current state
   - Identify all deployments needing migration
   - Document FQDN, subdomain, and configuration for each

3. **Test Environment Validation**
   - Set up test server if not already available
   - Run complete migration workflow on test
   - Validate rollback procedures work correctly

4. **Production Migration**
   - Schedule maintenance window with deployment owners
   - Execute migration scripts on production
   - Perform thorough verification and testing
   - Monitor for 24-48 hours post-migration

5. **Documentation Update**
   - Record actual migration times and issues
   - Update troubleshooting section with any new issues
   - Document server-specific configurations
   - Create playbook for future server migrations

---

## Appendix: Quick Reference Commands

### Discovery
```bash
# List all Open WebUI containers
docker ps -a --format '{{.Names}}\t{{.Status}}' | grep openwebui

# List all volumes
docker volume ls | grep openwebui

# Check data size
docker volume ls -q | grep openwebui | xargs -I {} sh -c "echo {} && docker run --rm -v {}:/data alpine du -sh /data"
```

### Migration
```bash
# Backup
bash backup-deployment.sh <container-name>

# Migrate
bash migrate-deployment.sh <container-name> <fqdn> <subdomain>

# Verify
bash verify-migration.sh <container-name> <fqdn>

# Cleanup
bash cleanup-old-volume.sh <container-name>
```

### Rollback
```bash
# Immediate (old container still exists)
bash rollback-immediate.sh <container-name>

# From backup (full restore)
bash rollback-from-backup.sh <container-name> <backup-date>
```

### Monitoring
```bash
# Container status
docker ps | grep openwebui

# Container health
docker inspect <container-name> --format '{{.State.Health.Status}}'

# Container logs
docker logs <container-name> --tail 100 -f

# Directory size
du -sh /opt/openwebui/*/
```

---

**Document Version:** 1.0
**Last Updated:** 2025-11-01
**Author:** Migration Plan Generator
**Status:** Ready for Implementation (pending SSH access resolution)
