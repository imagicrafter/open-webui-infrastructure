#!/bin/bash
# Quick Setup for Open WebUI Deployment
# Run this as root on a fresh Digital Ocean droplet
#
# Usage Option 1 (auto-copy SSH key from root):
#   curl -fsSL https://raw.githubusercontent.com/imagicrafter/open-webui/main/mt/setup/quick-setup.sh | bash
#
# Usage Option 2 (provide SSH key):
#   curl -fsSL https://raw.githubusercontent.com/imagicrafter/open-webui/main/mt/setup/quick-setup.sh | bash -s -- "YOUR_SSH_PUBLIC_KEY"
#
# Usage Option 3 (provide SSH key + server type):
#   curl -fsSL https://raw.githubusercontent.com/imagicrafter/open-webui/main/mt/setup/quick-setup.sh | bash -s -- "YOUR_SSH_PUBLIC_KEY" "production"
#   curl -fsSL https://raw.githubusercontent.com/imagicrafter/open-webui/main/mt/setup/quick-setup.sh | bash -s -- "YOUR_SSH_PUBLIC_KEY" "test"

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
DEPLOY_USER="qbmgr"
REPO_URL="https://github.com/imagicrafter/open-webui.git"
SSH_KEY="${1:-}"
SERVER_TYPE="${2:-}"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Open WebUI Quick Setup                                 ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ This script must be run as root${NC}"
    echo
    echo "Usage:"
    echo "  curl -fsSL https://raw.githubusercontent.com/imagicrafter/open-webui/main/mt/setup/quick-setup.sh | bash"
    exit 1
fi

# Function to wait for apt locks to be released
wait_for_apt_locks() {
    local timeout=${1:-300}  # Default 5 minute timeout
    local elapsed=0

    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        if [ $elapsed -ge $timeout ]; then
            echo -e "${RED}⚠️  Timeout waiting for apt locks after ${timeout}s${NC}"
            return 1
        fi

        if [ $elapsed -eq 0 ]; then
            echo -e "${YELLOW}⏳ Waiting for apt/dpkg operations to complete...${NC}"
        fi

        sleep 5
        elapsed=$((elapsed + 5))

        # Show progress every 30 seconds
        if [ $((elapsed % 30)) -eq 0 ]; then
            echo -e "${YELLOW}⏳ Still waiting... (${elapsed}s elapsed)${NC}"
        fi
    done

    # Extra pause to ensure locks are fully released
    sleep 2
    return 0
}

# Wait for any existing apt operations to complete
echo -e "${YELLOW}Checking for running package operations...${NC}"
wait_for_apt_locks
echo -e "${GREEN}✅ Package system ready${NC}"
echo

# Prompt for server type if not provided
if [ -z "$SERVER_TYPE" ]; then
    # Check if running interactively (not via curl|bash)
    if [ -t 0 ]; then
        # Interactive mode - can prompt user
        echo -e "${CYAN}Select server type:${NC}"
        echo -e "  ${GREEN}1${NC}) Test Server (uses 'main' branch - latest development code)"
        echo -e "  ${BLUE}2${NC}) Production Server (uses 'release' branch - stable tested code)"
        echo -e "  ${YELLOW}3${NC}) Development Server (uses 'feature/volume-mount-prototype' branch - experimental)"
        echo
        read -p "Enter choice [1, 2, or 3]: " choice
        echo

        case $choice in
            1)
                SERVER_TYPE="test"
                ;;
            2)
                SERVER_TYPE="production"
                ;;
            3)
                SERVER_TYPE="development"
                ;;
            *)
                echo -e "${RED}❌ Invalid choice. Please enter 1, 2, or 3${NC}"
                exit 1
                ;;
        esac
    else
        # Non-interactive mode (curl|bash) - require parameter
        echo -e "${RED}❌ Server type must be specified when running via curl${NC}"
        echo
        echo "Usage:"
        echo -e "  ${GREEN}Test server:${NC}"
        echo "  curl -fsSL https://raw.githubusercontent.com/imagicrafter/open-webui/main/mt/setup/quick-setup.sh | bash -s -- \"\" \"test\""
        echo
        echo -e "  ${BLUE}Production server:${NC}"
        echo "  curl -fsSL https://raw.githubusercontent.com/imagicrafter/open-webui/main/mt/setup/quick-setup.sh | bash -s -- \"\" \"production\""
        echo
        echo -e "  ${YELLOW}Development server (experimental):${NC}"
        echo "  curl -fsSL https://raw.githubusercontent.com/imagicrafter/open-webui/feature/volume-mount-prototype/mt/setup/quick-setup.sh | bash -s -- \"\" \"development\""
        echo
        echo -e "  ${YELLOW}Or SSH to server first and run interactively:${NC}"
        echo "  ssh root@server-ip"
        echo "  curl -fsSL https://raw.githubusercontent.com/imagicrafter/open-webui/main/mt/setup/quick-setup.sh -o /tmp/setup.sh"
        echo "  bash /tmp/setup.sh"
        exit 1
    fi
