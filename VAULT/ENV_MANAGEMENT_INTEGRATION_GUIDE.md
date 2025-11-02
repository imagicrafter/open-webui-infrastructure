# Environment Variable Management - Integration Guide

This guide shows how to integrate the custom environment variable management system into `client-manager.sh` and `start-template.sh`.

## Files Created

1. **`env-manager-functions.sh`** - Core helper functions
2. **`env-manager-menu.sh`** - Interactive menu
3. **This guide** - Integration instructions

---

## Step 1: Source Helper Functions in client-manager.sh

Add this near the top of `client-manager.sh` (around line 10-20, after SCRIPT_DIR definition):

```bash
# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Source environment variable management functions (from VAULT/scripts/)
source "${SCRIPT_DIR}/VAULT/scripts/env-manager-functions.sh"
source "${SCRIPT_DIR}/VAULT/scripts/env-manager-menu.sh"
```

---

## Step 2: Update the Deployment Menu

### Current Menu (lines 2049-2068)

Replace this section:

```bash
echo "1) Start deployment"
echo "2) Stop deployment"
echo "3) Restart deployment"
echo "4) View logs"
echo "5) Show Cloudflare DNS configuration"
echo "6) Update OAuth allowed domains"
echo "7) Change domain/client (preserve data)"
echo "8) Sync Management"

# Show database option based on current database type
if [[ -n "$database_url" ]]; then
    echo "9) View database configuration (includes rollback)"
else
    echo "9) Migrate to Supabase/PostgreSQL"
fi

echo "10) Remove deployment (DANGER)"
echo "11) Return to deployment list"
echo
echo -n "Select action (1-11): "
```

### With Updated Menu:

```bash
echo "1) Start deployment"
echo "2) Stop deployment"
echo "3) Restart deployment"
echo "4) View logs"
echo "5) Show Cloudflare DNS configuration"
echo "6) Update OAuth allowed domains"
echo "7) Change domain/client (preserve data)"
echo "8) Sync Management"

# Show database option based on current database type
if [[ -n "$database_url" ]]; then
    echo "9) View database configuration (includes rollback)"
else
    echo "9) Migrate to Supabase/PostgreSQL"
fi

echo "10) Remove deployment (DANGER)"
echo "11) Env Management"  # ← NEW OPTION
echo "12) Return to deployment list"  # ← RENUMBERED
echo
echo -n "Select action (1-12): "  # ← UPDATE MAX NUMBER
```

---

## Step 3: Add Menu Case Handler

### Find the case statement (around line 2071-2685)

Add this new case BEFORE the last case (currently "11)"):

```bash
            10)
                # Remove deployment
                echo "⚠️  WARNING: This will permanently remove the deployment!"
                echo "Data volume will be preserved but container will be deleted."
                echo -n "Type 'DELETE' to confirm: "
                read confirm
                if [ "$confirm" = "DELETE" ]; then
                    echo "Removing $container_name..."
                    docker stop "$container_name" 2>/dev/null
                    docker rm "$container_name"
                    echo "Deployment removed. Data volume preserved."
                    echo "Press Enter to continue..."
                    read
                    return
                else
                    echo "Removal cancelled."
                    echo "Press Enter to continue..."
                    read
                fi
                ;;
            11)  # ← NEW CASE
                # Env Management
                env_management_menu "$container_name"
                ;;
            12)  # ← RENUMBERED (was 11)
                # Return to deployment list
                return
                ;;
```

---

## Step 4: Modify Docker Run Commands to Include --env-file

There are multiple places in `client-manager.sh` where containers are created. Each needs the `--env-file` flag added.

### Helper Function (Add after sourcing env-manager-functions.sh)

```bash
# Get env-file flag for docker run (if custom env file exists)
get_env_file_flag() {
    local container_name="$1"
    local env_file=$(get_custom_env_file "$container_name")

    if [ -f "$env_file" ]; then
        echo "--env-file \"$env_file\""
    else
        echo ""
    fi
}
```

### Location 1: OAuth Domain Update (around line 2247)

**Find this docker run command:**

```bash
docker run -d \
    --name "$container_name" \
    --network openwebui-network \
    -e GOOGLE_CLIENT_ID=1063776054060-2fa0vn14b7ahi1tmfk49cuio44goosc1.apps.googleusercontent.com \
    -e GOOGLE_CLIENT_SECRET=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 \
    # ... rest of command
```

**Add --env-file flag:**

```bash
# Get custom env file flag
local env_file_flag=$(get_env_file_flag "$container_name")

docker run -d \
    --name "$container_name" \
    --network openwebui-network \
    ${env_file_flag} \
    -e GOOGLE_CLIENT_ID=1063776054060-2fa0vn14b7ahi1tmfk49cuio44goosc1.apps.googleusercontent.com \
    -e GOOGLE_CLIENT_SECRET=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 \
    # ... rest of command
```

### Location 2: Host nginx mode (around line 2271)

