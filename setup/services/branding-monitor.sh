#!/usr/bin/env bash
#
# branding-monitor.sh
# Monitors Docker containers and auto-injects branding when they become healthy
#
# Usage: ./branding-monitor.sh
#
# This service listens to Docker events and automatically runs the branding
# injection script when Open WebUI containers transition to "healthy" state.
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
OPENWEBUI_BASE="/opt/openwebui"
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

# Check if container has branding directory
has_branding() {
    local client_id="$1"
    local branding_dir="${OPENWEBUI_BASE}/${client_id}/branding"

    if [ -d "$branding_dir" ]; then
        # Check if directory has branding files
        if [ -f "${branding_dir}/logo.png" ] || [ -f "${branding_dir}/favicon.png" ]; then
            return 0
        fi
    fi
    return 1
}

# Inject branding for a container
inject_branding() {
    local container_name="$1"
    local client_id=$(get_client_id "$container_name")
    local branding_dir="${OPENWEBUI_BASE}/${client_id}/branding"

    log_info "Detected healthy container: $container_name"

    # Check if branding exists
    if ! has_branding "$client_id"; then
        log_info "No branding configured for $client_id, skipping"
        return 0
    fi

    log_info "Injecting branding for $client_id from $branding_dir"

    # Run injection script
    if bash "$INJECTION_SCRIPT" "$container_name" "$client_id" "$branding_dir" >> "$LOG_FILE" 2>&1; then
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
