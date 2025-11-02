#!/usr/bin/env bash
#
# inject-branding-post-startup.sh
# Inject custom branding AFTER Open WebUI container initialization
#
# Usage: ./inject-branding-post-startup.sh CONTAINER_NAME CLIENT_NAME BRANDING_SOURCE
#
# Arguments:
#   CONTAINER_NAME  - Docker container name (e.g., openwebui-acme-corp)
#   CLIENT_NAME     - Client identifier for directory path (e.g., acme-corp)
#   BRANDING_SOURCE - Directory containing custom branding files (e.g., ./branding/acme-corp)
#
# This script addresses Phase 0 finding that Open WebUI overwrites volume-mounted
# files during startup. Branding must be injected AFTER container is healthy.
#
# CRITICAL: Testing reveals branding is reset on EVERY container restart (not just recreation).
#           This script must be re-run after 'docker restart' or 'docker rm + run'.
#
# Exit codes:
#   0 - Success
#   1 - Container not found or health check failed
#   2 - Branding source directory not found
#   3 - Injection failed
#   4 - Invalid arguments

set -euo pipefail

# Parse arguments
if [ $# -ne 3 ]; then
    echo "Usage: $0 CONTAINER_NAME CLIENT_NAME BRANDING_SOURCE"
    echo "Example: $0 openwebui-acme-corp acme-corp ./branding/acme-corp"
    exit 4
fi

CONTAINER_NAME="$1"
CLIENT_NAME="$2"
BRANDING_SOURCE="$3"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Wait for container to reach healthy status
wait_for_healthy() {
    local max_wait=120
    local elapsed=0

    log_info "Waiting for $CONTAINER_NAME to become healthy..."

    while [ $elapsed -lt $max_wait ]; do
        # Check if container exists
        if ! docker ps --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            log_error "Container $CONTAINER_NAME not found"
            return 1
        fi

        # Check health status
        local health_status=$(docker inspect "$CONTAINER_NAME" --format '{{.State.Health.Status}}' 2>/dev/null || echo "none")

        if [ "$health_status" = "healthy" ]; then
            log_success "Container is healthy (elapsed: ${elapsed}s)"
            return 0
        elif [ "$health_status" = "unhealthy" ]; then
            log_error "Container is unhealthy"
            return 1
        fi

        # Show progress
        if [ $((elapsed % 10)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            log_info "Still waiting... (${elapsed}s elapsed, health: $health_status)"
        fi

        sleep 2
        elapsed=$((elapsed + 2))
    done

    log_error "Container did not become healthy within ${max_wait}s"
    return 1
}

# Validate branding source directory
validate_branding_source() {
    log_info "Validating branding source: $BRANDING_SOURCE"

    if [ ! -d "$BRANDING_SOURCE" ]; then
        log_error "Branding source directory not found: $BRANDING_SOURCE"
        return 2
    fi

    # Check for required files
    local required_files=(
        "favicon.png"
        "logo.png"
    )

    local missing_files=()
    for file in "${required_files[@]}"; do
        if [ ! -f "$BRANDING_SOURCE/$file" ]; then
            missing_files+=("$file")
        fi
    done

    if [ ${#missing_files[@]} -gt 0 ]; then
        log_warning "Missing recommended files: ${missing_files[*]}"
        log_warning "These files will not be replaced"
    fi

    log_success "Branding source validated"
    return 0
}

# Inject branding to volume-mounted directory AND container build directories
inject_branding() {
    local client_static="/opt/openwebui/${CLIENT_NAME}/static"

    log_info "Injecting branding to: $client_static"

    # Verify target directory exists
    if [ ! -d "$client_static" ]; then
        log_error "Client static directory not found: $client_static"
        log_error "Ensure container was started with volume mount: -v $client_static:/app/backend/open_webui/static"
        return 3
    fi

    # Count files to inject
    local inject_count=0

    # Branding files to copy
    local branding_files=(
        "favicon.png"
        "favicon.ico"
        "favicon.svg"
        "favicon-96x96.png"
        "favicon-dark.png"
        "logo.png"
        "apple-touch-icon.png"
        "splash.png"
        "splash-dark.png"
        "web-app-manifest-192x192.png"
        "web-app-manifest-512x512.png"
    )

    # Copy to host-mounted static directory
    for file in "${branding_files[@]}"; do
        if [ -f "$BRANDING_SOURCE/$file" ]; then
            cp -f "$BRANDING_SOURCE/$file" "$client_static/"
            inject_count=$((inject_count + 1))
            log_info "  ✓ $file (host)"
        fi
    done

    # CRITICAL: Also copy to container's /app/build/static/ (where web server actually serves from)
    log_info ""
    log_info "Injecting to container build directories..."
    local build_inject_count=0

    for file in "${branding_files[@]}"; do
        if [ -f "$BRANDING_SOURCE/$file" ]; then
            # Copy to /app/build/static/
            if docker cp "$BRANDING_SOURCE/$file" "$CONTAINER_NAME:/app/build/static/$file" 2>/dev/null; then
                build_inject_count=$((build_inject_count + 1))
                log_info "  ✓ $file (build)"
            fi
            # Also copy logo.png and favicon.png to /app/build/ root
            if [[ "$file" == "logo.png" ]] || [[ "$file" == "favicon.png" ]]; then
                docker cp "$BRANDING_SOURCE/$file" "$CONTAINER_NAME:/app/build/$file" 2>/dev/null
            fi
        fi
    done

    if [ $inject_count -eq 0 ]; then
        log_warning "No branding files were injected to host"
        return 3
    fi

    log_success "Injected $inject_count file(s) to host, $build_inject_count file(s) to container build"
    return 0
}

# Verify branding applied
verify_branding() {
    local client_static="/opt/openwebui/${CLIENT_NAME}/static"

    log_info "Verifying branding in container..."

    # Check if files are accessible in container
    if docker exec "$CONTAINER_NAME" ls -la /app/backend/open_webui/static/favicon.png &>/dev/null; then
        local size=$(docker exec "$CONTAINER_NAME" stat -c %s /app/backend/open_webui/static/favicon.png 2>/dev/null)
        log_info "Container favicon.png: $size bytes"
        log_success "Branding files accessible in container"
    else
        log_warning "Could not verify branding in container"
    fi
}

# Main execution
main() {
    log_info "Open WebUI Post-Startup Branding Injection"
    log_info "==========================================="
    log_info ""
    log_info "Container: $CONTAINER_NAME"
    log_info "Client: $CLIENT_NAME"
    log_info "Branding Source: $BRANDING_SOURCE"
    log_info ""

    # Step 1: Wait for container to be healthy
    if ! wait_for_healthy; then
        exit 1
    fi

    log_info ""

    # Step 2: Validate branding source
    if ! validate_branding_source; then
        exit 2
    fi

    log_info ""

    # Step 3: Inject branding
    if ! inject_branding; then
        exit 3
    fi

    log_info ""

    # Step 4: Verify branding
    verify_branding

    log_info ""
    log_success "Branding injection complete!"
    log_info ""
    log_info "Next steps:"
    log_info "1. Access the web UI to verify branding"
    log_info "2. To update branding, run this script again"
    log_info ""
    log_warning "CRITICAL: Branding WILL BE RESET on container restart!"
    log_warning "          Open WebUI overwrites volume-mounted files during initialization"
    log_warning "          Re-run this script after EVERY 'docker restart' or container recreation"
}

# Run main function
main "$@"