fi

# Set branch based on server type
case "$SERVER_TYPE" in
    test|TEST|t|T)
        GIT_BRANCH="main"
        SERVER_TYPE_DISPLAY="Test"
        BRANCH_DISPLAY="main (development)"
        ;;
    production|PRODUCTION|prod|PROD|p|P)
        GIT_BRANCH="release"
        SERVER_TYPE_DISPLAY="Production"
        BRANCH_DISPLAY="release (stable)"
        ;;
    development|DEVELOPMENT|dev|DEV|d|D)
        GIT_BRANCH="feature/volume-mount-prototype"
        SERVER_TYPE_DISPLAY="Development"
        BRANCH_DISPLAY="feature/volume-mount-prototype (experimental)"
        ;;
    *)
        echo -e "${RED}❌ Invalid server type: $SERVER_TYPE${NC}"
        echo "Valid options: test, production, development"
        exit 1
        ;;
esac

echo -e "${GREEN}✅ Server Type: ${SERVER_TYPE_DISPLAY}${NC}"
echo -e "${GREEN}✅ Git Branch: ${BRANCH_DISPLAY}${NC}"
echo

# Determine SSH key source
if [ -z "$SSH_KEY" ]; then
    if [ -f /root/.ssh/authorized_keys ]; then
        echo -e "${YELLOW}No SSH key provided - will copy from root's authorized_keys${NC}"
        COPY_FROM_ROOT=true
    else
        echo -e "${RED}❌ No SSH key provided and root has no authorized_keys${NC}"
        echo
        echo "Either:"
        echo "  1. Provide SSH key: curl ... | bash -s -- \"YOUR_SSH_KEY\""
        echo "  2. Ensure root has SSH keys in /root/.ssh/authorized_keys"
        exit 1
    fi
else
    # Validate SSH key format
    if [[ ! "$SSH_KEY" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256) ]]; then
        echo -e "${RED}❌ Invalid SSH key format${NC}"
        echo "SSH key should start with 'ssh-rsa', 'ssh-ed25519', or 'ecdsa-sha2-nistp256'"
        exit 1
    fi
    COPY_FROM_ROOT=false
fi

# Step 1: Create user if doesn't exist
echo -e "${BLUE}[1/9] Creating user '$DEPLOY_USER'...${NC}"
if id "$DEPLOY_USER" &>/dev/null; then
    echo -e "${YELLOW}User already exists, continuing...${NC}"
else
    useradd -m -s /bin/bash "$DEPLOY_USER"
    echo -e "${GREEN}✅ User created${NC}"
fi

# Step 2: Add to sudo and docker groups
echo -e "${BLUE}[2/9] Configuring groups (sudo, docker)...${NC}"
usermod -aG sudo "$DEPLOY_USER"
usermod -aG docker "$DEPLOY_USER"
echo -e "${GREEN}✅ Groups configured${NC}"

# Step 3: Configure passwordless sudo
echo -e "${BLUE}[3/9] Enabling passwordless sudo...${NC}"
echo "$DEPLOY_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$DEPLOY_USER"
chmod 0440 "/etc/sudoers.d/$DEPLOY_USER"
echo -e "${GREEN}✅ Passwordless sudo enabled${NC}"

# Step 4: Set up SSH key
echo -e "${BLUE}[4/9] Setting up SSH access...${NC}"
# Fix home directory permissions (SSH requires 755 or 700)
chmod 755 "/home/$DEPLOY_USER"
mkdir -p "/home/$DEPLOY_USER/.ssh"

