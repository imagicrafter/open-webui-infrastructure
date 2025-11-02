#!/usr/bin/env bash
#
# 9-rollback-to-local.sh
# Rolls back migration from external volume to local bind mounts
#
# Usage: sudo bash 9-rollback-to-local.sh
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
OPENWEBUI_BASE=${OPENWEBUI_BASE:-/opt/openwebui}
MOUNT_POINT=${MOUNT_POINT:-/mnt/openwebui-volume}
EXTERNAL_DATA_DIR="$MOUNT_POINT/openwebui"
LOG_FILE="/var/log/openwebui-rollback-$(date +%Y%m%d-%H%M%S).log"

echo -e "${RED}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  Rollback to Local Bind Mounts                        ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════╝${NC}"
echo

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ This script must be run as root${NC}"
    echo "   Usage: sudo bash 9-rollback-to-local.sh"
    exit 1
fi

# Pre-flight checks
preflight_checks() {
    log_info "Running pre-flight checks..."

    # Check if base directory is a symlink
    if [ ! -L "$OPENWEBUI_BASE" ]; then
        log_error "Base directory is not a symlink: $OPENWEBUI_BASE"
        echo -e "${RED}❌ Nothing to rollback - directory is not using external volume${NC}"
        exit 1
    fi
    log_success "Base directory is a symlink (as expected for rollback)"

    # Find backup directory
    local backup_dirs=($(ls -dt "${OPENWEBUI_BASE}.backup-"* 2>/dev/null || true))

    if [ ${#backup_dirs[@]} -eq 0 ]; then
        log_warning "No automatic backup found - will copy from external volume"
        BACKUP_FOUND=false
    else
        BACKUP_DIR="${backup_dirs[0]}"
        log_success "Found backup directory: $BACKUP_DIR"
        BACKUP_FOUND=true
    fi

    echo
}

# Discover Open WebUI containers
discover_containers() {
    log_info "Discovering Open WebUI containers..."

    CONTAINERS=($(docker ps -a --filter "name=^openwebui-" --format "{{.Names}}" | sort))

    if [ ${#CONTAINERS[@]} -eq 0 ]; then
        log_warning "No Open WebUI containers found"
        return 1
    fi

    log_success "Found ${#CONTAINERS[@]} container(s):"
    for container in "${CONTAINERS[@]}"; do
        local status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
        echo "  • $container ($status)"
    done
    echo

    return 0
}

# Stop all Open WebUI containers
stop_containers() {
    log_info "Stopping Open WebUI containers for rollback..."

    local stopped_count=0
    for container in "${CONTAINERS[@]}"; do
        local status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")

        if [ "$status" = "running" ]; then
            log_info "Stopping $container..."
            if docker stop "$container" >/dev/null 2>&1; then
                log_success "Stopped: $container"
                ((stopped_count++))
            else
                log_error "Failed to stop: $container"
                return 1
            fi
        else
            log_info "Already stopped: $container"
        fi
    done

    log_success "Stopped $stopped_count container(s)"
    echo
}

# Restore data
restore_data() {
    log_info "Restoring local data directory..."

    # Remove symlink
    if [ -L "$OPENWEBUI_BASE" ]; then
        log_info "Removing symlink: $OPENWEBUI_BASE"
        rm "$OPENWEBUI_BASE"
        log_success "Symlink removed"
    fi

    # Restore from backup or copy from external volume
    if [ "$BACKUP_FOUND" = true ]; then
        log_info "Restoring from backup: $BACKUP_DIR"

        if mv "$BACKUP_DIR" "$OPENWEBUI_BASE"; then
            log_success "Backup restored to $OPENWEBUI_BASE"
        else
            log_error "Failed to restore from backup"
            return 1
        fi
    else
        log_info "No backup found - copying from external volume"
        log_info "Copying from: $EXTERNAL_DATA_DIR"
        log_info "Copying to:   $OPENWEBUI_BASE"
        echo

        # Create target directory
        mkdir -p "$OPENWEBUI_BASE"

        # Copy data using rsync
        if rsync -ah --info=progress2 --stats "$EXTERNAL_DATA_DIR/" "$OPENWEBUI_BASE/"; then
            log_success "Data copied from external volume"
            echo
        else
            log_error "Failed to copy data from external volume"
            return 1
        fi
    fi

    # Verify restoration
    if [ -d "$OPENWEBUI_BASE" ] && [ ! -L "$OPENWEBUI_BASE" ]; then
        log_success "Local directory restored successfully"
    else
        log_error "Directory restoration verification failed"
        return 1
    fi

    echo
}

# Start containers
start_containers() {
    log_info "Starting Open WebUI containers..."

    local started_count=0
    for container in "${CONTAINERS[@]}"; do
        log_info "Starting $container..."
        if docker start "$container" >/dev/null 2>&1; then
            log_success "Started: $container"
            ((started_count++))
        else
            log_error "Failed to start: $container"
        fi
    done

    log_success "Started $started_count/${#CONTAINERS[@]} container(s)"
    echo

    # Wait for containers to become healthy
    log_info "Waiting for containers to become healthy (30s timeout)..."
    sleep 5

    for container in "${CONTAINERS[@]}"; do
        local wait_count=0
        local max_wait=30

        while [ $wait_count -lt $max_wait ]; do
            local health=$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
            local status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")

            if [ "$health" = "healthy" ] || [ "$status" = "running" -a "$health" = "none" ]; then
                log_success "$container is healthy"
                break
            fi

            ((wait_count++))
            sleep 1
        done

        if [ $wait_count -ge $max_wait ]; then
            log_warning "$container did not become healthy within timeout"
        fi
    done

    echo
}

# Cleanup external volume (optional)
cleanup_external_volume() {
    echo -e "${CYAN}External Volume Cleanup${NC}"
    echo

    read -p "Do you want to remove data from external volume? [y/N] " -n 1 -r
    echo
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Removing data from external volume: $EXTERNAL_DATA_DIR"

        if rm -rf "$EXTERNAL_DATA_DIR"; then
            log_success "External volume data removed"
        else
            log_error "Failed to remove external volume data"
            log_warning "You may need to manually remove: $EXTERNAL_DATA_DIR"
        fi
    else
        log_info "Keeping data on external volume for safety"
        echo -e "${BLUE}ℹ${NC}  You can manually remove later:"
        echo "     sudo rm -rf $EXTERNAL_DATA_DIR"
    fi

    echo
}

# Display rollback summary
display_summary() {
    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Rollback to Local Storage Complete!                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${CYAN}Rollback Summary:${NC}"
    echo "  Current location:   $OPENWEBUI_BASE (local directory)"
    echo "  Containers:         ${#CONTAINERS[@]}"
    echo "  Log file:           $LOG_FILE"
    echo

    if [ "$BACKUP_FOUND" = true ]; then
        echo -e "${CYAN}Restoration Method:${NC}"
        echo "  ✓ Restored from automatic backup"
    else
        echo -e "${CYAN}Restoration Method:${NC}"
        echo "  ✓ Copied from external volume"
    fi
    echo

    echo -e "${CYAN}Storage Information:${NC}"
    df -h "$OPENWEBUI_BASE" | tail -1
    echo

    echo -e "${CYAN}Next Steps:${NC}"
    echo "  1. Verify all deployments are working correctly"
    echo "  2. Test in browser to confirm functionality"
    echo "  3. If successful, you can detach/delete the external volume from DO dashboard"
    echo

    if [ -d "$EXTERNAL_DATA_DIR" ]; then
        echo -e "${YELLOW}⚠${NC}  External volume data still exists at:"
        echo "     $EXTERNAL_DATA_DIR"
        echo "     Consider removing it after verification"
    fi
    echo
}

# Main execution
main() {
    log_info "Starting rollback to local storage"
    log_info "Log file: $LOG_FILE"
    echo

    echo -e "${YELLOW}⚠${NC}  ${RED}WARNING: This will rollback to local bind mounts${NC}"
    echo
    echo -e "${CYAN}This script will:${NC}"
    echo "  1. Stop all Open WebUI containers"
    echo "  2. Remove symlink at $OPENWEBUI_BASE"

    if ls "${OPENWEBUI_BASE}.backup-"* 1> /dev/null 2>&1; then
        echo "  3. Restore from automatic backup"
    else
        echo "  3. Copy data from external volume (no backup found)"
    fi

    echo "  4. Restart all containers"
    echo
    echo -e "${YELLOW}⚠${NC}  Estimated downtime: 2-10 minutes"
    echo

    read -p "Are you sure you want to proceed? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Rollback cancelled${NC}"
        exit 0
    fi
    echo

    # Run rollback steps
    preflight_checks

    if ! discover_containers; then
        log_warning "No containers found, continuing with rollback..."
    else
        stop_containers || {
            log_error "Failed to stop containers"
            exit 1
        }
    fi

    restore_data || {
        log_error "Data restoration failed"
        # Attempt to restart containers
        if [ ${#CONTAINERS[@]} -gt 0 ]; then
            log_warning "Attempting to restart containers..."
            start_containers
        fi
        exit 1
    }

    if [ ${#CONTAINERS[@]} -gt 0 ]; then
        start_containers
    fi

    cleanup_external_volume

    display_summary

    log_success "Rollback completed successfully!"
}

# Run main function
main "$@"
