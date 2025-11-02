#!/bin/bash

# Environment Variable Management Menu
# This provides an interactive menu for managing custom environment variables

# Note: This file is meant to be sourced by client-manager.sh
# env-manager-functions.sh should already be sourced before this file

# ============================================================================
# MAIN ENV MANAGEMENT MENU
# ============================================================================

env_management_menu() {
    local container_name="$1"
    local env_file=$(get_custom_env_file "$container_name")

    # Ensure directory exists
    if ! ensure_custom_env_dir; then
        echo "Press Enter to continue..."
        read
        return
    fi

    while true; do
        clear
        echo "╔════════════════════════════════════════╗"
        echo "║         Env Management                 ║"
        echo "╚════════════════════════════════════════╝"
        echo
        echo "Container: $container_name"
        echo "Env File:  $env_file"
        echo

        # Check if file exists and show status
        if [ -f "$env_file" ]; then
            local var_count=$(count_custom_vars "$container_name")
            echo "Status: ✅ Custom env file exists ($var_count variable(s))"
        else
            echo "Status: ⚠️  No custom env file (using defaults only)"
        fi

        echo
        echo "1) View All Custom Variables"
        echo "2) Create/Update Variable"
        echo "3) Delete Variable"
        echo "4) View Raw Env File"
        echo "5) Edit Env File (Advanced)"
        echo "6) Validate Env File"
        echo "7) Apply Changes (Recreate Container)"
        echo "8) Delete All Custom Variables"
        echo "9) Return to Deployment Menu"
        echo
        echo -n "Select action (1-9): "
        read action

        case "$action" in
            1)
                # View All Custom Variables
                view_all_custom_variables "$container_name"
                ;;
            2)
                # Create/Update Variable
                create_update_variable "$container_name"
                ;;
            3)
                # Delete Variable
                delete_variable_interactive "$container_name"
                ;;
            4)
                # View Raw Env File
                view_raw_env_file "$container_name"
                ;;
            5)
                # Edit Env File (Advanced)
                edit_env_file_advanced "$container_name"
                ;;
            6)
                # Validate Env File
                validate_env_file_interactive "$container_name"
                ;;
            7)
                # Apply Changes (Recreate Container)
                apply_env_changes "$container_name"
                ;;
            8)
                # Delete All Custom Variables
                delete_all_custom_variables "$container_name"
                ;;
            9)
                # Return to Deployment Menu
                return
                ;;
            *)
                echo "Invalid selection. Press Enter to continue..."
                read
                ;;
        esac
    done
}

# ============================================================================
# MENU ACTION FUNCTIONS
# ============================================================================

