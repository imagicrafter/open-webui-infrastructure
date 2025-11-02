#!/bin/bash
# Cleanup script to restore Digital Ocean droplet to fresh state
# This allows re-running quick-setup.sh without destroying the droplet
#
# Usage:
#   sudo bash cleanup-for-rebuild.sh
#
# What this does:
#   - Stops and removes all Open WebUI containers
#   - Removes all Open WebUI Docker volumes
#   - Removes openwebui-network
#   - Removes /opt/openwebui-nginx directory (containerized nginx)
#   - Removes ALL HOST nginx site configurations
#   - Optionally removes nginx package completely
#   - Removes qbmgr user and home directory
#   - Removes qbmgr sudoers file
#
# What this preserves:
#   - Root SSH access and keys
#   - Docker installation
#   - System packages (certbot, jq, htop, etc.)
#   - SSL certificates in /etc/letsencrypt (optional cleanup)
#   - Network configuration and Cloudflare DNS

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}Droplet Cleanup for Quick-Setup Rebuild${NC}"
echo -e "${BLUE}==================================================${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ This script must be run as root${NC}"
    echo "Usage: sudo bash cleanup-for-rebuild.sh"
    exit 1
fi

# Confirmation prompt
echo -e "${YELLOW}WARNING: This will remove:${NC}"
echo "  - All Open WebUI containers and volumes"
echo "  - /opt/openwebui directory (ALL deployment data - bind mounts)"
echo "  - qbmgr user and home directory"
echo "  - /opt/openwebui-nginx directory (containerized nginx)"
echo "  - ALL HOST nginx site configurations (/etc/nginx/sites-*/*)"
echo "  - Optionally: nginx package and all configs"
echo
echo -e "${GREEN}This will preserve:${NC}"
echo "  - Root SSH access"
echo "  - Docker installation"
echo "  - System packages (unless nginx removal chosen)"
echo "  - SSL certificates (unless you choose to remove them)"
echo
read -p "Continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo

# Stop and remove all Open WebUI containers
echo -e "${BLUE}[1/8] Stopping and removing Open WebUI containers...${NC}"
CONTAINERS=$(docker ps -a --format '{{.Names}}' | grep -E '^openwebui-' || true)
if [ -n "$CONTAINERS" ]; then
    echo "$CONTAINERS" | while read container; do
        echo "  Stopping $container..."
        docker stop "$container" 2>/dev/null || true
        echo "  Removing $container..."
        docker rm "$container" 2>/dev/null || true
    done
    echo -e "${GREEN}✅ Containers removed${NC}"
else
    echo "  No Open WebUI containers found"
fi

# Remove Open WebUI Docker volumes
echo -e "${BLUE}[2/8] Removing Open WebUI Docker volumes...${NC}"
VOLUMES=$(docker volume ls --format '{{.Name}}' | grep -E '^openwebui-' || true)
if [ -n "$VOLUMES" ]; then
    echo "$VOLUMES" | while read volume; do
        echo "  Removing volume $volume..."
        docker volume rm "$volume" 2>/dev/null || true
    done
    echo -e "${GREEN}✅ Volumes removed${NC}"
else
    echo "  No Open WebUI volumes found"
fi

# Remove /opt/openwebui directory (bind mount data)
echo -e "${BLUE}[3/8] Removing /opt/openwebui directory...${NC}"
if [ -d "/opt/openwebui" ]; then
    # List what's being removed
    if [ -d "/opt/openwebui" ]; then
        CLIENT_DIRS=$(find /opt/openwebui -maxdepth 1 -type d -name "chat-*" 2>/dev/null | wc -l)
        if [ "$CLIENT_DIRS" -gt 0 ]; then
            echo "  Found $CLIENT_DIRS client deployment directories"
            find /opt/openwebui -maxdepth 1 -type d -name "chat-*" 2>/dev/null | while read dir; do
                echo "    - $(basename "$dir")"
            done
        fi
    fi
    rm -rf /opt/openwebui
    echo -e "${GREEN}✅ /opt/openwebui directory removed (includes all bind mount data)${NC}"
else
    echo "  Directory doesn't exist"
fi

# Remove Docker network
echo -e "${BLUE}[4/8] Removing openwebui-network...${NC}"
if docker network inspect openwebui-network >/dev/null 2>&1; then
    docker network rm openwebui-network 2>/dev/null || true
    echo -e "${GREEN}✅ Network removed${NC}"
else
    echo "  Network doesn't exist"
fi

# Remove nginx config directory (containerized nginx)
echo -e "${BLUE}[5/10] Removing /opt/openwebui-nginx...${NC}"
if [ -d "/opt/openwebui-nginx" ]; then
    rm -rf /opt/openwebui-nginx
    echo -e "${GREEN}✅ nginx config directory removed${NC}"
else
    echo "  Directory doesn't exist"
fi

