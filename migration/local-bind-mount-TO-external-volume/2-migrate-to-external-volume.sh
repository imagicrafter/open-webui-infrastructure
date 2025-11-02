#!/usr/bin/env bash
#
# 2-migrate-to-external-volume.sh
# Migrates Open WebUI data from local bind mounts to external volume using symlink approach
#
# Usage: sudo bash 2-migrate-to-external-volume.sh
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
BACKUP_DIR="$MOUNT_POINT/backup-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/var/log/openwebui-migration-external-$(date +%Y%m%d-%H%M%S).log"

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Migrate Open WebUI to External Volume                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
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
    echo "   Usage: sudo bash 2-migrate-to-external-volume.sh"
    exit 1
fi

# Pre-flight checks
preflight_checks() {
    log_info "Running pre-flight checks..."

    # Check if external volume is mounted
    if ! mountpoint -q "$MOUNT_POINT"; then
        log_error "External volume not mounted at $MOUNT_POINT"
        echo -e "${RED}❌ Please run 1-create-and-attach-volume.sh first${NC}"
        exit 1
    fi
    log_success "External volume mounted at $MOUNT_POINT"

    # Check if Open WebUI base directory exists
    if [ ! -d "$OPENWEBUI_BASE" ]; then
        log_error "Open WebUI base directory not found: $OPENWEBUI_BASE"
        exit 1
    fi
    log_success "Open WebUI base directory exists: $OPENWEBUI_BASE"

    # Check if it's already a symlink
    if [ -L "$OPENWEBUI_BASE" ]; then
        log_warning "Base directory is already a symlink"
        local link_target=$(readlink -f "$OPENWEBUI_BASE")
        echo -e "${YELLOW}⚠${NC}  Current symlink points to: $link_target"

        read -p "Continue with re-migration? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Migration cancelled${NC}"
            exit 0
        fi
    fi

    # Check available space on external volume
    local available_space=$(df "$MOUNT_POINT" | tail -1 | awk '{print $4}')
    local required_space=$(du -s "$OPENWEBUI_BASE" | awk '{print $1}')
    local required_space_with_buffer=$((required_space * 2)) # 2x for safety

    if [ "$available_space" -lt "$required_space_with_buffer" ]; then
        log_error "Insufficient space on external volume"
        echo -e "${RED}❌ Available: $(numfmt --to=iec-i --suffix=B $((available_space * 1024)))${NC}"
        echo -e "${RED}   Required:  $(numfmt --to=iec-i --suffix=B $((required_space_with_buffer * 1024))) (with buffer)${NC}"
        exit 1
    fi
    log_success "Sufficient space available on external volume"

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
    log_info "Stopping Open WebUI containers for migration..."

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

# Migrate data to external volume
migrate_data() {
    log_info "Migrating data to external volume..."

    # Create external data directory
    if [ ! -d "$EXTERNAL_DATA_DIR" ]; then
        log_info "Creating external data directory: $EXTERNAL_DATA_DIR"
        mkdir -p "$EXTERNAL_DATA_DIR"
    fi

    # Copy data using rsync for efficiency and resume capability
    log_info "Copying data from $OPENWEBUI_BASE to $EXTERNAL_DATA_DIR"
    log_info "This may take several minutes depending on data size..."
    echo

    # Show progress with rsync
    if rsync -ah --info=progress2 --stats "$OPENWEBUI_BASE/" "$EXTERNAL_DATA_DIR/"; then
        log_success "Data copied successfully"
        echo
    else
        log_error "Data copy failed"
        return 1
    fi

    # Verify data integrity
    log_info "Verifying data integrity..."

    local source_count=$(find "$OPENWEBUI_BASE" -type f | wc -l)
    local dest_count=$(find "$EXTERNAL_DATA_DIR" -type f | wc -l)

    if [ "$source_count" -eq "$dest_count" ]; then
        log_success "File count matches: $source_count files"
    else
        log_error "File count mismatch! Source: $source_count, Destination: $dest_count"
        return 1
    fi

    echo
}

# Create symlink
create_symlink() {
    log_info "Creating symlink for minimal downtime migration..."

    # Backup original directory (move it aside)
    local backup_path="${OPENWEBUI_BASE}.backup-$(date +%Y%m%d-%H%M%S)"
    log_info "Backing up original directory to: $backup_path"

    if mv "$OPENWEBUI_BASE" "$backup_path"; then
        log_success "Original directory backed up"
    else
        log_error "Failed to backup original directory"
        return 1
    fi

    # Create symlink
    log_info "Creating symlink: $OPENWEBUI_BASE → $EXTERNAL_DATA_DIR"

    if ln -s "$EXTERNAL_DATA_DIR" "$OPENWEBUI_BASE"; then
        log_success "Symlink created successfully"
    else
        log_error "Failed to create symlink"
        # Attempt to restore
        log_warning "Restoring original directory..."
        mv "$backup_path" "$OPENWEBUI_BASE"
        return 1
    fi

    # Verify symlink
    if [ -L "$OPENWEBUI_BASE" ]; then
        local link_target=$(readlink -f "$OPENWEBUI_BASE")
        if [ "$link_target" = "$EXTERNAL_DATA_DIR" ]; then
            log_success "Symlink verified: $link_target"
        else
            log_error "Symlink points to wrong location: $link_target"
            return 1
        fi
    else
        log_error "Symlink creation verification failed"
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
            # Don't return 1 here, try to start all containers
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

# Display migration summary
display_summary() {
    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Migration to External Volume Complete!               ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${CYAN}Migration Summary:${NC}"
    echo "  Original location:  $OPENWEBUI_BASE (now symlink)"
    echo "  External location:  $EXTERNAL_DATA_DIR"
    echo "  Symlink:            $OPENWEBUI_BASE → $EXTERNAL_DATA_DIR"
    echo "  Containers:         ${#CONTAINERS[@]}"
    echo "  Log file:           $LOG_FILE"
    echo
    echo -e "${CYAN}Storage Information:${NC}"
    df -h "$EXTERNAL_DATA_DIR" | tail -1
    echo
    echo -e "${CYAN}Next Steps:${NC}"
    echo "  1. Verify all deployments are working correctly"
    echo "  2. Run: bash 3-verify-external-volume.sh"
    echo "  3. If issues occur, rollback with: bash 9-rollback-to-local.sh"
    echo
    echo -e "${YELLOW}⚠${NC}  Important: Keep the backup directory until verified:"
    echo "     ${OPENWEBUI_BASE}.backup-*"
    echo
}

# Main execution
main() {
    log_info "Starting migration to external volume"
    log_info "Log file: $LOG_FILE"
    echo

    echo -e "${CYAN}This script will:${NC}"
    echo "  1. Stop all Open WebUI containers"
    echo "  2. Copy data to external volume: $EXTERNAL_DATA_DIR"
    echo "  3. Create symlink: $OPENWEBUI_BASE → $EXTERNAL_DATA_DIR"
    echo "  4. Restart all containers"
    echo
    echo -e "${YELLOW}⚠${NC}  Estimated downtime: 2-10 minutes depending on data size"
    echo

    read -p "Proceed with migration? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Migration cancelled${NC}"
        exit 0
    fi
    echo

    # Run migration steps
    preflight_checks

    if ! discover_containers; then
        log_error "No containers to migrate"
        exit 1
    fi

    stop_containers || {
        log_error "Failed to stop containers"
        exit 1
    }

    migrate_data || {
        log_error "Data migration failed"
        # Attempt to restart containers
        log_warning "Attempting to restart containers..."
        start_containers
        exit 1
    }

    create_symlink || {
        log_error "Symlink creation failed"
        # Attempt to restart containers
        log_warning "Attempting to restart containers..."
        start_containers
        exit 1
    }

    start_containers

    display_summary

    log_success "Migration completed successfully!"
}

# Run main function
main "$@"
