#!/bin/bash
# Migrate Individual Deployment to Bind Mounts
# Usage: bash 4-migrate-deployment.sh <container-name> <fqdn> <subdomain>

CONTAINER_NAME=$1
FQDN=$2
SUBDOMAIN=$3
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ $# -lt 3 ]; then
    echo "Usage: $0 <container-name> <fqdn> <subdomain>"
    echo
    echo "Example:"
    echo "  $0 openwebui-chat-lawnloonies-com chat.lawnloonies.com chat"
    echo
    echo "Available containers:"
    docker ps --format '{{.Names}}' | grep openwebui
    exit 1
fi

# Extract CLIENT_ID from container name
CLIENT_ID="${CONTAINER_NAME#openwebui-}"
CLIENT_DIR="/opt/openwebui/${CLIENT_ID}"
VOLUME_NAME="${CONTAINER_NAME}-data"

echo -e "${BLUE}=== Migrating Deployment ===${NC}"
echo "Container: $CONTAINER_NAME"
echo "CLIENT_ID: $CLIENT_ID"
echo "FQDN: $FQDN"
echo "Subdomain: $SUBDOMAIN"
echo "Target Directory: $CLIENT_DIR"
echo

# Safety check: Verify backup exists
LATEST_BACKUP=$(sudo find /root/migration-backups -name "${VOLUME_NAME}.tar.gz" -type f 2>/dev/null | head -1)
if [ -z "$LATEST_BACKUP" ]; then
    echo -e "${RED}❌ ERROR: No backup found for $VOLUME_NAME${NC}"
    echo "   Run: bash 2-backup-deployment.sh $CONTAINER_NAME"
    exit 1
fi
echo -e "${GREEN}✅ Backup verified: $LATEST_BACKUP${NC}"
echo

# Confirmation prompt
echo -e "${YELLOW}⚠️  WARNING: This will stop and recreate the container${NC}"
echo "   Estimated downtime: 2-5 minutes"
echo
read -p "Continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi
echo

# Step 1: Stop existing container
echo "Step 1: Stopping container..."
docker stop "$CONTAINER_NAME"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Container stopped${NC}"
else
    echo -e "${RED}❌ ERROR: Failed to stop container${NC}"
    exit 1
fi

# Step 2: Create new directory structure
echo "Step 2: Creating directory structure..."
sudo mkdir -p "$CLIENT_DIR/data"
sudo mkdir -p "$CLIENT_DIR/static"
sudo chown -R qbmgr:qbmgr "$CLIENT_DIR"

if [ -d "$CLIENT_DIR/data" ] && [ -d "$CLIENT_DIR/static" ]; then
    echo -e "${GREEN}✅ Directories created${NC}"
else
    echo -e "${RED}❌ ERROR: Failed to create directories${NC}"
    echo "   Attempting rollback..."
    docker start "$CONTAINER_NAME"
    exit 1
fi

# Step 3: Migrate data from volume to bind mount
echo "Step 3: Migrating data (this may take a few minutes)..."
docker run --rm \
    -v "$VOLUME_NAME":/source:ro \
    -v "$CLIENT_DIR/data":/target \
    alpine sh -c "cp -a /source/. /target/"

if [ $? -eq 0 ]; then
    DATA_FILES=$(find "$CLIENT_DIR/data" -type f 2>/dev/null | wc -l)
    DATA_SIZE=$(du -sh "$CLIENT_DIR/data" 2>/dev/null | awk '{print $1}')
    echo -e "${GREEN}✅ Data migrated: $DATA_FILES files ($DATA_SIZE)${NC}"
else
    echo -e "${RED}❌ ERROR: Data migration failed${NC}"
    echo "   Attempting rollback..."
    docker start "$CONTAINER_NAME"
    exit 1
fi

# Verify critical files
if [ ! -f "$CLIENT_DIR/data/webui.db" ]; then
    echo -e "${RED}❌ ERROR: Database file missing after migration!${NC}"
    echo "   Attempting rollback..."
    sudo rm -rf "$CLIENT_DIR"
    docker start "$CONTAINER_NAME"
    exit 1
fi

# Step 4: Initialize static assets
echo "Step 4: Initializing static assets..."
if [ -d "/opt/openwebui/defaults/static" ]; then
    cp -a /opt/openwebui/defaults/static/. "$CLIENT_DIR/static/"
    STATIC_COUNT=$(find "$CLIENT_DIR/static" -type f 2>/dev/null | wc -l)
    echo -e "${GREEN}✅ Static assets initialized ($STATIC_COUNT files)${NC}"
else
    echo -e "${YELLOW}⚠️  Warning: Default assets not found, extracting...${NC}"
    docker run --rm \
        -v "$CLIENT_DIR/static":/target \
        ghcr.io/imagicrafter/open-webui:main \
        sh -c "cp -r /app/backend/open_webui/static/* /target/" 2>/dev/null || true
    STATIC_COUNT=$(find "$CLIENT_DIR/static" -type f 2>/dev/null | wc -l)
    echo -e "${GREEN}✅ Static assets extracted ($STATIC_COUNT files)${NC}"
fi

# Step 5: Extract environment variables from old container
echo "Step 5: Extracting environment variables..."
OLD_ENV=$(docker inspect "$CONTAINER_NAME" --format '{{range .Config.Env}}{{println}}{{end}}')

