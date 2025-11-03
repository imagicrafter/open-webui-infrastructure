#!/usr/bin/env bash
# =============================================================================
# Configuration Loading Library
# =============================================================================
# This library provides functions for loading and managing configuration
# across all infrastructure scripts.
#
# Usage:
#   source "$(dirname "$0")/setup/lib/config.sh"
#   load_global_config
# =============================================================================

# -----------------------------------------------------------------------------
# Find Repository Root
# -----------------------------------------------------------------------------
# Finds the repository root by looking for config/global.conf
find_repo_root() {
    local current_dir="$(pwd)"
    local search_dir="$current_dir"

    # Search up the directory tree for config/global.conf
    while [ "$search_dir" != "/" ]; do
        if [ -f "$search_dir/config/global.conf" ]; then
            echo "$search_dir"
            return 0
        fi
        search_dir="$(dirname "$search_dir")"
    done

    # Also check the script's directory and its parent
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    search_dir="$script_dir"

    while [ "$search_dir" != "/" ]; do
        if [ -f "$search_dir/config/global.conf" ]; then
            echo "$search_dir"
            return 0
        fi
        search_dir="$(dirname "$search_dir")"
    done

    # Not found
    echo "ERROR: Could not find repository root (config/global.conf not found)" >&2
    return 1
}

# -----------------------------------------------------------------------------
# Load Global Configuration
# -----------------------------------------------------------------------------
# Loads config/global.conf from the repository root
load_global_config() {
    # Find repository root
    REPO_ROOT="$(find_repo_root)"
    if [ $? -ne 0 ]; then
        echo "ERROR: Cannot load configuration - repository root not found" >&2
        return 1
    fi

    export REPO_ROOT

    # Load global configuration
    local config_file="${REPO_ROOT}/config/global.conf"
    if [ ! -f "$config_file" ]; then
        echo "ERROR: Configuration file not found: $config_file" >&2
        return 1
    fi

    # Source the configuration
    source "$config_file"

    return 0
}

# -----------------------------------------------------------------------------
# Load Client-Specific Configuration
# -----------------------------------------------------------------------------
# Loads configuration specific to a client deployment
# Arguments:
#   $1: Client name
load_client_config() {
    local client_name="$1"

    if [ -z "$client_name" ]; then
        echo "ERROR: Client name required" >&2
        return 1
    fi

    # Ensure global config is loaded first
    if [ -z "$REPO_ROOT" ]; then
        load_global_config || return 1
    fi

    # Check if client directory exists
    local client_dir="${BASE_DIR}/${client_name}"
    if [ ! -d "$client_dir" ]; then
        echo "WARNING: Client directory not found: $client_dir" >&2
        return 1
    fi

    # Load client-specific .env if it exists
    local client_env="${client_dir}/.env"
    if [ -f "$client_env" ]; then
        set -a  # Auto-export variables
        source "$client_env"
        set +a
        echo "✓ Loaded client configuration: $client_env"
    fi

    # Export client-specific variables
    export CLIENT_NAME="$client_name"
    export CLIENT_DIR="$client_dir"
    export CLIENT_DATA_DIR="${client_dir}/data"
    export CLIENT_STATIC_DIR="${client_dir}/static"

    return 0
}

# -----------------------------------------------------------------------------
# Validate Required Configuration
# -----------------------------------------------------------------------------
# Validates that all required configuration variables are set
# Returns 0 if valid, 1 if validation fails
validate_required_config() {
    local errors=0

    # Check if global config is loaded
    if [ -z "$REPO_ROOT" ]; then
        echo "ERROR: Global configuration not loaded (call load_global_config first)" >&2
        ((errors++))
    fi

    # Validate using the function from global.conf
    if declare -f validate_config > /dev/null; then
        validate_config || ((errors++))
    fi

    return $errors
}

