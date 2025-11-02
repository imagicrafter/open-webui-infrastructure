#!/usr/bin/env bash
#
# extract-default-static.sh
# Extract default static assets from Open WebUI Docker image
#
# Usage: ./extract-default-static.sh [IMAGE] [TARGET_DIR]
#
# Arguments:
#   IMAGE       - Docker image to extract from (default: ghcr.io/open-webui/open-webui:main)
#   TARGET_DIR  - Directory to extract assets to (default: /opt/openwebui/defaults/static)
#
# This script creates a temporary container, extracts static assets, and cleans up.
# It's idempotent and safe to run multiple times.
#
# Exit codes:
#   0 - Success
#   1 - Docker not available
#   2 - Image pull failed
#   3 - Extraction failed
#   4 - Invalid arguments

set -euo pipefail

# Default values
DEFAULT_IMAGE="${OPENWEBUI_IMAGE:-ghcr.io/open-webui/open-webui:main}"
DEFAULT_TARGET_DIR="/opt/openwebui/defaults/static"

# Parse arguments
IMAGE="${1:-$DEFAULT_IMAGE}"
TARGET_DIR="${2:-$DEFAULT_TARGET_DIR}"

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

# Cleanup function
cleanup() {
    if [ -n "${TEMP_CONTAINER:-}" ]; then
        log_info "Cleaning up temporary container: $TEMP_CONTAINER"
        docker stop "$TEMP_CONTAINER" &>/dev/null || true
        docker rm "$TEMP_CONTAINER" &>/dev/null || true
    fi
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Main execution
main() {
    log_info "Open WebUI Default Asset Extractor"
    log_info "==================================="
    log_info ""
    log_info "Image: $IMAGE"
    log_info "Target: $TARGET_DIR"
    log_info ""

    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi

    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi

    # Check if target directory already exists and has files
    if [ -d "$TARGET_DIR" ] && [ "$(ls -A "$TARGET_DIR" 2>/dev/null)" ]; then
        log_warning "Target directory already exists and contains files"
        read -p "Overwrite existing files? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Extraction cancelled"
            exit 0
        fi
    fi

    # Create target directory
    log_info "Creating target directory..."
    mkdir -p "$TARGET_DIR" || {
        log_error "Failed to create directory: $TARGET_DIR"
        exit 3
    }

    # Pull the image
    log_info "Pulling Docker image..."
    if ! docker pull "$IMAGE"; then
        log_error "Failed to pull image: $IMAGE"
        exit 2
    fi

    # Create temporary container
    log_info "Creating temporary container..."
    TEMP_CONTAINER="temp-extract-$(date +%s)"

    if ! docker run -d --name "$TEMP_CONTAINER" "$IMAGE" sleep 3600; then
        log_error "Failed to create temporary container"
        exit 3
    fi

    log_success "Temporary container created: $TEMP_CONTAINER"

    # Wait a moment for container to be ready
    sleep 2

    # Extract static assets
    log_info "Extracting static assets from /app/backend/open_webui/static/..."

    if ! docker cp "$TEMP_CONTAINER:/app/backend/open_webui/static/." "$TARGET_DIR/"; then
        log_error "Failed to extract static assets"
        exit 3
    fi

    # Count extracted files
    FILE_COUNT=$(find "$TARGET_DIR" -type f | wc -l | tr -d ' ')
    DIR_COUNT=$(find "$TARGET_DIR" -type d | wc -l | tr -d ' ')

    log_success "Extracted $FILE_COUNT files in $DIR_COUNT directories"

    # List key files to verify extraction
    log_info ""
    log_info "Key files extracted:"

    KEY_FILES=(
        "favicon.png"
        "logo.png"
        "favicon.ico"
        "favicon.svg"
        "apple-touch-icon.png"
    )

    for file in "${KEY_FILES[@]}"; do
        if [ -f "$TARGET_DIR/$file" ]; then
            SIZE=$(ls -lh "$TARGET_DIR/$file" | awk '{print $5}')
            echo -e "  ${GREEN}✓${NC} $file ($SIZE)"
        else
            echo -e "  ${RED}✗${NC} $file (missing)"
        fi
    done

    # Check subdirectories
    log_info ""
    log_info "Subdirectories:"

    KEY_DIRS=(
        "assets"
        "fonts"
        "swagger-ui"
    )

    for dir in "${KEY_DIRS[@]}"; do
        if [ -d "$TARGET_DIR/$dir" ]; then
            COUNT=$(find "$TARGET_DIR/$dir" -type f | wc -l | tr -d ' ')
            echo -e "  ${GREEN}✓${NC} $dir/ ($COUNT files)"
        else
            echo -e "  ${RED}✗${NC} $dir/ (missing)"
        fi
    done

    log_info ""
    log_success "Static asset extraction complete!"
    log_info "Assets available at: $TARGET_DIR"

    # Provide usage hint
    log_info ""
    log_info "Next steps:"
    log_info "1. Copy these defaults to client directories:"
    log_info "   cp -a $TARGET_DIR/. /opt/openwebui/<client>/static/"
    log_info ""
    log_info "2. Replace assets with custom branding"
    log_info ""
    log_info "3. Mount the static directory when starting container:"
    log_info "   -v /opt/openwebui/<client>/static:/app/backend/open_webui/static"
}

# Run main function
main "$@"
