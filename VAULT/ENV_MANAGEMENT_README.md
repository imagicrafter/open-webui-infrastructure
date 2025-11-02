# Custom Environment Variable Management

Add custom environment variables to individual Open WebUI deployments without modifying the core deployment scripts.

## Quick Start

### 1. Install the System

```bash
cd /path/to/open-webui/mt

# Run automated installation
cd VAULT/scripts
./install-env-management.sh

# Follow manual steps in output
# (Edit client-manager.sh to add menu option 11)
```

### 2. Test Installation

```bash
# Run test suite (from VAULT/scripts directory)
./test-env-management.sh

# Expected output: ✅ ALL TESTS PASSED!
```

### 3. Use Env Management

```bash
# Start client manager
./client-manager.sh

# Navigate to:
# 3) Manage Client Deployment
# → Select your client
# → 11) Env Management

# Now you can:
# - View existing custom variables
# - Create/update variables
# - Delete variables
# - Apply changes (recreate container)
```

## What Was Created

### Core Files

1. **`env-manager-functions.sh`** (334 lines)
   - Helper functions for managing .env files
   - Create, read, update, delete operations
   - Validation and counting functions

2. **`env-manager-menu.sh`** (630 lines)
   - Interactive menu for env management
   - 9 menu options for complete control
   - Security features (masked values, confirmations)

3. **`ENV_MANAGEMENT_INTEGRATION_GUIDE.md`** (600+ lines)
   - Complete integration instructions
   - Code examples for all modifications
   - Testing and troubleshooting guide

4. **`install-env-management.sh`** (200+ lines)
   - Automated installation script
   - Backups existing files
   - Adds source statements
   - Creates directory structure

5. **`test-env-management.sh`** (330+ lines)
   - Comprehensive test suite
   - 27 automated tests
   - Validates all core functionality

### Documentation

- **`ENV_MANAGEMENT_README.md`** (this file)
- **`ENV_MANAGEMENT_INTEGRATION_GUIDE.md`** (detailed integration)
- **`VAULT/VAULT_DEPLOYMENT_GUIDE.md`** (future migration path)

## Features

### ✅ Interactive Menu System

```
╔════════════════════════════════════════╗
║         Env Management                 ║
╚════════════════════════════════════════╝

1) View All Custom Variables
2) Create/Update Variable
3) Delete Variable
4) View Raw Env File
5) Edit Env File (Advanced)
6) Validate Env File
7) Apply Changes (Recreate Container)
8) Delete All Custom Variables
9) Return to Deployment Menu
```

### ✅ Security Features

- **Masked values** in display (shows first 4 chars + *******)
- **600 permissions** on env files (owner read/write only)
- **Validation** prevents malformed variables
- **Confirmations** for destructive operations
- **Backups** before major changes

### ✅ Flexible Variable Management

- Add any custom environment variables
- Update existing variables
- Delete individual or all variables
- Direct file editing for advanced users
- Validation before applying

### ✅ Seamless Integration

- Works with existing client-manager.sh
- No changes to core deployment logic
- Compatible with all deployment types
- Future-proof for Vault migration

## Common Use Cases

### Example 1: Google Cloud Integration

```bash
# Add Google Drive credentials
GOOGLE_DRIVE_CLIENT_ID=1234567890-abc.apps.googleusercontent.com
GOOGLE_DRIVE_CLIENT_SECRET=GOCSPX-YourSecretHere
GOOGLE_MAPS_API_KEY=AIzaSyYourMapsAPIKey
```

### Example 2: AI Service Integration

```bash
# Add AI service API keys
OPENAI_API_KEY=sk-proj-your-key-here
OPENAI_API_BASE=https://api.openai.com/v1
ANTHROPIC_API_KEY=sk-ant-your-key-here
```

### Example 3: Custom Service Endpoints