# Remove ALL HOST nginx site configurations
echo -e "${BLUE}[6/10] Removing ALL HOST nginx site configurations...${NC}"
NGINX_CONFIGS_REMOVED=false
if [ -d "/etc/nginx/sites-enabled" ]; then
    ENABLED_COUNT=$(ls -A /etc/nginx/sites-enabled 2>/dev/null | wc -l)
    if [ "$ENABLED_COUNT" -gt 0 ]; then
        rm -rf /etc/nginx/sites-enabled/*
        echo -e "${GREEN}✅ Removed $ENABLED_COUNT config(s) from sites-enabled${NC}"
        NGINX_CONFIGS_REMOVED=true
    else
        echo "  No configs in sites-enabled"
    fi
else
    echo "  /etc/nginx/sites-enabled doesn't exist"
fi

if [ -d "/etc/nginx/sites-available" ]; then
    AVAILABLE_COUNT=$(ls -A /etc/nginx/sites-available 2>/dev/null | wc -l)
    if [ "$AVAILABLE_COUNT" -gt 0 ]; then
        rm -rf /etc/nginx/sites-available/*
        echo -e "${GREEN}✅ Removed $AVAILABLE_COUNT config(s) from sites-available${NC}"
        NGINX_CONFIGS_REMOVED=true
    else
        echo "  No configs in sites-available"
    fi
else
    echo "  /etc/nginx/sites-available doesn't exist"
fi

if [ "$NGINX_CONFIGS_REMOVED" = false ]; then
    echo -e "${GREEN}✅ No HOST nginx configs to remove${NC}"
fi

# Optional: Remove nginx package completely
echo
read -p "Also remove nginx package completely? (y/N): " remove_nginx
if [[ "$remove_nginx" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}[7/10] Removing nginx package...${NC}"
    if command -v nginx &> /dev/null; then
        systemctl stop nginx 2>/dev/null || true
        systemctl disable nginx 2>/dev/null || true
        apt-get purge -y nginx nginx-common nginx-core 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
        rm -rf /etc/nginx
        echo -e "${GREEN}✅ nginx package and configs removed${NC}"
    else
        echo "  nginx not installed"
    fi
else
    echo -e "${BLUE}[7/10] Preserving nginx package...${NC}"
    echo -e "${GREEN}✅ nginx package preserved${NC}"
fi

# Optional: Remove SSL certificates
echo
read -p "Also remove SSL certificates from /etc/letsencrypt? (y/N): " remove_ssl
if [[ "$remove_ssl" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}[8/10] Removing SSL certificates...${NC}"
    rm -rf /etc/letsencrypt
    echo -e "${GREEN}✅ SSL certificates removed${NC}"
else
    echo -e "${BLUE}[8/10] Preserving SSL certificates...${NC}"
    echo -e "${GREEN}✅ SSL certificates preserved${NC}"
fi

# Kill any processes owned by qbmgr
echo -e "${BLUE}[9/10] Killing processes owned by qbmgr...${NC}"
if id "qbmgr" &>/dev/null; then
    QBMGR_PROCS=$(ps -u qbmgr -o pid= 2>/dev/null || true)
    if [ -n "$QBMGR_PROCS" ]; then
        echo "$QBMGR_PROCS" | xargs kill -9 2>/dev/null || true
        echo -e "${GREEN}✅ Processes terminated${NC}"
    else
        echo "  No processes found"
    fi
else
    echo "  User doesn't exist"
fi

# Remove qbmgr from sudoers
echo -e "${BLUE}[10/11] Removing qbmgr from sudoers...${NC}"
if [ -f "/etc/sudoers.d/qbmgr" ]; then
    rm -f /etc/sudoers.d/qbmgr
    echo -e "${GREEN}✅ Sudoers file removed${NC}"
else
    echo "  Sudoers file doesn't exist"
fi

# Delete qbmgr user and home directory atomically, then remove group
echo -e "${BLUE}[11/11] Removing qbmgr user, home directory, and group...${NC}"
if id "qbmgr" &>/dev/null; then
    # -r flag removes home directory and mail spool atomically
    userdel -r qbmgr 2>/dev/null || true
    # Also remove the group if it still exists
    groupdel qbmgr 2>/dev/null || true
    echo -e "${GREEN}✅ User, home directory, and group removed${NC}"
else
    echo "  User doesn't exist"
fi

echo
echo -e "${BLUE}==================================================${NC}"
echo -e "${GREEN}✅ Cleanup Complete!${NC}"
echo -e "${BLUE}==================================================${NC}"
echo
echo "Droplet is now in clean state. Ready to run quick-setup:"
echo
echo -e "${GREEN}For test server (main branch):${NC}"
echo '  curl -fsSL https://raw.githubusercontent.com/imagicrafter/open-webui/main/mt/setup/quick-setup.sh | bash -s -- "" "test"'
echo
echo -e "${BLUE}For production server (release branch):${NC}"
echo '  curl -fsSL https://raw.githubusercontent.com/imagicrafter/open-webui/main/mt/setup/quick-setup.sh | bash -s -- "" "production"'
echo
echo -e "${YELLOW}Note:${NC} Root SSH access, Docker, and system packages remain intact."
echo