view_all_custom_variables() {
    local container_name="$1"
    local env_file=$(get_custom_env_file "$container_name")

    clear
    echo "╔════════════════════════════════════════╗"
    echo "║      All Custom Variables              ║"
    echo "╚════════════════════════════════════════╝"
    echo
    echo "Container: $container_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    if [ ! -f "$env_file" ]; then
        echo "No custom variables defined."
        echo
        echo "Use option 2 to create your first variable."
    else
        local var_names=$(list_env_var_names "$container_name")

        if [ -z "$var_names" ]; then
            echo "No custom variables defined."
            echo
            echo "The env file exists but contains no variables."
        else
            echo "Current custom variables:"
            echo

            local count=1
            for var_name in $var_names; do
                local var_value=$(get_env_var "$container_name" "$var_name")
                # Mask value for security (show first 4 chars + asterisks)
                local masked_value="${var_value:0:4}********"
                if [ ${#var_value} -lt 4 ]; then
                    masked_value="********"
                fi
                echo "  $count) $var_name = $masked_value"
                ((count++))
            done
        fi
    fi

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "Standard variables (managed by client-manager.sh):"
    echo "  - GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET"
    echo "  - OAUTH_ALLOWED_DOMAINS, GOOGLE_REDIRECT_URI"
    echo "  - WEBUI_NAME, WEBUI_SECRET_KEY, FQDN"
    echo "  - CLIENT_NAME, DATABASE_URL (if PostgreSQL)"
    echo
    echo "These are set via docker -e flags and NOT shown above."
    echo
    echo "Press Enter to continue..."
    read
}

create_update_variable() {
    local container_name="$1"

    clear
    echo "╔════════════════════════════════════════╗"
    echo "║       Create/Update Variable           ║"
    echo "╚════════════════════════════════════════╝"
    echo

    # Show existing variables for reference
    local var_count=$(count_custom_vars "$container_name")
    if [ "$var_count" -gt 0 ]; then
        echo "Existing variables (for reference):"
        local var_names=$(list_env_var_names "$container_name")
        for var_name in $var_names; do
            echo "  - $var_name"
        done
        echo
    fi

    echo "Enter variable name (e.g., GOOGLE_DRIVE_CLIENT_ID)"
    echo "  - Must start with letter or underscore"
    echo "  - Can contain letters, numbers, underscores"
    echo "  - Use UPPERCASE by convention"
    echo
    echo -n "Variable name (or 'cancel' to abort): "
    read var_name

    # Check for cancel
    if [[ "$var_name" == "cancel" ]] || [[ -z "$var_name" ]]; then
        echo
        echo "Operation cancelled."
        echo "Press Enter to continue..."
        read
        return
    fi

    # Validate variable name
    if [[ ! "$var_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        echo
        echo "❌ Invalid variable name!"
        echo
        echo "Variable names must:"
        echo "  - Start with letter or underscore"
        echo "  - Contain only letters, numbers, underscores"
        echo
        echo "Examples:"
        echo "  ✅ GOOGLE_DRIVE_CLIENT_ID"
        echo "  ✅ OPENAI_API_KEY"
        echo "  ✅ CUSTOM_VAR_1"
        echo "  ❌ 123_VAR (starts with number)"
        echo "  ❌ MY-VAR (contains hyphen)"
        echo
        echo "Press Enter to continue..."
        read
        return
    fi

    # Check if variable already exists
    local existing_value=$(get_env_var "$container_name" "$var_name")
    if [ -n "$existing_value" ]; then
        echo
        echo "⚠️  Variable '$var_name' already exists"
        echo "   Current value: ${existing_value:0:4}********"
        echo
        echo "Do you want to update it? (y/N): "
        read confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo
            echo "Operation cancelled."
            echo "Press Enter to continue..."
            read
            return
        fi
        echo
    fi

    # Get variable value
    echo "Enter variable value:"
    echo "  - Can contain any characters"
    echo "  - Will be stored in plain text (use quotes if needed)"
    echo
    echo -n "Variable value: "
    read -r var_value

    if [ -z "$var_value" ]; then
        echo
        echo "❌ Variable value cannot be empty"
        echo
        echo "Press Enter to continue..."
        read
        return
    fi

    # Confirmation
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Summary:"
    echo "  Variable: $var_name"
    echo "  Value:    ${var_value:0:20}..."
    if [ -n "$existing_value" ]; then
        echo "  Action:   UPDATE existing variable"
    else
        echo "  Action:   CREATE new variable"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo -n "Confirm? (y/N): "
    read confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if set_env_var "$container_name" "$var_name" "$var_value"; then
            echo
            echo "✅ Variable saved successfully!"
            echo
            echo "⚠️  IMPORTANT: Changes will take effect after container recreation"
            echo "   Use option 7 (Apply Changes) to recreate the container"
        else
            echo
            echo "❌ Failed to save variable"
        fi
    else
        echo
        echo "Operation cancelled."
    fi

    echo
    echo "Press Enter to continue..."
    read
}

delete_variable_interactive() {
    local container_name="$1"

    clear
    echo "╔════════════════════════════════════════╗"
    echo "║          Delete Variable               ║"
    echo "╚════════════════════════════════════════╝"
    echo

    # Check if any variables exist
    local var_count=$(count_custom_vars "$container_name")
    if [ "$var_count" -eq 0 ]; then
        echo "No custom variables to delete."
        echo
        echo "Press Enter to continue..."
        read
        return
    fi

    # List current variables
    echo "Current custom variables:"
    echo

    local var_names=$(list_env_var_names "$container_name")
    declare -a vars_array
    local i=1
    for var_name in $var_names; do
        vars_array[$i]="$var_name"
        local var_value=$(get_env_var "$container_name" "$var_name")
        local masked_value="${var_value:0:4}********"
        echo "  $i) $var_name = $masked_value"
        ((i++))
    done

    echo
    echo "  0) Cancel"
    echo
    echo -n "Select variable to delete (0-$((i-1))): "
    read selection

    # Check for cancel
    if [ "$selection" -eq 0 ] 2>/dev/null; then
        echo
        echo "Operation cancelled."
        echo
        echo "Press Enter to continue..."
        read
        return
    fi

    # Validate selection
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -ge "$i" ]; then
        echo
        echo "❌ Invalid selection"
        echo
        echo "Press Enter to continue..."
        read
        return
    fi

    local var_to_delete="${vars_array[$selection]}"

    # Confirmation
    echo
    echo "⚠️  You are about to delete:"
    echo "   Variable: $var_to_delete"
    echo
    echo -n "Type 'DELETE' to confirm: "
    read confirm

    if [[ "$confirm" == "DELETE" ]]; then
        if delete_env_var "$container_name" "$var_to_delete"; then
            echo
            echo "✅ Variable '$var_to_delete' deleted successfully!"
            echo
            echo "⚠️  Changes will take effect after container recreation"
            echo "   Use option 7 (Apply Changes) to recreate the container"
        else
            echo
            echo "❌ Failed to delete variable"
        fi
    else
        echo
        echo "Deletion cancelled (confirmation did not match)."
    fi

    echo
    echo "Press Enter to continue..."
    read
}

view_raw_env_file() {
    local container_name="$1"
    local env_file=$(get_custom_env_file "$container_name")

    clear
    echo "╔════════════════════════════════════════╗"
    echo "║         Raw Env File Contents          ║"
    echo "╚════════════════════════════════════════╝"
    echo
    echo "File: $env_file"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    if [ ! -f "$env_file" ]; then
        echo "# No custom env file exists"
        echo "# Use option 2 to create variables"
    else
        sudo cat "$env_file"
    fi

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "Press Enter to continue..."
    read
}

edit_env_file_advanced() {
    local container_name="$1"
    local env_file=$(get_custom_env_file "$container_name")

    clear
    echo "╔════════════════════════════════════════╗"
    echo "║       Edit Env File (Advanced)         ║"
    echo "╚════════════════════════════════════════╝"
    echo
    echo "⚠️  WARNING: Advanced feature!"
    echo
    echo "This will open the env file in a text editor."
    echo "Direct editing can introduce syntax errors."
    echo
    echo "Tips:"
    echo "  - Use KEY=VALUE format (no spaces around =)"
    echo "  - Comments start with #"
    echo "  - Save and exit when done"
    echo "  - Use option 6 to validate after editing"
    echo
    echo -n "Continue? (y/N): "
    read confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo
        echo "Operation cancelled."
        echo
        echo "Press Enter to continue..."
        read
        return
    fi

    # Create file if doesn't exist
    if [ ! -f "$env_file" ]; then
        create_custom_env_file "$container_name"
    fi

    # Determine editor
    local editor="${EDITOR:-nano}"
    if ! command -v "$editor" &> /dev/null; then
        editor="vi"
    fi

    echo
    echo "Opening $editor..."
    echo

    # Open editor
    sudo "$editor" "$env_file" 2>/dev/null || "$editor" "$env_file" 2>/dev/null

    echo
    echo "Validating changes..."
    if validate_env_file "$container_name"; then
        echo
        echo "✅ Changes saved and validated!"
        echo "⚠️  Use option 7 to apply changes (recreate container)"
    else
        echo
        echo "⚠️  Validation failed. Please fix errors before applying."
    fi

    echo
    echo "Press Enter to continue..."
    read
}

validate_env_file_interactive() {
    local container_name="$1"

    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        Validate Env File               ║"
    echo "╚════════════════════════════════════════╝"
    echo

    if ! has_custom_env_file "$container_name"; then
        echo "ℹ️  No custom env file to validate"
        echo
        echo "The file will be created when you add your first variable."
    else
        echo "Validating environment file..."
        echo
        validate_env_file "$container_name"
    fi

    echo
    echo "Press Enter to continue..."
    read
}

apply_env_changes() {
    local container_name="$1"
    local env_file=$(get_custom_env_file "$container_name")

    clear
    echo "╔════════════════════════════════════════╗"
    echo "║      Apply Changes (Recreate)          ║"
    echo "╚════════════════════════════════════════╝"
    echo

    # Validate first if env file exists
    if has_custom_env_file "$container_name"; then
        echo "Step 1: Validating environment file..."
        echo
        if ! validate_env_file "$container_name"; then
            echo
            echo "❌ Validation failed!"
            echo "   Please fix errors before applying changes."
            echo
            echo "Press Enter to continue..."
            read
            return
        fi
        echo
    else
        echo "ℹ️  No custom env file found"
        echo "   Container will be recreated without custom variables"
        echo
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  WARNING: Container Recreation Required"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "Custom environment variables are loaded at container"
    echo "creation time. To apply changes, the container must be"
    echo "recreated with the new environment file."
    echo
    echo "What will happen:"
    echo "  1. Get current container configuration"
    echo "  2. Stop container"
    echo "  3. Remove container (data volume preserved)"
    echo "  4. Recreate container with --env-file flag"
    echo "  5. Start container"
    echo
    echo "Downtime: ~10-30 seconds"
    echo "Data: Fully preserved (uses same volume)"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "⚠️  This is a CRITICAL operation!"
    echo
    echo -n "Type 'RECREATE' to confirm: "
    read confirm

    if [[ "$confirm" != "RECREATE" ]]; then
        echo
        echo "Operation cancelled (confirmation did not match)."
        echo
        echo "Press Enter to continue..."
        read
        return
    fi

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Starting container recreation..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    # This function will call a helper that needs to be in client-manager.sh
    # For now, show the message
    echo "⚠️  Container recreation must be implemented in client-manager.sh"
    echo
    echo "The recreation logic needs access to:"
    echo "  - Current OAuth settings"
    echo "  - Port configuration"
    echo "  - Network settings"
    echo "  - Database URL (if PostgreSQL)"
    echo
    echo "Please use client-manager.sh option 6 (Update OAuth domains)"
    echo "which recreates the container. Your custom env file will be"
    echo "automatically included if it exists."
    echo
    echo "Or manually recreate using docker run with:"
    echo "  --env-file $env_file"
    echo
    echo "Press Enter to continue..."
    read
}

delete_all_custom_variables() {
    local container_name="$1"
    local env_file=$(get_custom_env_file "$container_name")

    clear
    echo "╔════════════════════════════════════════╗"
    echo "║    Delete All Custom Variables         ║"
    echo "╚════════════════════════════════════════╝"
    echo

    if ! has_custom_env_file "$container_name"; then
        echo "ℹ️  No custom env file to delete"
        echo
        echo "Press Enter to continue..."
        read
        return
    fi

    local var_count=$(count_custom_vars "$container_name")

    echo "⚠️  CRITICAL WARNING!"
    echo
    echo "This will permanently delete the custom env file:"
    echo "  File: $env_file"
    echo "  Variables: $var_count"
    echo
    echo "The container will revert to using standard variables only."
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo -n "Type 'DELETE ALL' to confirm: "
    read confirm

    if [[ "$confirm" == "DELETE ALL" ]]; then
        # Backup before deleting
        local backup_file="${env_file}.backup-$(date +%Y%m%d-%H%M%S)"
        cp "$env_file" "$backup_file" 2>/dev/null

        if sudo rm -f "$env_file" 2>/dev/null || rm -f "$env_file" 2>/dev/null; then
            echo
            echo "✅ Custom env file deleted"
            echo
            echo "Backup saved to:"
            echo "  $backup_file"
            echo
            echo "⚠️  Recreate container (option 7) to apply changes"
        else
            echo
            echo "❌ Failed to delete env file"
        fi
    else
        echo
        echo "Deletion cancelled (confirmation did not match)."
    fi

    echo
    echo "Press Enter to continue..."
    read
}

# Export the main menu function
export -f env_management_menu
