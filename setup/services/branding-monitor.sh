#!/usr/bin/env bash
#
# branding-monitor.sh
# Monitors Docker containers and auto-injects branding when they become healthy
#
# Usage: ./branding-monitor.sh
#
# This service listens to Docker events and automatically handles branding for
# Open WebUI containers when they transition to "healthy" state.
#
# Phase Detection:
#   - Phase 2: Volume-mounted static/ directory - branding persists automatically (no injection)
#   - Phase 1: Branding/ directory - runs injection script to copy branding to container
#
# This ensures custom branding persists across container restarts without
# manual intervention.
#
# Install as systemd service:
#   sudo cp branding-monitor.service /etc/systemd/system/
#   sudo systemctl enable branding-monitor
#   sudo systemctl start branding-monitor
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
INJECTION_SCRIPT="${SCRIPT_DIR}/../lib/inject-branding-post-startup.sh"

# Load centralized configuration
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [ -f "$REPO_ROOT/setup/lib/config.sh" ]; then
    source "$REPO_ROOT/setup/lib/config.sh"
    load_global_config 2>/dev/null || true
fi

# Set defaults
OPENWEBUI_BASE="${BASE_DIR:-/opt/openwebui}"
LOG_FILE="/var/log/openwebui-branding-monitor.log"

# Color codes for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Check if injection script exists
check_injection_script() {
    if [ ! -f "$INJECTION_SCRIPT" ]; then
        log_error "Injection script not found: $INJECTION_SCRIPT"
        exit 1
    fi

    if [ ! -x "$INJECTION_SCRIPT" ]; then
        log_warning "Making injection script executable"
        chmod +x "$INJECTION_SCRIPT"
    fi
}

# Extract client_id from container name
get_client_id() {
    local container_name="$1"
    # Strip "openwebui-" prefix
    echo "${container_name#openwebui-}"
}

# Check if container has branding and detect deployment mode
# Returns: "phase1:/path" or "phase2:/path" or exits with code 1 if no branding
has_branding() {
    local client_id="$1"
    local static_dir="${OPENWEBUI_BASE}/${client_id}/static"
    local branding_dir="${OPENWEBUI_BASE}/${client_id}/branding"

    # Check Phase 2 first (static directory with branding files)
    if [ -d "$static_dir" ]; then
        # Check if directory has branding files
        if [ -f "${static_dir}/logo.png" ] || [ -f "${static_dir}/favicon.png" ]; then
            echo "phase2:${static_dir}"
            return 0
        fi
    fi

    # Check Phase 1 (branding directory)
    if [ -d "$branding_dir" ]; then
        # Check if directory has branding files
        if [ -f "${branding_dir}/logo.png" ] || [ -f "${branding_dir}/favicon.png" ]; then
            echo "phase1:${branding_dir}"
            return 0
        fi
    fi

    return 1
}

# Inject branding for a container
inject_branding() {
    local container_name="$1"
    local client_id=$(get_client_id "$container_name")

    log_info "Detected healthy container: $container_name"

    # Check if branding exists and get deployment mode
    local branding_info
    if ! branding_info=$(has_branding "$client_id"); then
        log_info "No branding configured for $client_id, skipping"
        return 0
    fi

    # Parse mode and path
    local mode="${branding_info%%:*}"
    local branding_path="${branding_info#*:}"

    log_info "Detected deployment mode: $mode"

    if [ "$mode" = "phase2" ]; then
        # Phase 2: Volume-mounted static directory - no injection needed
        log_info "Phase 2 deployment detected for $client_id"
        log_info "Branding directory: $branding_path (volume-mounted)"
        log_success "Branding persists automatically via volume mount - no injection needed"

        # Log a reminder about Cloudflare cache
        log_warning "REMINDER: If using Cloudflare, purge cache for custom branding to appear"
        log_info "Cloudflare purge: Zone → Caching → Purge Everything or Purge by URL"
        return 0
    fi

    # Phase 1: Requires injection
    log_info "Phase 1 deployment detected - injecting branding for $client_id from $branding_path"

    # Run injection script
    if bash "$INJECTION_SCRIPT" "$container_name" "$client_id" "$branding_path" >> "$LOG_FILE" 2>&1; then
        log_success "Branding injected successfully for $container_name"

        # Log a reminder about Cloudflare cache
        log_warning "REMINDER: If using Cloudflare, purge cache for custom branding to appear"
        log_info "Cloudflare purge: Zone → Caching → Purge Everything or Purge by URL"
    else
        log_error "Failed to inject branding for $container_name"
        return 1
    fi
}

# Process health status event
process_health_event() {
    local container_name="$1"
    local health_status="$2"

    # Only process Open WebUI containers
    if [[ ! "$container_name" =~ ^openwebui- ]]; then
        return 0
    fi

    # Only inject when container becomes healthy
    if [ "$health_status" = "healthy" ]; then
        # Add small delay to ensure container is fully ready
        sleep 3
        inject_branding "$container_name"
    fi
}

# Monitor Docker events
monitor_events() {
    log_info "Starting Open WebUI branding monitor"
    log_info "Monitoring Docker events for health status changes..."
    log_info "Injection script: $INJECTION_SCRIPT"
    log_info "Base directory: $OPENWEBUI_BASE"
    log_info ""

    # Listen to Docker events for health status changes
    # Note: The 'health_status' event has status in Action field, not Attributes
    # Format: timestamp container_name action (where action = "health_status: healthy")
    docker events --filter 'type=container' --filter 'event=health_status' \
        --format '{{.Time}} {{.Actor.Attributes.name}} {{.Action}}' |
    while read -r timestamp container_name action; do
        # Extract health status from action (format: "health_status: healthy")
        local health_status=$(echo "$action" | awk '{print $NF}')
        process_health_event "$container_name" "$health_status"
    done
}

# Handle termination signals gracefully
cleanup() {
    log_info "Received termination signal, shutting down..."
    exit 0
}

trap cleanup SIGTERM SIGINT

# Main execution
main() {
    # Verify we can access Docker
    if ! docker info >/dev/null 2>&1; then
        log_error "Cannot access Docker daemon. Ensure Docker is running and user has permissions."
        exit 1
    fi

    # Check injection script exists
    check_injection_script

    # Create log file if it doesn't exist
    touch "$LOG_FILE" 2>/dev/null || {
        log_warning "Cannot write to $LOG_FILE, logging to stdout only"
        LOG_FILE="/dev/null"
    }

    # Start monitoring
    monitor_events
}

# Run main function
main "$@"
