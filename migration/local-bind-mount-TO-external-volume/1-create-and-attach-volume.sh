#!/usr/bin/env bash
#
# 1-create-and-attach-volume.sh
# Creates and attaches a Digital Ocean block storage volume for Open WebUI data migration
#
# Usage: sudo bash 1-create-and-attach-volume.sh
#

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
VOLUME_SIZE_GB=${VOLUME_SIZE_GB:-100}  # Default 100GB
VOLUME_NAME=${VOLUME_NAME:-openwebui-data}
MOUNT_POINT=${MOUNT_POINT:-/mnt/openwebui-volume}

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Digital Ocean Volume Creation & Attachment           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ This script must be run as root${NC}"
    echo "   Usage: sudo bash 1-create-and-attach-volume.sh"
    exit 1
fi

# Function to check if doctl is installed
check_doctl() {
    if command -v doctl >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to get current droplet ID
get_droplet_id() {
    # Try to get droplet ID from metadata service
    local droplet_id=$(curl -s http://169.254.169.254/metadata/v1/id 2>/dev/null || echo "")

    if [ -n "$droplet_id" ]; then
        echo "$droplet_id"
        return 0
    fi

    return 1
}

# Function to get current region
get_region() {
    # Try to get region from metadata service
    local region=$(curl -s http://169.254.169.254/metadata/v1/region 2>/dev/null || echo "")

    if [ -n "$region" ]; then
        echo "$region"
        return 0
    fi

    return 1
}

# Function to create volume with doctl
create_volume_with_doctl() {
    echo -e "${BLUE}Creating volume using doctl...${NC}"
    echo

    # Get droplet info
    local droplet_id=$(get_droplet_id)
    local region=$(get_region)

    if [ -z "$droplet_id" ] || [ -z "$region" ]; then
        echo -e "${YELLOW}⚠${NC}  Could not auto-detect droplet ID or region"
        echo -e "${BLUE}Please enter manually:${NC}"
        read -p "Droplet ID: " droplet_id
        read -p "Region (e.g., nyc3, sfo3): " region
    else
        echo -e "${GREEN}✓${NC} Detected droplet ID: $droplet_id"
        echo -e "${GREEN}✓${NC} Detected region: $region"
    fi

    echo
    echo -e "${CYAN}Volume Configuration:${NC}"
    echo "  Name:      $VOLUME_NAME"
    echo "  Size:      ${VOLUME_SIZE_GB}GB"
    echo "  Region:    $region"
    echo "  Droplet:   $droplet_id"
    echo

    read -p "Proceed with volume creation? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Volume creation cancelled${NC}"
        exit 0
    fi

    # Create volume
    echo -e "${BLUE}Creating volume...${NC}"
    if doctl compute volume create "$VOLUME_NAME" \
        --region "$region" \
        --size "${VOLUME_SIZE_GB}GiB" \
        --desc "Open WebUI data storage" \
        --format ID,Name,Size,Region; then
        echo -e "${GREEN}✓${NC} Volume created successfully"
    else
        echo -e "${RED}❌ Failed to create volume${NC}"
        exit 1
    fi

    # Get volume ID
    local volume_id=$(doctl compute volume list --format ID,Name --no-header | grep "$VOLUME_NAME" | awk '{print $1}')

    if [ -z "$volume_id" ]; then
        echo -e "${RED}❌ Could not find created volume${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓${NC} Volume ID: $volume_id"

    # Attach volume to droplet
    echo -e "${BLUE}Attaching volume to droplet...${NC}"
    if doctl compute volume-action attach "$volume_id" "$droplet_id"; then
        echo -e "${GREEN}✓${NC} Volume attached successfully"
    else
        echo -e "${RED}❌ Failed to attach volume${NC}"
        exit 1
    fi

    # Wait for volume to be available
    echo -e "${BLUE}Waiting for volume to be ready...${NC}"
    sleep 5

    return 0
}

# Function to display manual instructions
display_manual_instructions() {
    echo -e "${YELLOW}doctl CLI not found${NC}"
    echo
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}   MANUAL VOLUME CREATION INSTRUCTIONS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${BLUE}1. Log in to Digital Ocean Dashboard${NC}"
    echo "   https://cloud.digitalocean.com/volumes"
    echo
    echo -e "${BLUE}2. Create Volume:${NC}"
    echo "   • Click 'Create Volume'"
    echo "   • Size: ${VOLUME_SIZE_GB} GB"
    echo "   • Name: $VOLUME_NAME"
    echo "   • Description: Open WebUI data storage"
    echo "   • Region: Same as your droplet"
    echo "   • Filesystem: ext4"
    echo
    echo -e "${BLUE}3. Attach Volume:${NC}"
    echo "   • Select your droplet from the dropdown"
    echo "   • Click 'Attach Volume'"
    echo
    echo -e "${BLUE}4. Copy Mount Commands:${NC}"
    echo "   • After creation, DO will show mount commands"
    echo "   • Save the device path (e.g., /dev/disk/by-id/scsi-0DO_Volume_$VOLUME_NAME)"
    echo
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo

    read -p "Press Enter after you've attached the volume in DO dashboard..."
    echo
}

# Function to detect and mount volume
mount_volume() {
    echo -e "${BLUE}Detecting attached volume...${NC}"

    # Look for the volume device
    local volume_device=""
    local possible_devices=(
        "/dev/disk/by-id/scsi-0DO_Volume_${VOLUME_NAME}"
        "/dev/sda"
        "/dev/vda"
    )

    for device in "${possible_devices[@]}"; do
        if [ -b "$device" ]; then
            volume_device="$device"
            echo -e "${GREEN}✓${NC} Found volume device: $volume_device"
            break
        fi
    done

    if [ -z "$volume_device" ]; then
        echo -e "${YELLOW}⚠${NC}  Could not auto-detect volume device"
        echo -e "${BLUE}Please enter the device path manually:${NC}"
        echo "   (Check with: lsblk or ls /dev/disk/by-id/)"
        read -p "Device path: " volume_device

        if [ ! -b "$volume_device" ]; then
            echo -e "${RED}❌ Device not found: $volume_device${NC}"
            exit 1
        fi
    fi

    # Check if volume has a filesystem
    echo -e "${BLUE}Checking filesystem...${NC}"
    if ! blkid "$volume_device" | grep -q "TYPE="; then
        echo -e "${YELLOW}⚠${NC}  Volume has no filesystem, creating ext4..."
        if mkfs.ext4 -F "$volume_device"; then
            echo -e "${GREEN}✓${NC} Filesystem created"
        else
            echo -e "${RED}❌ Failed to create filesystem${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}✓${NC} Filesystem detected"
    fi

    # Create mount point
    echo -e "${BLUE}Creating mount point...${NC}"
    if [ ! -d "$MOUNT_POINT" ]; then
        mkdir -p "$MOUNT_POINT"
        echo -e "${GREEN}✓${NC} Created: $MOUNT_POINT"
    else
        echo -e "${GREEN}✓${NC} Mount point exists: $MOUNT_POINT"
    fi

    # Mount the volume
    echo -e "${BLUE}Mounting volume...${NC}"
    if mount -o defaults,nofail,discard "$volume_device" "$MOUNT_POINT"; then
        echo -e "${GREEN}✓${NC} Volume mounted at $MOUNT_POINT"
    else
        echo -e "${RED}❌ Failed to mount volume${NC}"
        exit 1
    fi

    # Add to fstab for persistent mounting
    echo -e "${BLUE}Adding to /etc/fstab for persistent mounting...${NC}"
    local fstab_entry="$volume_device $MOUNT_POINT ext4 defaults,nofail,discard 0 0"

    if grep -q "$MOUNT_POINT" /etc/fstab; then
        echo -e "${YELLOW}⚠${NC}  Entry already exists in /etc/fstab"
    else
        echo "$fstab_entry" >> /etc/fstab
        echo -e "${GREEN}✓${NC} Added to /etc/fstab"
    fi

    # Verify mount
    if df -h | grep -q "$MOUNT_POINT"; then
        echo -e "${GREEN}✓${NC} Volume successfully mounted and verified"
        echo
        df -h "$MOUNT_POINT"
    else
        echo -e "${RED}❌ Mount verification failed${NC}"
        exit 1
    fi
}

# Main execution
main() {
    echo -e "${CYAN}This script will:${NC}"
    echo "  1. Create a Digital Ocean block storage volume"
    echo "  2. Attach it to this droplet"
    echo "  3. Format and mount it at $MOUNT_POINT"
    echo

    # Check if doctl is available
    if check_doctl; then
        echo -e "${GREEN}✓${NC} doctl CLI detected - will use automated creation"
        echo
        create_volume_with_doctl
    else
        display_manual_instructions
    fi

    # Mount the volume
    mount_volume

    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Volume Setup Complete!                                ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${CYAN}Volume Information:${NC}"
    echo "  Name:        $VOLUME_NAME"
    echo "  Size:        ${VOLUME_SIZE_GB}GB"
    echo "  Mount Point: $MOUNT_POINT"
    echo
    echo -e "${CYAN}Next Steps:${NC}"
    echo "  1. Run: bash 2-migrate-to-external-volume.sh"
    echo "  2. This will migrate your Open WebUI data to the external volume"
    echo
}

# Run main function
main "$@"
