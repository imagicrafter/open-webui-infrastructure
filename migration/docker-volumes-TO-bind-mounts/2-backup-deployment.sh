#!/bin/bash
# Backup Deployment Script
# Usage: bash 2-backup-deployment.sh <container-name>

CONTAINER_NAME=$1
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/root/migration-backups/${BACKUP_DATE}"

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

# Check if container exists
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${RED}❌ ERROR: Container '$CONTAINER_NAME' not found${NC}"
    exit 1
fi

echo -e "${BLUE}=== Backing up: $CONTAINER_NAME ===${NC}"
echo "Backup location: $BACKUP_DIR"
echo

# Create backup directory
sudo mkdir -p "$BACKUP_DIR"

# 1. Export container configuration
echo "1. Exporting container config..."
docker inspect "$CONTAINER_NAME" | sudo tee "$BACKUP_DIR/${CONTAINER_NAME}_config.json" >/dev/null
echo -e "${GREEN}✅ Config exported${NC}"

# 2. Export environment variables
echo "2. Exporting environment variables..."
docker inspect "$CONTAINER_NAME" --format '{{range .Config.Env}}{{println}}{{end}}' | sudo tee "$BACKUP_DIR/${CONTAINER_NAME}_env.txt" >/dev/null
echo -e "${GREEN}✅ Environment exported${NC}"

# 3. Backup data volume
echo "3. Backing up data volume (this may take a few minutes)..."
VOLUME_NAME="${CONTAINER_NAME}-data"

if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
    echo -e "${RED}❌ ERROR: Volume '$VOLUME_NAME' not found${NC}"
    exit 1
fi

docker run --rm \
    -v "$VOLUME_NAME":/source:ro \
    -v "$BACKUP_DIR":/backup \
    alpine tar czf "/backup/${VOLUME_NAME}.tar.gz" -C /source .

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ ERROR: Volume backup failed${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Volume backed up${NC}"

# 4. Verify backup
echo "4. Verifying backup..."
if sudo test -f "$BACKUP_DIR/${VOLUME_NAME}.tar.gz"; then
    SIZE=$(sudo du -h "$BACKUP_DIR/${VOLUME_NAME}.tar.gz" | awk '{print $1}')
    echo -e "${GREEN}✅ Backup created: ${VOLUME_NAME}.tar.gz ($SIZE)${NC}"
else
    echo -e "${RED}❌ ERROR: Backup file not found${NC}"
    exit 1
fi

# 5. Test backup integrity
echo "5. Testing backup integrity..."
if sudo tar tzf "$BACKUP_DIR/${VOLUME_NAME}.tar.gz" >/dev/null 2>&1; then
    FILE_COUNT=$(sudo tar tzf "$BACKUP_DIR/${VOLUME_NAME}.tar.gz" | wc -l)
    echo -e "${GREEN}✅ Backup integrity verified ($FILE_COUNT files)${NC}"
else
    echo -e "${RED}❌ ERROR: Backup corrupted${NC}"
    exit 1
fi

# 6. Save metadata
echo "6. Saving metadata..."
sudo tee "$BACKUP_DIR/${CONTAINER_NAME}_metadata.txt" >/dev/null <<EOF
Container: $CONTAINER_NAME
Volume: $VOLUME_NAME
Backup Date: $BACKUP_DATE
Backup Location: $BACKUP_DIR
Server: $(hostname)
Server IP: $(hostname -I | awk '{print $1}')
Backup Size: $SIZE
File Count: $FILE_COUNT
EOF
echo -e "${GREEN}✅ Metadata saved${NC}"

echo
echo -e "${GREEN}=== Backup Complete ===${NC}"
echo "Location: $BACKUP_DIR"
echo "Files created:"
sudo ls -lh "$BACKUP_DIR" | grep "$CONTAINER_NAME"
echo
echo "Next steps:"
echo "1. Verify backup contents: tar tzf $BACKUP_DIR/${VOLUME_NAME}.tar.gz | head -20"
echo "2. Proceed with: bash 3-prepare-environment.sh"