# Extract key variables
OAUTH_DOMAINS=$(echo "$OLD_ENV" | grep "^OAUTH_ALLOWED_DOMAINS=" | cut -d= -f2-)
WEBUI_SECRET_KEY=$(echo "$OLD_ENV" | grep "^WEBUI_SECRET_KEY=" | cut -d= -f2-)
GOOGLE_CLIENT_ID=$(echo "$OLD_ENV" | grep "^GOOGLE_CLIENT_ID=" | cut -d= -f2-)
GOOGLE_CLIENT_SECRET=$(echo "$OLD_ENV" | grep "^GOOGLE_CLIENT_SECRET=" | cut -d= -f2-)

# Default values if not found
OAUTH_DOMAINS="${OAUTH_DOMAINS:-martins.net}"
WEBUI_SECRET_KEY="${WEBUI_SECRET_KEY:-$(openssl rand -base64 32)}"
GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-1063776054060-2fa0vn14b7ahi1tmfk49cuio44goosc1.apps.googleusercontent.com}"
GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET:-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}"

echo "  OAuth Domains: $OAUTH_DOMAINS"
echo "  Secret Key: ${WEBUI_SECRET_KEY:0:10}..."
echo -e "${GREEN}✅ Environment extracted${NC}"

# Step 6: Remove old container (keep volume for now)
echo "Step 6: Removing old container..."
docker rm "$CONTAINER_NAME"
echo -e "${GREEN}✅ Old container removed (volume preserved for rollback)${NC}"

# Step 7: Determine network configuration
echo "Step 7: Determining network configuration..."
PORT="N/A"
if docker ps --filter "name=openwebui-nginx" --format "{{.Names}}" | grep -q "^openwebui-nginx$"; then
    echo "  Using containerized nginx (no port needed)"
else
    # Find next available port (starting from 8081)
    for test_port in {8081..8099}; do
        if ! netstat -tuln 2>/dev/null | grep -q ":${test_port} "; then
            PORT=$test_port
            break
        fi
    done
    echo "  Using port: $PORT"
fi

# Step 8: Launch new container with bind mounts
echo "Step 8: Launching new container..."
cd ~/open-webui/mt

# Use the updated start-template.sh script
bash start-template.sh \
    "$SUBDOMAIN" \
    "$PORT" \
    "$FQDN" \
    "$CONTAINER_NAME" \
    "$FQDN" \
    "$OAUTH_DOMAINS" \
    "$WEBUI_SECRET_KEY"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ ERROR: Failed to start new container${NC}"
    echo "   Check logs for details"
    exit 1
fi

# Wait for container to become healthy
echo "Waiting for container to become healthy..."
for i in {1..30}; do
    HEALTH=$(docker inspect "$CONTAINER_NAME" --format '{{.State.Health.Status}}' 2>/dev/null)
    if [ "$HEALTH" = "healthy" ]; then
        echo -e "${GREEN}✅ Container is healthy${NC}"
        break
    fi
    echo -n "."
    sleep 2
done
echo

if [ "$HEALTH" != "healthy" ]; then
    echo -e "${YELLOW}⚠️  Warning: Container not healthy yet${NC}"
    echo "   Check logs: docker logs $CONTAINER_NAME"
fi

# Step 9: Verify migration
echo "Step 9: Verifying migration..."

# Check mounts
MOUNT_CHECK=$(docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{.Type}}:{{.Destination}}{{println}}{{end}}' | grep -c "^bind:/app/backend")
if [ "$MOUNT_CHECK" -ge 2 ]; then
    echo -e "${GREEN}✅ Bind mounts configured correctly ($MOUNT_CHECK mounts found)${NC}"
else
    echo -e "${YELLOW}⚠️  Warning: Expected 2 bind mounts, found $MOUNT_CHECK${NC}"
fi

# Check data directory
DB_EXISTS=$([ -f "$CLIENT_DIR/data/webui.db" ] && echo "yes" || echo "no")
if [ "$DB_EXISTS" = "yes" ]; then
    DB_SIZE=$(du -h "$CLIENT_DIR/data/webui.db" | awk '{print $1}')
    echo -e "${GREEN}✅ Database file exists ($DB_SIZE)${NC}"
else
    echo -e "${RED}❌ ERROR: Database file missing!${NC}"
fi

# Check static assets
STATIC_COUNT=$(find "$CLIENT_DIR/static" -type f 2>/dev/null | wc -l)
if [ "$STATIC_COUNT" -gt 10 ]; then
    echo -e "${GREEN}✅ Static assets present: $STATIC_COUNT files${NC}"
else
    echo -e "${YELLOW}⚠️  Warning: Only $STATIC_COUNT static files found${NC}"
fi

# Check container status
CONTAINER_STATUS=$(docker inspect "$CONTAINER_NAME" --format '{{.State.Status}}')
echo "Container status: $CONTAINER_STATUS"

echo
echo -e "${GREEN}=== Migration Complete ===${NC}"
echo "Container: $CONTAINER_NAME"
echo "Status: $CONTAINER_STATUS"
echo "Health: $HEALTH"
echo "Data Directory: $CLIENT_DIR/data"
echo "Static Directory: $CLIENT_DIR/static"
echo
echo -e "${BLUE}Next Steps (REQUIRED):${NC}"
echo "1. Test the deployment: https://$FQDN"
echo "2. Verify login and data integrity"
echo "3. Test chat functionality"
echo "4. Check custom branding (if any)"
echo
echo "After successful verification:"
echo "  Run: bash 5-verify-migration.sh $CONTAINER_NAME $FQDN"
echo
echo "If problems occur:"
echo "  Run: bash 9-rollback-deployment.sh $CONTAINER_NAME"