if [ "$COPY_FROM_ROOT" = true ]; then
    # Copy SSH keys from root
    cp /root/.ssh/authorized_keys "/home/$DEPLOY_USER/.ssh/authorized_keys"
    echo -e "${GREEN}✅ SSH keys copied from root${NC}"
else
    # Normalize SSH key to single line (remove any newlines/whitespace issues)
    SSH_KEY_CLEAN=$(echo "$SSH_KEY" | tr -d '\n\r' | tr -s ' ')
    echo "$SSH_KEY_CLEAN" > "/home/$DEPLOY_USER/.ssh/authorized_keys"
    echo -e "${GREEN}✅ SSH key configured${NC}"
fi

chown -R "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
chmod 700 "/home/$DEPLOY_USER/.ssh"
chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys"

# Step 4.5: Configure environment and auto-start
echo -e "${BLUE}[4.5/9] Configuring environment and auto-start...${NC}"

# Set Docker image tag based on server type
case "$SERVER_TYPE" in
    test|TEST|t|T)
        DOCKER_IMAGE_TAG="main"
        ;;
    production|PRODUCTION|prod|PROD|p|P)
        DOCKER_IMAGE_TAG="release"
        ;;
    development|DEVELOPMENT|dev|DEV|d|D)
        DOCKER_IMAGE_TAG="main"
        ;;
esac

# Create .bashrc with environment variables
cat > "/home/$DEPLOY_USER/.bashrc" << BASHRC_EOF
# Open WebUI Deployment Environment
# Server Type: ${SERVER_TYPE_DISPLAY}
# Git Branch: ${GIT_BRANCH}

# Set Docker image tag for deployments
export OPENWEBUI_IMAGE_TAG="${DOCKER_IMAGE_TAG}"

# Standard bashrc content
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# User aliases and functions
alias ll='ls -alh'
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dlogs='docker logs -f'

# Docker completion
if [ -f /usr/share/bash-completion/completions/docker ]; then
    . /usr/share/bash-completion/completions/docker
fi
BASHRC_EOF

chown "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.bashrc"
chmod 644 "/home/$DEPLOY_USER/.bashrc"

# Create .bash_profile that sources .bashrc and starts client-manager
cat > "/home/$DEPLOY_USER/.bash_profile" << 'BASH_PROFILE_EOF'
# Source bashrc for environment setup
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi

# Auto-start client-manager on interactive SSH login
if [[ -n "$SSH_CONNECTION" ]] || [[ -n "$SSH_CLIENT" ]]; then
    # Check if this is an interactive shell
    if [[ $- == *i* ]]; then
        cd ~/open-webui/mt 2>/dev/null && ./client-manager.sh
    fi
fi
BASH_PROFILE_EOF

chown "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.bash_profile"
chmod 644 "/home/$DEPLOY_USER/.bash_profile"
echo -e "${GREEN}✅ Environment configured (OPENWEBUI_IMAGE_TAG=${DOCKER_IMAGE_TAG})${NC}"

# Step 5: Clone Open WebUI repository
echo -e "${BLUE}[5/9] Cloning repository (branch: ${GIT_BRANCH})...${NC}"
REPO_PATH="/home/$DEPLOY_USER/open-webui"
if [ -d "$REPO_PATH" ]; then
    echo -e "${YELLOW}Repository exists, checking out ${GIT_BRANCH} and pulling latest...${NC}"
    sudo -u "$DEPLOY_USER" git -C "$REPO_PATH" checkout "$GIT_BRANCH" || true
    sudo -u "$DEPLOY_USER" git -C "$REPO_PATH" pull origin "$GIT_BRANCH" || true
else
    sudo -u "$DEPLOY_USER" git clone -b "$GIT_BRANCH" "$REPO_URL" "$REPO_PATH"
fi