**Find:**

```bash
docker run -d \
    --name "$container_name" \
    -p "${port}:8080" \
    -e GOOGLE_CLIENT_ID=1063776054060-2fa0vn14b7ahi1tmfk49cuio44goosc1.apps.googleusercontent.com \
    # ... rest
```

**Add:**

```bash
# Get custom env file flag
local env_file_flag=$(get_env_file_flag "$container_name")

docker run -d \
    --name "$container_name" \
    -p "${port}:8080" \
    ${env_file_flag} \
    -e GOOGLE_CLIENT_ID=1063776054060-2fa0vn14b7ahi1tmfk49cuio44goosc1.apps.googleusercontent.com \
    # ... rest
```

### Location 3: Domain Change (around line 2431)

**Find:**

```bash
docker run -d \
    --name "$new_container_name" \
    -p "${current_port}:8080" \
    -e GOOGLE_CLIENT_ID=1063776054060-2fa0vn14b7ahi1tmfk49cuio44goosc1.apps.googleusercontent.com \
    # ... rest
```

**Add:**

```bash
# Get custom env file flag (use NEW container name)
local env_file_flag=$(get_env_file_flag "$new_container_name")

docker run -d \
    --name "$new_container_name" \
    -p "${current_port}:8080" \
    ${env_file_flag} \
    -e GOOGLE_CLIENT_ID=1063776054060-2fa0vn14b7ahi1tmfk49cuio44goosc1.apps.googleusercontent.com \
    # ... rest
```

### Location 4: Database Migration Recreation

Find the `recreate_container_with_postgres` function in `mt/DB_MIGRATION/db-migration-helper.sh` and add `--env-file` flag there as well.

---

## Step 5: Update start-template.sh

### Add custom env directory constant (line 5)

```bash
#!/bin/bash

# Multi-Client Open WebUI Template Script
# Usage: ./start-template.sh CLIENT_NAME PORT DOMAIN CONTAINER_NAME FQDN [OAUTH_DOMAINS] [WEBUI_SECRET_KEY]
# FQDN-based container naming for multi-tenant deployments

# Custom environment variables directory
CUSTOM_ENV_DIR="/opt/openwebui-configs"
```

### Add env-file flag to docker run command (around line 68-95)

**Find:**

```bash
docker_cmd="docker run -d \
    --name ${CONTAINER_NAME} \
    ${PORT_CONFIG} \
    ${NETWORK_CONFIG} \
    -e GOOGLE_CLIENT_ID=1063776054060-2fa0vn14b7ahi1tmfk49cuio44goosc1.apps.googleusercontent.com \
    # ... rest
```

**Replace with:**

```bash
# Check for custom env file
ENV_FILE_FLAG=""
if [ -f "${CUSTOM_ENV_DIR}/${CONTAINER_NAME}.env" ]; then
    ENV_FILE_FLAG="--env-file ${CUSTOM_ENV_DIR}/${CONTAINER_NAME}.env"
    echo "✓ Loading custom environment variables from ${CONTAINER_NAME}.env"
fi

docker_cmd="docker run -d \
    --name ${CONTAINER_NAME} \
    ${PORT_CONFIG} \
    ${NETWORK_CONFIG} \
    ${ENV_FILE_FLAG} \
    -e GOOGLE_CLIENT_ID=1063776054060-2fa0vn14b7ahi1tmfk49cuio44goosc1.apps.googleusercontent.com \
    # ... rest
```

---

## Step 6: Make Scripts Executable

```bash
cd /path/to/open-webui/mt
chmod +x env-manager-functions.sh
chmod +x env-manager-menu.sh
```

---

## Testing the Integration

### Test 1: View Menu

```bash
./client-manager.sh
# Select option 3 (Manage Client Deployment)
# Select a client
# Verify option 11 "Env Management" appears
```

### Test 2: Create Variable

```bash
# In Env Management menu:
# Option 2: Create/Update Variable
# Name: TEST_VAR
# Value: test_value
# Verify file created at /opt/openwebui-configs/openwebui-CLIENT.env
```

### Test 3: View Variables

```bash
# Option 1: View All Custom Variables
# Should show: TEST_VAR = test********
```

### Test 4: Verify Env File

```bash
cat /opt/openwebui-configs/openwebui-localhost-8081.env
# Should contain:
# TEST_VAR=test_value
```

### Test 5: Container Recreation

```bash
# Option 6: Update OAuth allowed domains
# This will recreate container with --env-file flag
# After recreation, verify env var loaded:
docker exec openwebui-localhost-8081 env | grep TEST_VAR
# Should show: TEST_VAR=test_value
```

---

## File Structure After Integration

```
mt/
├── client-manager.sh              (modified - sourcing new files)
├── start-template.sh              (modified - --env-file support)
├── env-manager-functions.sh       (new - helper functions)
├── env-manager-menu.sh            (new - interactive menu)
└── ENV_MANAGEMENT_INTEGRATION_GUIDE.md  (this file)

/opt/openwebui-configs/
├── openwebui-localhost-8081.env   (created when first var added)
├── openwebui-chat-quantabase-io.env
└── ... (one per deployment with custom vars)
```

