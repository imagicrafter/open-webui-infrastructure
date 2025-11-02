#!/bin/bash
# Prepare Migration Environment (One-time per server)
# Usage: bash 3-prepare-environment.sh

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Preparing Migration Environment ===${NC}"
echo

# Check if already on main branch
CURRENT_BRANCH=$(cd ~/open-webui && git branch --show-current)
if [ "$CURRENT_BRANCH" = "main" ]; then
    echo -e "${YELLOW}⚠️  Already on main branch${NC}"
    read -p "Continue anyway? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

# 1. Update repository to main branch
echo "1. Updating repository to main branch..."
cd ~/open-webui
git fetch origin
git checkout main
git pull origin main

if [ $? -eq 0 ]; then
    NEW_BRANCH=$(git branch --show-current)
    echo -e "${GREEN}✅ Repository updated (branch: $NEW_BRANCH)${NC}"
else
    echo -e "${RED}❌ ERROR: Failed to update repository${NC}"
    exit 1
fi

# 2. Create /opt/openwebui structure
echo "2. Creating directory structure..."
sudo mkdir -p /opt/openwebui/defaults/static

if [ -d "/opt/openwebui/defaults/static" ]; then
    echo -e "${GREEN}✅ Directories created${NC}"
else
    echo -e "${RED}❌ ERROR: Failed to create directories${NC}"
    exit 1
fi

# 3. Set ownership
echo "3. Setting ownership..."
sudo chown -R qbmgr:qbmgr /opt/openwebui
echo -e "${GREEN}✅ Ownership set${NC}"

# 4. Extract default static assets
echo "4. Extracting default static assets..."

# Check if extraction script exists
if [ -f ~/open-webui/mt/setup/lib/extract-default-static.sh ]; then
    bash ~/open-webui/mt/setup/lib/extract-default-static.sh
else
    echo -e "${YELLOW}⚠️  Extraction script not found, using manual method...${NC}"

    # Manual extraction
    IMAGE_TAG="main"
    docker pull ghcr.io/imagicrafter/open-webui:${IMAGE_TAG}
    docker run --rm \
        -v /opt/openwebui/defaults/static:/target \
        ghcr.io/imagicrafter/open-webui:${IMAGE_TAG} \
        sh -c "cp -r /app/backend/open_webui/static/* /target/" 2>/dev/null || true
fi

# 5. Verify default assets
echo "5. Verifying default assets..."
ASSET_COUNT=$(find /opt/openwebui/defaults/static -type f 2>/dev/null | wc -l)

if [ "$ASSET_COUNT" -gt 10 ]; then
    echo -e "${GREEN}✅ Default assets extracted: $ASSET_COUNT files${NC}"
    echo "   Sample files:"
    find /opt/openwebui/defaults/static -type f | head -5 | sed 's/^/     /'
else
    echo -e "${YELLOW}⚠️  Warning: Only $ASSET_COUNT files found${NC}"
    echo "   Migration can continue, but static assets may not work correctly"
fi

# 6. Set permissions
echo "6. Setting permissions..."
sudo chown -R qbmgr:qbmgr /opt/openwebui
sudo chmod -R 755 /opt/openwebui
echo -e "${GREEN}✅ Permissions set${NC}"

# 7. Verify directory structure
echo "7. Verifying directory structure..."
echo "   /opt/openwebui:"
ls -la /opt/openwebui/ | sed 's/^/     /'

echo
echo -e "${GREEN}=== Migration Environment Ready ===${NC}"
echo "Repository: $(cd ~/open-webui && git branch --show-current) branch"
echo "Directory: /opt/openwebui/"
echo "Default assets: $ASSET_COUNT files"
echo
echo "Next steps:"
echo "1. Review directory structure above"
echo "2. Run: bash 4-migrate-deployment.sh <container-name> <fqdn> <subdomain>"
echo
echo "Example:"
echo "  bash 4-migrate-deployment.sh openwebui-chat-lawnloonies-com chat.lawnloonies.com chat"
