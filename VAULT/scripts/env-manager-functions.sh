#!/bin/bash

# Environment Variable Management Functions
# For managing custom per-deployment environment variables

# Configuration
CUSTOM_ENV_DIR="/opt/openwebui-configs"

# ============================================================================
# CORE FUNCTIONS
# ============================================================================

# Ensure custom env directory exists
ensure_custom_env_dir() {
    if [ ! -d "$CUSTOM_ENV_DIR" ]; then
        echo "Creating custom environment directory..."
        sudo mkdir -p "$CUSTOM_ENV_DIR" 2>/dev/null || mkdir -p "$CUSTOM_ENV_DIR" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "❌ Failed to create directory: $CUSTOM_ENV_DIR"
            echo "   You may need sudo privileges"
            return 1
        fi
        sudo chmod 755 "$CUSTOM_ENV_DIR" 2>/dev/null || chmod 755 "$CUSTOM_ENV_DIR" 2>/dev/null
    fi
    return 0
}

# Get custom env file path for a container
get_custom_env_file() {
    local container_name="$1"
    echo "${CUSTOM_ENV_DIR}/${container_name}.env"
}

# Check if custom env file exists
has_custom_env_file() {
    local container_name="$1"
    local env_file=$(get_custom_env_file "$container_name")
    [ -f "$env_file" ]
}

# Count custom variables (exclude comments and empty lines)
count_custom_vars() {
    local container_name="$1"
    local env_file=$(get_custom_env_file "$container_name")

    if [ ! -f "$env_file" ]; then
        echo "0"
        return
    fi

    grep -v '^[[:space:]]*#' "$env_file" | grep -v '^[[:space:]]*$' | wc -l | tr -d ' '
}

# Create empty custom env file with template
create_custom_env_file() {
    local container_name="$1"
    local env_file=$(get_custom_env_file "$container_name")

    cat << 'EOF' | sudo tee "$env_file" > /dev/null
# Custom Environment Variables for Open WebUI Deployment
#
# This file contains deployment-specific environment variables.
# Standard variables (OAuth, domain, etc.) are managed by client-manager.sh
#
# Format: VARIABLE_NAME=value (no spaces around =)
# Comments start with #
#
# Example Google Cloud Integration:
# GOOGLE_DRIVE_CLIENT_ID=your-client-id
# GOOGLE_DRIVE_CLIENT_SECRET=your-client-secret
# GOOGLE_MAPS_API_KEY=your-api-key
# GMAIL_API_CREDENTIALS=your-credentials
#
# Example OpenAI Integration:
# OPENAI_API_KEY=sk-your-key
# OPENAI_API_BASE=https://api.openai.com/v1
#
# Example Anthropic Integration:
# ANTHROPIC_API_KEY=sk-ant-your-key
#
# Add your custom variables below:
# ================================================

EOF

    if [ $? -eq 0 ]; then
        sudo chmod 600 "$env_file" 2>/dev/null || chmod 600 "$env_file" 2>/dev/null
        return 0
    else
        return 1
    fi
}

# Get a specific variable value from env file
get_env_var() {
    local container_name="$1"
    local var_name="$2"
    local env_file=$(get_custom_env_file "$container_name")

    if [ ! -f "$env_file" ]; then
        return 1
    fi

    # Extract value for key (skip comments and empty lines)
    grep "^${var_name}=" "$env_file" | head -1 | cut -d'=' -f2-
}

# Set or update a variable in env file
set_env_var() {
    local container_name="$1"
    local var_name="$2"
    local var_value="$3"
    local env_file=$(get_custom_env_file "$container_name")

    # Create file if doesn't exist
    if [ ! -f "$env_file" ]; then
        if ! ensure_custom_env_dir; then
            return 1
        fi
        create_custom_env_file "$container_name"
    fi

    # Check if key exists
    if grep -q "^${var_name}=" "$env_file" 2>/dev/null; then
        # Update existing key (using sed for in-place replacement)
        if [ "$(uname)" = "Darwin" ]; then
            # macOS sed syntax
            sed -i '' "s|^${var_name}=.*|${var_name}=${var_value}|" "$env_file"
        else
            # Linux sed syntax
            sed -i "s|^${var_name}=.*|${var_name}=${var_value}|" "$env_file"
        fi
    else
        # Append new key
        echo "${var_name}=${var_value}" | sudo tee -a "$env_file" > /dev/null
    fi
}

# Delete a variable from env file
delete_env_var() {
    local container_name="$1"
    local var_name="$2"
    local env_file=$(get_custom_env_file "$container_name")

    if [ ! -f "$env_file" ]; then
        return 0
    fi

    # Remove the line with this key
    if [ "$(uname)" = "Darwin" ]; then
        # macOS sed syntax
        sed -i '' "/^${var_name}=/d" "$env_file"
    else
        # Linux sed syntax
        sed -i "/^${var_name}=/d" "$env_file"
    fi
}

# List all variable names (keys only)
list_env_var_names() {
    local container_name="$1"
    local env_file=$(get_custom_env_file "$container_name")

    if [ ! -f "$env_file" ]; then
        return 0
    fi

    # Return just the keys (skip comments and empty lines)
    grep -v '^[[:space:]]*#' "$env_file" | grep -v '^[[:space:]]*$' | cut -d'=' -f1
}

# Validate env file format
validate_env_file() {
    local container_name="$1"
    local env_file=$(get_custom_env_file "$container_name")
    local line_num=0
    local errors=0

    if [ ! -f "$env_file" ]; then
        return 0  # No file is valid (no custom vars)
    fi

    while IFS= read -r line; do
        ((line_num++))

        # Skip empty lines and comments
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        # Check for valid KEY=VALUE format
        if [[ ! "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*=.*$ ]]; then
            echo "⚠️  Line $line_num: Invalid format - '$line'"
            echo "   Expected: VARIABLE_NAME=value"
            ((errors++))
        fi
    done < "$env_file"

    if [ $errors -gt 0 ]; then
        echo ""
        echo "Found $errors validation error(s)"
        return 1
    else
        echo "✅ Environment file validation passed"
        return 0
    fi
}

# Export functions
export -f ensure_custom_env_dir
export -f get_custom_env_file
export -f has_custom_env_file
export -f count_custom_vars
export -f create_custom_env_file
export -f get_env_var
export -f set_env_var
export -f delete_env_var
export -f list_env_var_names
export -f validate_env_file