---

## Usage Examples

### Example 1: Add Google Drive Integration

```bash
./client-manager.sh
→ 3) Manage Client Deployment
→ Select: openwebui-localhost-8081
→ 11) Env Management
→ 2) Create/Update Variable

Variable name: GOOGLE_DRIVE_CLIENT_ID
Variable value: 1234567890-abcdefg.apps.googleusercontent.com

→ 2) Create/Update Variable (again)

Variable name: GOOGLE_DRIVE_CLIENT_SECRET
Variable value: GOCSPX-YourSecretHere

→ 1) View All Custom Variables
# Shows both variables (masked)

→ 7) Apply Changes
# Recreates container with env file
```

### Example 2: Add Multiple API Keys

```bash
# Via Env Management menu:
OPENAI_API_KEY=sk-proj-...
ANTHROPIC_API_KEY=sk-ant-...
GOOGLE_MAPS_API_KEY=AIza...
CUSTOM_API_ENDPOINT=https://api.example.com
```

### Example 3: View Variables from Command Line

```bash
# Direct file access
cat /opt/openwebui-configs/openwebui-localhost-8081.env

# View in container
docker exec openwebui-localhost-8081 env | grep GOOGLE_DRIVE
```

---

## Security Best Practices

### 1. File Permissions

The env files are created with `chmod 600` (owner read/write only):

```bash
ls -l /opt/openwebui-configs/*.env
# Should show: -rw------- (600)
```

### 2. Backup Before Deletion

Always backup before deleting variables:

```bash
cp /opt/openwebui-configs/openwebui-CLIENT.env \
   ~/backups/CLIENT.env.backup-$(date +%Y%m%d)
```

### 3. Never Commit to Git

Add to `.gitignore`:

```bash
/opt/openwebui-configs/*.env
*.env
```

### 4. Rotate Secrets Regularly

Use the update function to rotate API keys:

```bash
# Env Management → Option 2
# Update existing variable with new value
```

---

## Migration Path to Vault (Future)

When ready to migrate to Vault:

1. Keep `env-manager-functions.sh` and `env-manager-menu.sh` as-is
2. Replace function implementations with Vault API calls
3. Run migration script to move .env files to Vault
4. Update configuration to use Vault backend
5. No changes needed in `client-manager.sh` menu

See: `mt/VAULT/VAULT_DEPLOYMENT_GUIDE.md`

---

## Troubleshooting

### Issue: "Permission denied" creating /opt/openwebui-configs

**Solution:**

```bash
sudo mkdir -p /opt/openwebui-configs
sudo chown $USER:$USER /opt/openwebui-configs
chmod 755 /opt/openwebui-configs
```

### Issue: Env variables not loaded in container

**Check:**

```bash
# 1. Verify env file exists
ls -la /opt/openwebui-configs/openwebui-CLIENT.env

# 2. Check docker run included --env-file
docker inspect openwebui-CLIENT | grep env-file

# 3. Recreate container (option 6 in menu)
```

### Issue: Validation fails

**Common issues:**

```bash
# Bad: spaces around =
VARIABLE = value

# Good: no spaces
VARIABLE=value

# Bad: starts with number
123_VAR=value

# Good: starts with letter
VAR_123=value
```

### Issue: Changes not applied

**Remember:** Container must be recreated for env changes to take effect.

Options that recreate container:
- Option 6: Update OAuth allowed domains
- Option 7: Change domain/client
- Manual: `docker stop CLIENT && docker rm CLIENT` then redeploy

---

## Advanced: Programmatic Access

### Bash Script Integration

```bash
#!/bin/bash

# Source the functions
source /path/to/mt/env-manager-functions.sh

# Set a variable
set_env_var "openwebui-localhost-8081" "MY_VAR" "my_value"

# Get a variable
value=$(get_env_var "openwebui-localhost-8081" "MY_VAR")
echo "MY_VAR = $value"

# List all variables
list_env_var_names "openwebui-localhost-8081"

# Delete a variable
delete_env_var "openwebui-localhost-8081" "MY_VAR"
```

---

## Summary

This environment variable management system provides:

✅ **Interactive menu** for managing custom env vars per deployment
✅ **Validation** to prevent syntax errors
✅ **Security** with masked values and proper file permissions
✅ **Flexibility** to add any custom variables needed
✅ **Future-proof** design for easy Vault migration
✅ **No disruption** to existing client-manager functionality

All custom variables are stored in `/opt/openwebui-configs/{container-name}.env` and loaded via Docker's `--env-file` flag at container creation time.

---

**Last Updated:** 2025-01-22
**Version:** 1.0
**Tested On:** macOS, Ubuntu 22.04 LTS
