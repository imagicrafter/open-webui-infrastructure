#!/bin/bash
# Rollback Deployment to Docker Volumes
# Usage: bash 9-rollback-deployment.sh <container-name>

CONTAINER_NAME=$1
VOLUME_NAME="${CONTAINER_NAME}-data"
CLIENT_ID="${CONTAINER_NAME#openwebui-}"
CLIENT_DIR="/opt/openwebui/${CLIENT_ID}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$CONTAINER_NAME" ]; then
    echo "Usage: $0 <container-name>"
    echo
    echo "Available containers:"
    docker ps -a --format '{{.Names}}' | grep openwebui
    exit 1
fi

echo -e "${BLUE}=== Rollback Deployment ===${NC}"
echo "Container: $CONTAINER_NAME"
echo "Volume: $VOLUME_NAME"
echo

# Check if old volume still exists
if ! docker volume ls -q | grep -q "^${VOLUME_NAME}$"; then
    echo -e "${RED}❌ ERROR: Old volume not found: $VOLUME_NAME${NC}"
    echo "   Volume may have been deleted."
    echo "   To restore from backup, use: bash 9-rollback-from-backup.sh"
    exit 1
fi

VOL_SIZE=$(docker run --rm -v "$VOLUME_NAME":/data alpine du -sh /data 2>/dev/null | awk '{print $1}')
echo -e "${GREEN}✅ Old volume found: $VOLUME_NAME ($VOL_SIZE)${NC}"
echo

# Confirmation
echo -e "${YELLOW}This will:${NC}"
echo "1. Stop and remove current container (with bind mounts)"
echo "2. Recreate container using old Docker volume"
echo "3. Optionally remove bind mount directories"
echo
read -p "Continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi
echo

# Step 1: Get environment variables before removing container
echo "Step 1: Extracting configuration..."
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    OLD_ENV=$(docker inspect "$CONTAINER_NAME" --format '{{range .Config.Env}}{{println}}{{end}}')

    # Extract variables
    OAUTH_DOMAINS=$(echo "$OLD_ENV" | grep "^OAUTH_ALLOWED_DOMAINS=" | cut -d= -f2-)
    WEBUI_SECRET_KEY=$(echo "$OLD_ENV" | grep "^WEBUI_SECRET_KEY=" | cut -d= -f2-)
    GOOGLE_CLIENT_ID=$(echo "$OLD_ENV" | grep "^GOOGLE_CLIENT_ID=" | cut -d= -f2-)
    GOOGLE_CLIENT_SECRET=$(echo "$OLD_ENV" | grep "^GOOGLE_CLIENT_SECRET=" | cut -d= -f2-)
    REDIRECT_URI=$(echo "$OLD_ENV" | grep "^GOOGLE_REDIRECT_URI=" | cut -d= -f2-)
    FQDN=$(echo "$OLD_ENV" | grep "^FQDN=" | cut -d= -f2-)

    # Get port if not using nginx network
    PORT=$(docker inspect "$CONTAINER_NAME" --format '{{range $p, $conf := .NetworkSettings.Ports}}{{if eq $p "8080/tcp"}}{{(index $conf 0).HostPort}}{{end}}{{end}}' 2>/dev/null)

    echo -e "${GREEN}✅ Configuration extracted${NC}"
else
    echo -e "${RED}❌ ERROR: Container not found${NC}"
    exit 1
fi

# Default values if not found
OAUTH_DOMAINS="${OAUTH_DOMAINS:-martins.net}"
WEBUI_SECRET_KEY="${WEBUI_SECRET_KEY:-$(openssl rand -base64 32)}"
GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-1063776054060-2fa0vn14b7ahi1tmfk49cuio44goosc1.apps.googleusercontent.com}"
GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET:-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}"
PORT="${PORT:-8081}"

# Step 2: Stop and remove current container
echo "Step 2: Removing current container..."
docker stop "$CONTAINER_NAME" 2>/dev/null
docker rm "$CONTAINER_NAME" 2>/dev/null
echo -e "${GREEN}✅ Container removed${NC}"

# Step 3: Determine network configuration
echo "Step 3: Determining network configuration..."
NETWORK_CONFIG=""
PORT_CONFIG=""

if docker ps --filter "name=openwebui-nginx" --format "{{.Names}}" | grep -q "^openwebui-nginx$"; then
    NETWORK_CONFIG="--network openwebui-network"
    echo "  Using containerized nginx (no port mapping)"
else
    PORT_CONFIG="-p ${PORT}:8080"
    echo "  Using port: $PORT"
fi

# Step 4: Recreate container with Docker volume (old architecture)
echo "Step 4: Recreating container with Docker volume..."

docker run -d \
    --name "$CONTAINER_NAME" \
    $PORT_CONFIG \
    $NETWORK_CONFIG \
    -e GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
    -e GOOGLE_CLIENT_SECRET="$GOOGLE_CLIENT_SECRET" \
    -e GOOGLE_REDIRECT_URI="$REDIRECT_URI" \
    -e ENABLE_OAUTH_SIGNUP=true \
    -e OAUTH_ALLOWED_DOMAINS="$OAUTH_DOMAINS" \
    -e OPENID_PROVIDER_URL="https://accounts.google.com/.well-known/openid-configuration" \
    -e WEBUI_SECRET_KEY="$WEBUI_SECRET_KEY" \
    -e WEBUI_URL="$REDIRECT_URI" \
    -e FQDN="$FQDN" \
    -e ENABLE_VERSION_UPDATE_CHECK=false \
    -v "$VOLUME_NAME":/app/backend/data \
    --restart unless-stopped \
    ghcr.io/imagicrafter/open-webui:release

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ ERROR: Failed to recreate container${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Container recreated${NC}"

# Step 5: Wait for health
echo "Step 5: Waiting for container to become healthy..."
for i in {1..30}; do
    if docker ps --format '{{.Names}}\t{{.Status}}' | grep "$CONTAINER_NAME" | grep -q "healthy"; then
        echo -e "${GREEN}✅ Container healthy${NC}"
        break
    fi
    echo -n "."
    sleep 2
done
echo

# Step 6: Verify rollback
echo "Step 6: Verifying rollback..."
STATUS=$(docker inspect "$CONTAINER_NAME" --format '{{.State.Status}}')
MOUNT_TYPE=$(docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{.Type}} {{end}}')

echo "  Status: $STATUS"
echo "  Mount type: $MOUNT_TYPE"

if echo "$MOUNT_TYPE" | grep -q "volume"; then
    echo -e "${GREEN}✅ Container using Docker volume (rollback successful)${NC}"
else
    echo -e "${YELLOW}⚠️  Warning: Container may not be using volume correctly${NC}"
fi

echo
echo -e "${GREEN}=== Rollback Complete ===${NC}"
echo "Container: $CONTAINER_NAME"
echo "Architecture: Docker volumes (release branch)"
echo "Status: $STATUS"
echo "Access: $REDIRECT_URI"
echo

# Ask about bind mount cleanup
echo "Bind mount directories still exist at: $CLIENT_DIR"
read -p "Remove bind mount directories? (y/N): " cleanup_dirs
if [[ "$cleanup_dirs" =~ ^[Yy]$ ]]; then
    sudo rm -rf "$CLIENT_DIR"
    echo -e "${GREEN}✅ Bind mount directories removed${NC}"
else
    echo "Bind mount directories preserved (can be removed manually later)"
fi

echo
echo "Rollback complete. Test the deployment to ensure it's working correctly."