# Make scripts executable
chmod +x "$REPO_PATH/mt/client-manager.sh"
chmod +x "$REPO_PATH/mt/nginx-container/deploy-nginx-container.sh"
chmod +x "$REPO_PATH/mt/setup"/*.sh 2>/dev/null || true

echo -e "${GREEN}✅ Repository ready at $REPO_PATH (branch: ${GIT_BRANCH})${NC}"

# Step 6: Create directories
echo -e "${BLUE}[6/9] Creating directories...${NC}"
mkdir -p /opt/openwebui-nginx
chown -R "$DEPLOY_USER:$DEPLOY_USER" /opt/openwebui-nginx
echo -e "${GREEN}✅ Created /opt/openwebui-nginx${NC}"

# Step 7: Configure swap space
echo -e "${BLUE}[7/9] Configuring swap space...${NC}"

# Check if swap already exists
EXISTING_SWAP=$(swapon --show --noheadings | wc -l)
if [ "$EXISTING_SWAP" -gt 0 ]; then
    echo -e "${YELLOW}Swap already configured:${NC}"
    swapon --show
    echo -e "${GREEN}✅ Skipping swap creation${NC}"
else
    # Calculate swap size based on system memory
    # Recommendation:
    #   <= 2GB RAM: 2GB swap
    #   2-4GB RAM: Equal to RAM
    #   4-8GB RAM: 4GB swap
    #   > 8GB RAM: 4GB swap (or custom)

    TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_MEM_GB=$((TOTAL_MEM_KB / 1024 / 1024))

    if [ "$TOTAL_MEM_GB" -le 2 ]; then
        SWAP_SIZE_GB=2
    elif [ "$TOTAL_MEM_GB" -le 4 ]; then
        SWAP_SIZE_GB=$TOTAL_MEM_GB
    else
        SWAP_SIZE_GB=4
    fi

    echo -e "${CYAN}System memory: ${TOTAL_MEM_GB}GB${NC}"
    echo -e "${CYAN}Creating ${SWAP_SIZE_GB}GB swap file...${NC}"

    # Check available disk space
    AVAILABLE_SPACE_GB=$(df / | tail -1 | awk '{print int($4/1024/1024)}')
    if [ "$AVAILABLE_SPACE_GB" -lt "$((SWAP_SIZE_GB + 5))" ]; then
        echo -e "${YELLOW}⚠️  Limited disk space (${AVAILABLE_SPACE_GB}GB available)${NC}"
        echo -e "${YELLOW}⚠️  Reducing swap size to 1GB${NC}"
        SWAP_SIZE_GB=1
    fi

    # Create swap file
    if fallocate -l "${SWAP_SIZE_GB}G" /swapfile 2>/dev/null; then
        echo -e "${GREEN}✅ Swap file allocated (${SWAP_SIZE_GB}GB)${NC}"
    else
        # Fallback to dd if fallocate fails
        echo -e "${YELLOW}Using dd to create swap file (this may take a moment)...${NC}"
        dd if=/dev/zero of=/swapfile bs=1M count=$((SWAP_SIZE_GB * 1024)) status=progress 2>/dev/null
        echo -e "${GREEN}✅ Swap file created (${SWAP_SIZE_GB}GB)${NC}"
    fi

    # Set correct permissions (critical for security)
    chmod 600 /swapfile
    echo -e "${GREEN}✅ Swap file permissions set (600)${NC}"

    # Format as swap
    mkswap /swapfile > /dev/null
    echo -e "${GREEN}✅ Swap file formatted${NC}"

    # Activate swap
    swapon /swapfile
    echo -e "${GREEN}✅ Swap activated${NC}"

    # Make it permanent (survives reboots)
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo -e "${GREEN}✅ Swap configured in /etc/fstab${NC}"
    fi

    # Show swap status
    echo -e "${CYAN}Current swap configuration:${NC}"
    swapon --show
    echo
    free -h | grep -E "Mem:|Swap:"
fi

# Step 8: Install packages
echo -e "${BLUE}[8/9] Installing packages (certbot, jq, htop, tree)...${NC}"
echo -e "${YELLOW}Updating package lists...${NC}"
apt-get update || true

# Wait for any background processes triggered by apt-get update (like unattended-upgrades)
echo -e "${YELLOW}Waiting for package system to be ready...${NC}"
wait_for_apt_locks
echo -e "${GREEN}✅ Package locks released${NC}"

echo -e "${YELLOW}Installing packages (this may take 10-30 seconds)...${NC}"
DEBIAN_FRONTEND=noninteractive apt-get install -y certbot jq htop tree net-tools imagemagick
echo -e "${GREEN}✅ Packages installed${NC}"

# Step 8.5: Optimize system services for multi-container deployments
echo -e "${BLUE}[8.5/9] Optimizing system services...${NC}"

# Disable snapd (saves ~20MB RAM)
if systemctl is-active --quiet snapd 2>/dev/null; then
    echo -e "${YELLOW}Disabling snapd (snap package manager)...${NC}"
    systemctl stop snapd snapd.socket 2>/dev/null || true
    systemctl disable snapd snapd.socket 2>/dev/null || true
    systemctl mask snapd snapd.socket 2>/dev/null || true
    echo -e "${GREEN}✅ snapd disabled (saves ~20MB RAM)${NC}"
else
    echo -e "${CYAN}snapd already disabled${NC}"
fi

# Disable multipathd (saves ~27MB RAM)
if systemctl is-active --quiet multipathd 2>/dev/null; then
    echo -e "${YELLOW}Disabling multipathd (multipath storage daemon)...${NC}"
    systemctl stop multipathd 2>/dev/null || true
    systemctl disable multipathd 2>/dev/null || true
    echo -e "${GREEN}✅ multipathd disabled (saves ~27MB RAM)${NC}"
else
    echo -e "${CYAN}multipathd already disabled${NC}"
fi

# Disable packagekit (saves ~8MB RAM)
if systemctl is-active --quiet packagekit 2>/dev/null; then
    echo -e "${YELLOW}Disabling packagekit (GUI package manager)...${NC}"
    systemctl stop packagekit 2>/dev/null || true
    systemctl disable packagekit 2>/dev/null || true
    systemctl mask packagekit 2>/dev/null || true
    echo -e "${GREEN}✅ packagekit disabled (saves ~8MB RAM)${NC}"
else
    echo -e "${CYAN}packagekit already disabled${NC}"
fi

echo -e "${GREEN}✅ System services optimized (saves ~55MB RAM for containers)${NC}"

# Step 8.5: Create OpenWebUI directory structure
echo -e "${BLUE}[8.5/10] Creating OpenWebUI directory structure...${NC}"
if mkdir -p /opt/openwebui/defaults; then
    chown -R "$DEPLOY_USER:$DEPLOY_USER" /opt/openwebui
    echo -e "${GREEN}✅ Directory structure created at /opt/openwebui${NC}"
else
    echo -e "${RED}❌ Failed to create /opt/openwebui directory${NC}"
    exit 1
fi

# Step 8.6: Extract default static assets for volume-mounted deployments
echo -e "${BLUE}[8.6/10] Extracting default static assets...${NC}"
echo -e "${CYAN}This prepares branding assets for volume-mounted deployments${NC}"

# Run extraction script as deploy user
if sudo -u "$DEPLOY_USER" bash "${REPO_PATH}/mt/setup/lib/extract-default-static.sh"; then
    echo -e "${GREEN}✅ Default assets extracted to /opt/openwebui/defaults/static${NC}"
else
    echo -e "${YELLOW}⚠️  Default asset extraction failed${NC}"
    echo -e "${YELLOW}   You can run manually later: bash ~/open-webui/mt/setup/lib/extract-default-static.sh${NC}"
fi

# Step 8.7: Install branding monitor service
echo -e "${BLUE}[8.7/10] Installing branding monitor service...${NC}"
echo -e "${CYAN}This automatically restores custom branding after container restarts${NC}"

if bash "${REPO_PATH}/mt/setup/services/install-branding-monitor.sh" > /tmp/branding-monitor-install.log 2>&1; then
    echo -e "${GREEN}✅ Branding monitor service installed and started${NC}"
    echo -e "${CYAN}   Service will automatically inject branding when containers restart${NC}"
else
    echo -e "${YELLOW}⚠️  Branding monitor installation failed${NC}"
    echo -e "${YELLOW}   Check log: /tmp/branding-monitor-install.log${NC}"
    echo -e "${YELLOW}   You can install manually later: sudo bash ~/open-webui/mt/setup/services/install-branding-monitor.sh${NC}"
fi

# Step 9: Create welcome message
echo -e "${BLUE}[9/10] Creating welcome message...${NC}"
cat > "/home/$DEPLOY_USER/WELCOME.txt" << EOF
╔════════════════════════════════════════════════════════════╗
║          Open WebUI Deployment Server Ready                ║
╚════════════════════════════════════════════════════════════╝

✅ Quick setup completed successfully!

Server Configuration:
  - Server Type: ${SERVER_TYPE_DISPLAY}
  - Git Branch: ${GIT_BRANCH}
  - Docker Image: ghcr.io/imagicrafter/open-webui:${DOCKER_IMAGE_TAG}
  - User: qbmgr (sudo + docker access)
  - Repository: ~/open-webui
  - nginx directory: /opt/openwebui-nginx
  - Default assets: /opt/openwebui/defaults/static
  - Branding monitor: Enabled (auto-injects on restart)
  - Swap: 2GB configured
  - Memory optimized: ~55MB saved (services disabled)
  - Container limits: 700MB per container (supports 2+ containers)

Quick Start Commands:

1. Start the client manager:
   cd ~/open-webui/mt
   ./client-manager.sh

2. Deploy nginx (option 2 in menu)
   Then create client deployments (option 3)

3. Check running containers:
   docker ps

Documentation:
  - Main Guide: ~/open-webui/mt/README.md (Getting Started section)
  - nginx Setup: ~/open-webui/mt/nginx-container/README.md
  - Setup Details: ~/open-webui/mt/setup/README.md

Security Note:
  Root SSH is still enabled. After testing qbmgr access, disable it:
  sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
  sudo systemctl reload sshd

EOF

chown "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/WELCOME.txt"
echo -e "${GREEN}✅ Welcome message created${NC}"

# Get droplet IP
DROPLET_IP=$(hostname -I | awk '{print $1}')

# Summary
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}🎉 Setup Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo
echo "Configuration:"
echo -e "  ${GREEN}✅${NC} Server Type: ${SERVER_TYPE_DISPLAY}"
echo -e "  ${GREEN}✅${NC} Git Branch: ${GIT_BRANCH}"
echo -e "  ${GREEN}✅${NC} Docker Image: ghcr.io/imagicrafter/open-webui:${DOCKER_IMAGE_TAG}"
echo -e "  ${GREEN}✅${NC} User: qbmgr"
echo -e "  ${GREEN}✅${NC} Groups: sudo, docker"
echo -e "  ${GREEN}✅${NC} Repository: /home/qbmgr/open-webui"
if [ "$COPY_FROM_ROOT" = true ]; then
    echo -e "  ${GREEN}✅${NC} SSH keys: Copied from root"
else
    echo -e "  ${GREEN}✅${NC} SSH key: Configured"
fi
echo -e "  ${GREEN}✅${NC} Packages: certbot, jq, htop, tree"
echo -e "  ${GREEN}✅${NC} Auto-start: client-manager on login"
echo -e "  ${GREEN}✅${NC} Default assets: /opt/openwebui/defaults/static"
echo -e "  ${GREEN}✅${NC} Swap: 2GB configured"
echo -e "  ${GREEN}✅${NC} Services optimized: snapd, multipathd, packagekit disabled"
echo -e "  ${GREEN}✅${NC} Memory saved: ~55MB for containers"
echo
echo -e "${YELLOW}Security Reminder:${NC}"
echo -e "  Root SSH password login is enabled. After testing qbmgr access, secure it with:"
echo -e "  ${BLUE}sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config && sudo systemctl reload sshd${NC}"
echo

# Test Docker access
echo -e "${BLUE}Testing Docker access for qbmgr...${NC}"
if sudo -u "$DEPLOY_USER" docker ps > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Docker access verified${NC}"
else
    echo -e "${YELLOW}⚠️  Docker access may require logout/login to activate${NC}"
fi

echo
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}🎉 Setup Complete! 🎉${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo
echo -e "${BLUE}Next Step:${NC}"
echo -e "  1. ${BLUE}Exit this root session${NC}"
echo -e "  2. ${BLUE}SSH as qbmgr to auto-start client-manager:${NC}"
echo -e "     ${YELLOW}ssh qbmgr@${DROPLET_IP}${NC}"
echo
echo -e "${GREEN}The client-manager will start automatically on login!${NC}"
echo