```bash
# Add custom service configuration
CUSTOM_API_ENDPOINT=https://api.yourservice.com/v1
CUSTOM_API_KEY=your-api-key
CUSTOM_TIMEOUT=30
FEATURE_FLAG_NEW_UI=true
```

## File Locations

```
/path/to/open-webui/mt/
├── client-manager.sh              (modified - sources from VAULT/scripts/)
├── start-template.sh              (modified - --env-file support)
│
└── VAULT/
    ├── README.md                          (overview & roadmap)
    ├── ENV_MANAGEMENT_README.md           (this file)
    ├── ENV_MANAGEMENT_INTEGRATION_GUIDE.md
    ├── VAULT_DEPLOYMENT_GUIDE.md
    │
    └── scripts/
        ├── env-manager-functions.sh       (core functions)
        ├── env-manager-menu.sh            (interactive menu)
        ├── install-env-management.sh      (installer)
        └── test-env-management.sh         (test suite)

/opt/openwebui-configs/
├── openwebui-localhost-8081.env   (per-deployment env files)
├── openwebui-chat-quantabase-io.env
└── ... (created when first variable added)
```

## How It Works

### 1. Storage

Custom variables are stored in plain text files:
- Location: `/opt/openwebui-configs/{container-name}.env`
- Format: `KEY=VALUE` (one per line)
- Permissions: `600` (owner read/write only)

### 2. Loading

Variables are loaded via Docker's `--env-file` flag:

```bash
docker run -d \
    --name openwebui-localhost-8081 \
    --env-file /opt/openwebui-configs/openwebui-localhost-8081.env \
    -e GOOGLE_CLIENT_ID=... \
    -e GOOGLE_CLIENT_SECRET=... \
    ...
```

### 3. Precedence

Docker loads env vars in this order:
1. Variables from `--env-file` (custom vars)
2. Variables from `-e` flags (standard vars)

**Note:** `-e` flags override `--env-file` values if same key.

### 4. Container Recreation

Environment variables are loaded at **container creation time**.
To apply changes, container must be recreated:

```bash
# Container recreation preserves:
✅ Data volume (all chat history, uploads)
✅ Database connections
✅ OAuth configuration

# Downtime: ~10-30 seconds
```

## Integration Details

### Modified Files

1. **`client-manager.sh`**
   - Sources `env-manager-functions.sh` and `env-manager-menu.sh`
   - Adds menu option 11 "Env Management"
   - Adds `get_env_file_flag()` helper function
   - Updates docker run commands to include `--env-file`

2. **`start-template.sh`**
   - Checks for custom env file
   - Adds `--env-file` flag if file exists
   - Shows confirmation message when loading

### Docker Run Locations Updated

The following docker run commands include `--env-file`:
- New deployments (via start-template.sh)
- OAuth domain updates
- Domain/client changes
- Database migrations

## Validation

### Variable Name Rules

✅ Valid:
- `GOOGLE_DRIVE_CLIENT_ID`
- `OPENAI_API_KEY`
- `CUSTOM_VAR_123`
- `_INTERNAL_VAR`

❌ Invalid:
- `123_VAR` (starts with number)
- `MY-VAR` (contains hyphen)
- `MY VAR` (contains space)

### Format Requirements

```bash
# Good
VARIABLE_NAME=value
API_KEY=sk-proj-abc123

# Bad
VARIABLE_NAME = value  # spaces around =
VARIABLE-NAME=value    # hyphen in name
123_VAR=value          # starts with number
```

## Security Best Practices

### 1. File Permissions

Always verify:
```bash
ls -la /opt/openwebui-configs/*.env
# Should show: -rw------- (600)
```

### 2. Backup Before Changes

```bash
# Manual backup
cp /opt/openwebui-configs/openwebui-CLIENT.env \
   ~/backups/CLIENT-$(date +%Y%m%d).env.backup
```

### 3. Never Commit to Git

Add to `.gitignore`:
```
/opt/openwebui-configs/*.env
*.env
!.env.example
```

### 4. Rotate Secrets Regularly

