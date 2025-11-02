#!/bin/bash
# Discovery Script - Document Current State
# Usage: bash 1-discover-deployments.sh

echo "=== Open WebUI Deployment Discovery ==="
echo "Server: $(hostname)"
echo "Date: $(date)"
echo

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# List all containers
echo -e "${BLUE}=== Containers ===${NC}"
docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep -E "NAME|openwebui"
echo

# List Docker volumes
echo -e "${BLUE}=== Docker Volumes ===${NC}"
docker volume ls | grep -E "DRIVER|openwebui"
echo

# Volume details and sizes
echo -e "${BLUE}=== Volume Details ===${NC}"
for container in $(docker ps -a --format '{{.Names}}' | grep openwebui); do
    echo
    echo -e "${GREEN}Container: $container${NC}"

    # Mounts
    echo "Mounts:"
    docker inspect "$container" --format '{{range .Mounts}}  {{.Type}}: {{.Source}} -> {{.Destination}}{{println}}{{end}}'

    # Environment (relevant vars)
    echo "Environment:"
    docker inspect "$container" --format '{{range .Config.Env}}{{println}}{{end}}' | grep -E 'FQDN|CLIENT|SUBDOMAIN|WEBUI_NAME|OAUTH|REDIRECT' | sed 's/^/  /'

    # Status
    STATUS=$(docker inspect "$container" --format '{{.State.Status}}')
    HEALTH=$(docker inspect "$container" --format '{{.State.Health.Status}}' 2>/dev/null || echo "N/A")
    echo "Status: $STATUS (Health: $HEALTH)"
done
echo

# Volume sizes
echo -e "${BLUE}=== Volume Disk Usage ===${NC}"
for volume in $(docker volume ls -q | grep openwebui); do
    echo -n "$volume: "
    docker run --rm -v "$volume":/data alpine du -sh /data 2>/dev/null | awk '{print $1}'
done
echo

# Current repository status
echo -e "${BLUE}=== Repository Status ===${NC}"
if [ -d ~/open-webui ]; then
    cd ~/open-webui
    echo "Branch: $(git branch --show-current)"
    echo "Remote: $(git config --get remote.origin.url)"
    echo "Recent commits:"
    git log --oneline -5 | sed 's/^/  /'
else
    echo "Repository not found at ~/open-webui"
fi
echo

# Disk space
echo -e "${BLUE}=== Disk Space ===${NC}"
echo "Docker volumes:"
df -h /var/lib/docker/volumes/ | tail -1
echo
echo "/opt/ directory:"
df -h /opt/ | tail -1
echo

# Check if new directory structure exists
echo -e "${BLUE}=== Migration Status ===${NC}"
if [ -d "/opt/openwebui" ]; then
    echo "/opt/openwebui exists:"
    ls -la /opt/openwebui/
else
    echo "/opt/openwebui does not exist (migration not started)"
fi
echo

echo "=== Discovery Complete ==="
echo
echo "Next steps:"
echo "1. Review deployment details above"
echo "2. Ensure sufficient disk space (need 2x current data size)"
echo "3. Run: bash 2-backup-deployment.sh <container-name>"