# -----------------------------------------------------------------------------
# Show Current Configuration
# -----------------------------------------------------------------------------
# Displays the current configuration state
show_current_config() {
    if declare -f show_config > /dev/null; then
        show_config
    else
        echo "ERROR: show_config function not available (global config not loaded?)" >&2
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Set Image Version
# -----------------------------------------------------------------------------
# Helper function to set the Open WebUI image version
# Arguments:
#   $1: Image tag (latest, main, v0.5.1, etc.)
set_image_version() {
    local version="$1"

    if [ -z "$version" ]; then
        echo "ERROR: Image version required" >&2
        echo "Usage: set_image_version <version>" >&2
        echo "Examples: latest, main, v0.5.1" >&2
        return 1
    fi

    export OPENWEBUI_IMAGE_TAG="$version"
    export OPENWEBUI_FULL_IMAGE="${OPENWEBUI_IMAGE}:${OPENWEBUI_IMAGE_TAG}"

    echo "✓ Image version set to: $OPENWEBUI_FULL_IMAGE"
    return 0
}

# -----------------------------------------------------------------------------
# Get Client Container Name
# -----------------------------------------------------------------------------
# Constructs the container name for a client
# Arguments:
#   $1: Client name
get_container_name() {
    local client_name="$1"

    if [ -z "$client_name" ]; then
        echo "ERROR: Client name required" >&2
        return 1
    fi

    echo "openwebui-${client_name}"
    return 0
}

# -----------------------------------------------------------------------------
# Check if Container Exists
# -----------------------------------------------------------------------------
# Checks if a container exists for the given client
# Arguments:
#   $1: Client name or container name
container_exists() {
    local name="$1"

    if [ -z "$name" ]; then
        return 1
    fi

    # Check if it's already a container name
    if [[ "$name" == openwebui-* ]]; then
        docker ps -a --format '{{.Names}}' | grep -q "^${name}$"
        return $?
    else
        # Assume it's a client name
        local container_name="$(get_container_name "$name")"
        docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"
        return $?
    fi
}

# -----------------------------------------------------------------------------
# Check if Container is Running
# -----------------------------------------------------------------------------
# Checks if a container is currently running
# Arguments:
#   $1: Client name or container name
container_is_running() {
    local name="$1"

    if [ -z "$name" ]; then
        return 1
    fi

    # Check if it's already a container name
    if [[ "$name" == openwebui-* ]]; then
        docker ps --format '{{.Names}}' | grep -q "^${name}$"
        return $?
    else
        # Assume it's a client name
        local container_name="$(get_container_name "$name")"
        docker ps --format '{{.Names}}' | grep -q "^${container_name}$"
        return $?
    fi
}

# -----------------------------------------------------------------------------
# Get Client Directory Structure
# -----------------------------------------------------------------------------
# Returns information about a client's directory structure
# Arguments:
#   $1: Client name
get_client_info() {
    local client_name="$1"

    if [ -z "$client_name" ]; then
        echo "ERROR: Client name required" >&2
        return 1
    fi

    local client_dir="${BASE_DIR}/${client_name}"
    local data_dir="${client_dir}/data"
    local static_dir="${client_dir}/static"
    local container_name="$(get_container_name "$client_name")"

    echo "Client: $client_name"
    echo "  Directory:   $client_dir"
    echo "  Data:        $data_dir"
    echo "  Static:      $static_dir"
    echo "  Container:   $container_name"

    if container_exists "$client_name"; then
        echo "  Status:      $(container_is_running "$client_name" && echo "Running" || echo "Stopped")"
    else
        echo "  Status:      Not deployed"
    fi

    return 0
}

# -----------------------------------------------------------------------------
# Initialize Client Directory
# -----------------------------------------------------------------------------
# Creates the directory structure for a new client
# Arguments:
#   $1: Client name
init_client_directory() {
    local client_name="$1"

    if [ -z "$client_name" ]; then
        echo "ERROR: Client name required" >&2
        return 1
    fi

    local client_dir="${BASE_DIR}/${client_name}"
    local data_dir="${client_dir}/data"
    local static_dir="${client_dir}/static"

    # Create directories
    echo "Initializing client directory: $client_dir"

    mkdir -p "$data_dir" || {
        echo "ERROR: Failed to create data directory: $data_dir" >&2
        return 1
    }

    mkdir -p "$static_dir" || {
        echo "ERROR: Failed to create static directory: $static_dir" >&2
        return 1
    }

    # Extract default static assets from the Open WebUI image
    # Uses OPENWEBUI_IMAGE_TAG set by client-manager.sh during deployment
    echo "Extracting default static assets from Open WebUI image..."
    echo "  Image: ${OPENWEBUI_IMAGE:-ghcr.io/open-webui/open-webui}:${OPENWEBUI_IMAGE_TAG:-latest}"

    # Find the extract script
    local extract_script="${REPO_ROOT}/setup/lib/extract-default-static.sh"

    if [ ! -f "$extract_script" ]; then
        echo "ERROR: extract-default-static.sh not found at: $extract_script" >&2
        return 1
    fi

    # Extract directly to client's static directory
    if bash "$extract_script" "${OPENWEBUI_IMAGE:-ghcr.io/open-webui/open-webui}:${OPENWEBUI_IMAGE_TAG:-latest}" "$static_dir"; then
        echo "✓ Static assets extracted from image"
    else
        echo "ERROR: Failed to extract static assets" >&2
        return 1
    fi

    # Set permissions
    chmod 755 "$client_dir" || true
    chmod 755 "$data_dir" || true
    chmod 755 "$static_dir" || true

    echo "✓ Client directory initialized: $client_dir"
    return 0
}

# -----------------------------------------------------------------------------
# Export Functions
# -----------------------------------------------------------------------------
# Make functions available to scripts that source this library
export -f find_repo_root
export -f load_global_config
export -f load_client_config
export -f validate_required_config
export -f show_current_config
export -f set_image_version
export -f get_container_name
export -f container_exists
export -f container_is_running
export -f get_client_info
export -f init_client_directory
