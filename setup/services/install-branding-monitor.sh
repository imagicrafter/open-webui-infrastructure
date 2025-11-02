#!/usr/bin/env bash
#
# install-branding-monitor.sh
# Installs the Open WebUI branding monitor service
#
# Usage: sudo bash install-branding-monitor.sh
#

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Open WebUI Branding Monitor Setup    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ This script must be run as root${NC}"
    echo "   Usage: sudo bash install-branding-monitor.sh"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Files to install
MONITOR_SCRIPT="${SCRIPT_DIR}/branding-monitor.sh"
SERVICE_FILE="${SCRIPT_DIR}/branding-monitor.service"
LOG_FILE="/var/log/openwebui-branding-monitor.log"

# Verify files exist
echo -e "${BLUE}Checking installation files...${NC}"

if [ ! -f "$MONITOR_SCRIPT" ]; then
    echo -e "${RED}❌ Monitor script not found: $MONITOR_SCRIPT${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Monitor script found"

if [ ! -f "$SERVICE_FILE" ]; then
    echo -e "${RED}❌ Service file not found: $SERVICE_FILE${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Service file found"

# Check if qbmgr user exists
if ! id -u qbmgr >/dev/null 2>&1; then
    echo -e "${RED}❌ User 'qbmgr' does not exist${NC}"
    echo "   This service is designed to run as qbmgr user"
    exit 1
fi
echo -e "${GREEN}✓${NC} User 'qbmgr' exists"

# Check if qbmgr is in docker group
if ! groups qbmgr | grep -q docker; then
    echo -e "${YELLOW}⚠${NC}  User 'qbmgr' is not in 'docker' group"
    echo -e "${BLUE}Adding qbmgr to docker group...${NC}"
    usermod -aG docker qbmgr
    echo -e "${GREEN}✓${NC} User added to docker group"
fi

echo
echo -e "${BLUE}Installing branding monitor...${NC}"

# Make monitor script executable
chmod +x "$MONITOR_SCRIPT"
echo -e "${GREEN}✓${NC} Made monitor script executable"

# Copy service file to systemd
cp "$SERVICE_FILE" /etc/systemd/system/branding-monitor.service
echo -e "${GREEN}✓${NC} Copied service file to /etc/systemd/system/"

# Create log file with correct permissions
touch "$LOG_FILE"
chown qbmgr:qbmgr "$LOG_FILE"
echo -e "${GREEN}✓${NC} Created log file: $LOG_FILE"

# Reload systemd
systemctl daemon-reload
echo -e "${GREEN}✓${NC} Reloaded systemd"

# Stop service if already running
if systemctl is-active --quiet branding-monitor; then
    echo -e "${BLUE}Stopping existing service...${NC}"
    systemctl stop branding-monitor
fi

# Enable and start service
systemctl enable branding-monitor
echo -e "${GREEN}✓${NC} Enabled service (will start on boot)"

systemctl start branding-monitor
echo -e "${GREEN}✓${NC} Started service"

# Wait a moment and check status
sleep 2

echo
echo -e "${BLUE}Checking service status...${NC}"
if systemctl is-active --quiet branding-monitor; then
    echo -e "${GREEN}✅ Service is running${NC}"
    echo
    echo -e "${BLUE}Recent log entries:${NC}"
    journalctl -u branding-monitor -n 10 --no-pager
else
    echo -e "${RED}❌ Service failed to start${NC}"
    echo
    echo -e "${BLUE}Error log:${NC}"
    journalctl -u branding-monitor -n 20 --no-pager
    exit 1
fi

echo
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Installation Complete!               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo
echo -e "${BLUE}Service Details:${NC}"
echo "  Name:     branding-monitor"
echo "  User:     qbmgr"
echo "  Log File: $LOG_FILE"
echo
echo -e "${BLUE}Management Commands:${NC}"
echo "  Status:   systemctl status branding-monitor"
echo "  Logs:     journalctl -u branding-monitor -f"
echo "  Stop:     sudo systemctl stop branding-monitor"
echo "  Start:    sudo systemctl start branding-monitor"
echo "  Restart:  sudo systemctl restart branding-monitor"
echo "  Disable:  sudo systemctl disable branding-monitor"
echo
echo -e "${BLUE}How It Works:${NC}"
echo "  1. Service monitors Docker events for Open WebUI containers"
echo "  2. When a container becomes 'healthy' after restart"
echo "  3. Automatically injects custom branding from /opt/openwebui/{client_id}/branding/"
echo "  4. Logs all activity to $LOG_FILE"
echo
echo -e "${YELLOW}⚠${NC}  Note: After branding injection, you may need to purge Cloudflare cache"
echo "    to see changes immediately in browsers."
echo
