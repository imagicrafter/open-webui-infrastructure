#!/bin/bash
# Cleanup Old Docker Volume (Post-Migration)
# Usage: bash 6-cleanup-old-volume.sh <container-name>
# WARNING: Only run after successful migration verification!

CONTAINER_NAME=$1
VOLUME_NAME="${CONTAINER_NAME}-data"

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
    docker ps --format '{{.Names}}' | grep openwebui
    exit 1
fi

echo -e "${BLUE}=== Cleanup Old Volume ===${NC}"
echo "Volume: $VOLUME_NAME"
echo

# Safety check: Container must be running with bind mounts
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${RED}❌ ERROR: Container $CONTAINER_NAME is not running!${NC}"
    echo "   Cannot safely delete volume."
    exit 1
fi

# Verify bind mounts are in use
BIND_COUNT=$(docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{.Type}}{{println}}{{end}}' | grep -c "^bind$")
if [ "$BIND_COUNT" -lt 2 ]; then
    echo -e "${RED}❌ ERROR: Container not using bind mounts!${NC}"
    echo "   Migration may not be complete. Found $BIND_COUNT bind mount(s)."
    exit 1
fi

# Check if volume exists
if ! docker volume ls -q | grep -q "^${VOLUME_NAME}$"; then
    echo -e "${GREEN}Volume $VOLUME_NAME does not exist (already deleted)${NC}"
    exit 0
fi

# Show volume size
VOL_SIZE=$(docker run --rm -v "$VOLUME_NAME":/data alpine du -sh /data 2>/dev/null | awk '{print $1}')
echo "Volume size: $VOL_SIZE"
echo

# Final confirmation
echo -e "${YELLOW}⚠️  WARNING: This will permanently delete the Docker volume: $VOLUME_NAME${NC}"
echo "   Make sure you have:"
echo "   1. Verified the migration is successful (bash 5-verify-migration.sh)"
echo "   2. Tested the deployment manually"
echo "   3. Confirmed all data is intact"
echo
read -p "Are you sure? Type 'DELETE' to confirm: " confirm

if [ "$confirm" != "DELETE" ]; then
    echo "Cancelled."
    exit 0
fi

# Remove volume
echo
echo "Removing volume..."
docker volume rm "$VOLUME_NAME"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Volume removed: $VOLUME_NAME${NC}"
    echo
    echo "Remaining volumes:"
    docker volume ls | grep openwebui || echo "  (none)"
else
    echo -e "${RED}❌ Failed to remove volume${NC}"
    echo "   Volume may still be in use"
    exit 1
fi

echo
echo -e "${GREEN}=== Cleanup Complete ===${NC}"
echo "Old volume removed. Container now uses bind mounts exclusively."
