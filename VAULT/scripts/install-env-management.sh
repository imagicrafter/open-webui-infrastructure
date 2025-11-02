#!/bin/bash

# Automated Installation Script for Environment Variable Management
# This script modifies client-manager.sh to add Env Management functionality

set -e  # Exit on error

# Script is now in mt/VAULT/scripts/
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
MT_DIR="$( cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd )"

echo "╔════════════════════════════════════════╗"
echo "║  Env Management Installation Script    ║"
echo "╚════════════════════════════════════════╝"
echo

echo "Paths:"
echo "  Scripts: ${SCRIPT_DIR}"
echo "  MT Root: ${MT_DIR}"
echo

# Check if required files exist
if [ ! -f "${SCRIPT_DIR}/env-manager-functions.sh" ]; then
    echo "❌ Error: env-manager-functions.sh not found in ${SCRIPT_DIR}"
    exit 1
fi

if [ ! -f "${SCRIPT_DIR}/env-manager-menu.sh" ]; then
    echo "❌ Error: env-manager-menu.sh not found in ${SCRIPT_DIR}"
    exit 1
fi

if [ ! -f "${MT_DIR}/client-manager.sh" ]; then
    echo "❌ Error: client-manager.sh not found in ${MT_DIR}"
    exit 1
fi

if [ ! -f "${MT_DIR}/start-template.sh" ]; then
    echo "❌ Error: start-template.sh not found in ${MT_DIR}"
    exit 1
fi

echo "✅ All required files found"
echo

# Backup existing files
echo "Creating backups..."
cp "${MT_DIR}/client-manager.sh" "${MT_DIR}/client-manager.sh.backup-$(date +%Y%m%d-%H%M%S)"
cp "${MT_DIR}/start-template.sh" "${MT_DIR}/start-template.sh.backup-$(date +%Y%m%d-%H%M%S)"
echo "✅ Backups created"
echo

# Check if already installed
if grep -q "env-manager-functions.sh" "${MT_DIR}/client-manager.sh"; then
    echo "⚠️  WARNING: Env Management appears to be already installed!"
    echo
    echo "Found 'env-manager-functions.sh' reference in client-manager.sh"
    echo
    echo -n "Continue anyway (will re-apply changes)? (y/N): "
    read confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    echo
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Modifying client-manager.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Add source statements (if not already present)
if ! grep -q "source.*env-manager-functions.sh" "${MT_DIR}/client-manager.sh"; then
    echo "Adding source statements..."

    # Find the line with SCRIPT_DIR definition
    line_num=$(grep -n "SCRIPT_DIR=" "${MT_DIR}/client-manager.sh" | head -1 | cut -d: -f1)

    if [ -z "$line_num" ]; then
        echo "❌ Error: Could not find SCRIPT_DIR definition"
        exit 1
    fi

    # Add source statements after SCRIPT_DIR (now pointing to VAULT/scripts/)
    sed -i.tmp "$((line_num + 1))i\\
