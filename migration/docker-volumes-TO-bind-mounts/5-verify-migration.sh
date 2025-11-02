#!/bin/bash
# Verify Migration Success
# Usage: bash 5-verify-migration.sh <container-name> <fqdn>

CONTAINER_NAME=$1
FQDN=$2
CLIENT_ID="${CONTAINER_NAME#openwebui-}"
CLIENT_DIR="/opt/openwebui/${CLIENT_ID}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ $# -lt 2 ]; then
    echo "Usage: $0 <container-name> <fqdn>"
    echo
    echo "Example:"
    echo "  $0 openwebui-chat-lawnloonies-com chat.lawnloonies.com"
    exit 1
fi

echo -e "${BLUE}=== Migration Verification ===${NC}"
echo "Container: $CONTAINER_NAME"
echo "FQDN: $FQDN"
echo

ISSUES_FOUND=0

# 1. Container status
echo "1. Container Status:"
STATUS=$(docker inspect "$CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null)
HEALTH=$(docker inspect "$CONTAINER_NAME" --format '{{.State.Health.Status}}' 2>/dev/null)
echo "   Status: $STATUS"
echo "   Health: $HEALTH"

if [ "$STATUS" != "running" ]; then
    echo -e "   ${RED}❌ Container not running!${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
elif [ "$HEALTH" != "healthy" ]; then
    echo -e "   ${YELLOW}⚠️  Container not healthy${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    echo -e "   ${GREEN}✅ Container running and healthy${NC}"
fi

# 2. Mount verification
echo
echo "2. Mount Configuration:"
docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}  {{.Type}}: {{.Source}} -> {{.Destination}}{{println}}{{end}}'

BIND_COUNT=$(docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{.Type}}{{println}}{{end}}' | grep -c "^bind$")
if [ "$BIND_COUNT" -ge 2 ]; then
    echo -e "   ${GREEN}✅ Bind mounts configured ($BIND_COUNT found)${NC}"
else
    echo -e "   ${RED}❌ Expected 2 bind mounts, found $BIND_COUNT${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# 3. Environment variables
echo
echo "3. Environment Variables:"
CLIENT_ID_ENV=$(docker inspect "$CONTAINER_NAME" --format '{{range .Config.Env}}{{println}}{{end}}' | grep "^CLIENT_ID=" | cut -d= -f2)
FQDN_ENV=$(docker inspect "$CONTAINER_NAME" --format '{{range .Config.Env}}{{println}}{{end}}' | grep "^FQDN=" | cut -d= -f2)
SUBDOMAIN_ENV=$(docker inspect "$CONTAINER_NAME" --format '{{range .Config.Env}}{{println}}{{end}}' | grep "^SUBDOMAIN=" | cut -d= -f2)

echo "   CLIENT_ID: $CLIENT_ID_ENV"
echo "   FQDN: $FQDN_ENV"
echo "   SUBDOMAIN: $SUBDOMAIN_ENV"

if [ "$CLIENT_ID_ENV" = "$CLIENT_ID" ] && [ "$FQDN_ENV" = "$FQDN" ]; then
    echo -e "   ${GREEN}✅ Environment variables correct${NC}"
else
    echo -e "   ${YELLOW}⚠️  Warning: Environment variables may not match${NC}"
fi

# 4. Data integrity
echo
echo "4. Data Integrity:"
if [ -f "$CLIENT_DIR/data/webui.db" ]; then
    DB_SIZE=$(du -h "$CLIENT_DIR/data/webui.db" | awk '{print $1}')
    DATA_SIZE=$(du -sh "$CLIENT_DIR/data" | awk '{print $1}')
    DATA_FILES=$(find "$CLIENT_DIR/data" -type f | wc -l)
    echo "   Database: $DB_SIZE"
    echo "   Total Data: $DATA_SIZE ($DATA_FILES files)"
    echo -e "   ${GREEN}✅ Database file exists${NC}"
else
    echo -e "   ${RED}❌ Database file missing!${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# 5. Static assets
echo
echo "5. Static Assets:"
STATIC_COUNT=$(find "$CLIENT_DIR/static" -type f 2>/dev/null | wc -l)
STATIC_SIZE=$(du -sh "$CLIENT_DIR/static" 2>/dev/null | awk '{print $1}')
echo "   Files: $STATIC_COUNT"
echo "   Size: $STATIC_SIZE"

if [ "$STATIC_COUNT" -gt 10 ]; then
    echo -e "   ${GREEN}✅ Static assets present${NC}"
    echo "   Sample files:"
    find "$CLIENT_DIR/static" -type f | head -3 | sed 's/^/     /'
else
    echo -e "   ${YELLOW}⚠️  Warning: Low static file count${NC}"
fi

# 6. HTTP connectivity test
echo
echo "6. HTTP Connectivity:"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -k "https://$FQDN" --max-time 10 2>/dev/null)
echo "   Status: $HTTP_STATUS"

if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "302" ]; then
    echo -e "   ${GREEN}✅ Web interface accessible${NC}"
elif [ -z "$HTTP_STATUS" ]; then
    echo -e "   ${YELLOW}⚠️  Could not reach server (may need nginx config)${NC}"
else
    echo -e "   ${YELLOW}⚠️  HTTP status $HTTP_STATUS${NC}"
fi

# 7. Directory ownership
echo
echo "7. Permissions:"
OWNER=$(stat -c "%U:%G" "$CLIENT_DIR" 2>/dev/null || stat -f "%Su:%Sg" "$CLIENT_DIR" 2>/dev/null)
echo "   Owner: $OWNER"

if [ "$OWNER" = "qbmgr:qbmgr" ]; then
    echo -e "   ${GREEN}✅ Correct ownership${NC}"
else
    echo -e "   ${YELLOW}⚠️  Warning: Expected qbmgr:qbmgr, got $OWNER${NC}"
fi

# 8. Old volume check
echo
echo "8. Old Volume Status:"
VOLUME_NAME="${CONTAINER_NAME}-data"
if docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
    VOL_SIZE=$(docker run --rm -v "$VOLUME_NAME":/data alpine du -sh /data 2>/dev/null | awk '{print $1}')
    echo -e "   ${YELLOW}⚠️  Old volume still exists: $VOLUME_NAME ($VOL_SIZE)${NC}"
    echo "   After confirming migration success, run:"
    echo "   bash 6-cleanup-old-volume.sh $CONTAINER_NAME"
else
    echo -e "   ${GREEN}✅ Old volume already removed${NC}"
fi

echo
echo -e "${BLUE}=== Verification Summary ===${NC}"

if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed!${NC}"
    echo
    echo "Migration appears successful. Please perform manual tests:"
else
    echo -e "${RED}❌ Found $ISSUES_FOUND issue(s)${NC}"
    echo
    echo "Review issues above before proceeding."
    echo
fi

echo -e "${BLUE}Manual Tests Required:${NC}"
echo "1. Open https://$FQDN in browser"
echo "2. Login with existing account"
echo "3. Verify chat history is intact"
echo "4. Test sending a new message"
echo "5. Check custom branding (if any)"
echo
echo "After successful manual verification:"
echo "  Run: bash 6-cleanup-old-volume.sh $CONTAINER_NAME"
echo
echo "If issues found:"
echo "  Run: bash 9-rollback-deployment.sh $CONTAINER_NAME"