Use menu option 2 to update existing variables.

### 5. Audit Access

```bash
# Check who has access
ls -la /opt/openwebui-configs/

# View file ownership
stat /opt/openwebui-configs/*.env
```

## Troubleshooting

### Issue: "Permission denied" accessing /opt/openwebui-configs

```bash
# Fix permissions
sudo chown $USER:$USER /opt/openwebui-configs
chmod 755 /opt/openwebui-configs
```

### Issue: Variables not loaded in container

```bash
# 1. Verify env file exists
ls -la /opt/openwebui-configs/openwebui-CLIENT.env

# 2. Check file is loaded
docker inspect openwebui-CLIENT | grep -A 5 "EnvFile"

# 3. Verify variables in container
docker exec openwebui-CLIENT env | grep YOUR_VAR

# 4. Recreate container if needed
# Use client-manager → option 6 (Update OAuth)
```

### Issue: Validation fails

```bash
# View detailed errors
./client-manager.sh
→ 11) Env Management
→ 6) Validate Env File

# Common fixes:
# - Remove spaces around =
# - Fix variable names (no hyphens, start with letter)
# - Remove empty values if not intended
```

### Issue: Container won't start after adding env vars

```bash
# 1. Check logs
docker logs openwebui-CLIENT

# 2. Verify env file syntax
cat /opt/openwebui-configs/openwebui-CLIENT.env

# 3. Validate file
cd /path/to/mt
source env-manager-functions.sh
validate_env_file "openwebui-CLIENT"

# 4. Restore from backup if needed
cp /opt/openwebui-configs/openwebui-CLIENT.env.backup \
   /opt/openwebui-configs/openwebui-CLIENT.env
```

## Future: Migration to Vault

This system is designed to easily migrate to HashiCorp Vault:

### Current (Filesystem)
```
/opt/openwebui-configs/
└── openwebui-CLIENT.env
    ├── GOOGLE_DRIVE_CLIENT_ID=xxx
    └── GOOGLE_DRIVE_CLIENT_SECRET=yyy
```

### Future (Vault)
```
vault kv put openwebui/deployments/openwebui-CLIENT \
    GOOGLE_DRIVE_CLIENT_ID=xxx \
    GOOGLE_DRIVE_CLIENT_SECRET=yyy
```

### Migration Path
1. Deploy Vault (see `VAULT/VAULT_DEPLOYMENT_GUIDE.md`)
2. Run migration script to copy .env → Vault
3. Update configuration to use Vault backend
4. No changes needed to menu or interface

## Command Reference

### Installation
```bash
./install-env-management.sh          # Install system
./test-env-management.sh             # Test installation
```

### Interactive Usage
```bash
./client-manager.sh                  # Start manager
→ 3) Manage Client Deployment
→ Select client
→ 11) Env Management
```

### Programmatic Usage
```bash
source env-manager-functions.sh

# Set variable
set_env_var "openwebui-CLIENT" "MY_VAR" "my_value"

# Get variable
get_env_var "openwebui-CLIENT" "MY_VAR"

# List all
list_env_var_names "openwebui-CLIENT"

# Delete
delete_env_var "openwebui-CLIENT" "MY_VAR"

# Count
count_custom_vars "openwebui-CLIENT"
```

## Support

### Documentation
- Integration Guide: `ENV_MANAGEMENT_INTEGRATION_GUIDE.md`
- Vault Migration: `VAULT/VAULT_DEPLOYMENT_GUIDE.md`
- Main README: `README.md`

### Testing
```bash
# Run full test suite
./test-env-management.sh

# Quick function test
source env-manager-functions.sh
ensure_custom_env_dir
```

### Logs
```bash
# View container logs
docker logs openwebui-CLIENT

# Check if env file loaded
docker exec openwebui-CLIENT env
```

---

**Version:** 1.0
**Created:** 2025-01-22
**Tested On:** macOS, Ubuntu 22.04 LTS
**Status:** Ready for Production