\\
# Source environment variable management (from VAULT/scripts/)\\
source \"\${SCRIPT_DIR}/VAULT/scripts/env-manager-functions.sh\"\\
source \"\${SCRIPT_DIR}/VAULT/scripts/env-manager-menu.sh\"\\
\\
# Helper function to get env-file flag\\
get_env_file_flag() {\\
    local container_name=\"\$1\"\\
    local env_file=\$(get_custom_env_file \"\$container_name\")\\
    if [ -f \"\$env_file\" ]; then\\
        echo \"--env-file \\\"\$env_file\\\"\"\\
    else\\
        echo \"\"\\
    fi\\
}\\
" "${MT_DIR}/client-manager.sh"

    rm -f "${MT_DIR}/client-manager.sh.tmp"
    echo "✅ Source statements added"
else
    echo "⚠️  Source statements already present (skipping)"
fi

echo

# Update menu options
echo "Updating menu options..."

# This is a manual step - show instructions
echo "⚠️  MANUAL STEP REQUIRED:"
echo
echo "Please manually update the deployment menu in client-manager.sh:"
echo
echo "1. Find the menu around line 2049-2068"
echo "2. Add: echo \"11) Env Management\""
echo "3. Change: echo \"11) Return to deployment list\" → \"12) Return to deployment list\""
echo "4. Update: echo -n \"Select action (1-11):\" → \"Select action (1-12):\""
echo
echo "5. Add case handler around line 2657-2680:"
echo "   11)"
echo "       # Env Management"
echo "       env_management_menu \"\$container_name\""
echo "       ;;"
echo "   12)  # Changed from 11"
echo "       # Return to deployment list"
echo "       return"
echo "       ;;"
echo

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Modifying start-template.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Add custom env directory to start-template.sh
if ! grep -q "CUSTOM_ENV_DIR=" "${MT_DIR}/start-template.sh"; then
    echo "Adding CUSTOM_ENV_DIR variable..."

    # Add after shebang and comments
    sed -i.tmp "7i\\
\\
# Custom environment variables directory\\
CUSTOM_ENV_DIR=\"/opt/openwebui-configs\"\\
" "${MT_DIR}/start-template.sh"

    rm -f "${MT_DIR}/start-template.sh.tmp"
    echo "✅ CUSTOM_ENV_DIR added"
else
    echo "⚠️  CUSTOM_ENV_DIR already present (skipping)"
fi

echo

# Add env-file logic to docker run command
if ! grep -q "ENV_FILE_FLAG=" "${MT_DIR}/start-template.sh"; then
    echo "Adding env-file logic to docker run..."

    # Find the line with docker_cmd="docker run
    line_num=$(grep -n 'docker_cmd="docker run' "${MT_DIR}/start-template.sh" | head -1 | cut -d: -f1)

    if [ -z "$line_num" ]; then
        echo "❌ Error: Could not find docker_cmd line"
        exit 1
    fi

    # Add env-file check before docker_cmd
    sed -i.tmp "$((line_num - 1))a\\
\\
# Check for custom env file\\
ENV_FILE_FLAG=\"\"\\
if [ -f \"\${CUSTOM_ENV_DIR}/\${CONTAINER_NAME}.env\" ]; then\\
    ENV_FILE_FLAG=\"--env-file \${CUSTOM_ENV_DIR}/\${CONTAINER_NAME}.env\"\\
    echo \"✓ Loading custom environment variables from \${CONTAINER_NAME}.env\"\\
fi\\
" "${MT_DIR}/start-template.sh"

    # Now add ENV_FILE_FLAG to docker run command
    # Find the line with --name and add ENV_FILE_FLAG on next line
    sed -i.tmp "s|\(--name \${CONTAINER_NAME}\)|\1 \\\\\n    \${ENV_FILE_FLAG}|" "${MT_DIR}/start-template.sh"

    rm -f "${MT_DIR}/start-template.sh.tmp"
    echo "✅ Env-file logic added to start-template.sh"
else
    echo "⚠️  Env-file logic already present (skipping)"
fi

echo

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Setting up environment directory"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Create /opt/openwebui-configs if it doesn't exist
if [ ! -d "/opt/openwebui-configs" ]; then
    echo "Creating /opt/openwebui-configs..."
    sudo mkdir -p /opt/openwebui-configs 2>/dev/null || mkdir -p /opt/openwebui-configs 2>/dev/null
    if [ $? -eq 0 ]; then
        sudo chown $USER:$USER /opt/openwebui-configs 2>/dev/null || true
        chmod 755 /opt/openwebui-configs
        echo "✅ Directory created: /opt/openwebui-configs"
    else
        echo "⚠️  Could not create directory (may need sudo)"
    fi
else
    echo "✅ Directory already exists: /opt/openwebui-configs"
fi

echo

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: Making scripts executable"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

chmod +x "${SCRIPT_DIR}/env-manager-functions.sh"
chmod +x "${SCRIPT_DIR}/env-manager-menu.sh"
echo "✅ Scripts are now executable"

echo

echo "╔════════════════════════════════════════╗"
echo "║     Installation Complete (Partial)    ║"
echo "╚════════════════════════════════════════╝"
echo

echo "✅ Completed:"
echo "  - Backup files created"
echo "  - Source statements added to client-manager.sh"
echo "  - start-template.sh modified for --env-file"
echo "  - /opt/openwebui-configs directory created"
echo "  - Scripts made executable"
echo

echo "⚠️  MANUAL STEPS REQUIRED:"
echo
echo "Due to the complexity of the menu structure, please manually:"
echo
echo "1. Edit client-manager.sh:"
echo "   - Add menu option 11 (Env Management)"
echo "   - Renumber option 11 → 12 (Return to deployment list)"
echo "   - Update prompt to say 1-12 instead of 1-11"
echo "   - Add case 11) handler for env_management_menu"
echo "   - Renumber case 11) → 12)"
echo
echo "2. Add --env-file to docker run commands:"
echo "   - Search for all 'docker run -d' commands"
echo "   - Add: local env_file_flag=\$(get_env_file_flag \"\$container_name\")"
echo "   - Add: \${env_file_flag} after --name or --network"
echo
echo "See VAULT/ENV_MANAGEMENT_INTEGRATION_GUIDE.md for detailed instructions"
echo

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Testing the Installation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

echo "After completing manual steps, test with:"
echo
echo "  ./client-manager.sh"
echo "  → 3) Manage Client Deployment"
echo "  → Select a client"
echo "  → 11) Env Management"
echo

echo "Or run the test script:"
echo "  cd VAULT/scripts && ./test-env-management.sh"
echo

echo "Backups saved:"
ls -1 "${MT_DIR}"/client-manager.sh.backup-* 2>/dev/null | tail -1
ls -1 "${MT_DIR}"/start-template.sh.backup-* 2>/dev/null | tail -1
echo

echo "Installation script complete!"
