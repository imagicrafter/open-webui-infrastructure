# MT Directory Refactoring Plan

This document analyzes refactoring opportunities across all features in the `mt/` directory to improve code maintainability, reduce duplication, and establish consistent patterns.

---

## Analysis Status

- ✅ **mt/setup/** - Complete (see below)
- ⏳ **mt/nginx-container/** - Pending
- ⏳ **mt/DB_MIGRATION/** - Pending
- ⏳ **mt/SYNC/** - Pending
- ⏳ **mt/tests/** - Pending
- ⏳ **Root-level scripts** (client-manager.sh, start-template.sh, etc.) - Pending

---

# Feature Analysis: mt/setup/

**Analysis Date**: 2025-10-29
**Status**: ✅ Complete
**Priority**: High (foundational infrastructure)

## Directory Structure

```
mt/setup/
├── README.md (20K)                                    # Main setup documentation
├── QUICKSTART-FRESH-DEPLOYMENT.md (11K)              # Deployment quickstart guide
├── quick-setup.sh (19K)                              # Automated server provisioning
├── cleanup-for-rebuild.sh (7.8K)                     # Droplet cleanup/reset script
└── scripts/
    ├── user-approve.sh (1.0K)                        # Approve pending user
    ├── user-delete.sh (4.1K)                         # Delete user with cleanup
    ├── user-demote-admin.sh (1.3K)                   # Demote admin to user
    ├── user-list.sh (1.6K)                           # List users with filters
    ├── user-promote-admin.sh (973B)                  # Promote user to admin
    ├── user-promote-primary.sh (1.3K)                # Promote to primary admin
    └── asset_management/
        ├── README.md (13K)                           # Asset management docs
        ├── IMPLEMENTATION_SUMMARY.md (10K)           # Implementation details
        ├── apply-branding.sh (13K)                   # Apply logos from URL
        └── generate-text-logo.sh (12K)               # Generate text-based logos
```

## Script Purpose Analysis

### Core Setup Scripts

| Script | Purpose | Lines | Complexity |
|--------|---------|-------|------------|
| **quick-setup.sh** | Automated droplet provisioning with user creation, repo cloning, swap configuration, package installation, service optimization | 520 | High |
| **cleanup-for-rebuild.sh** | Reset droplet to clean state, remove all Open WebUI resources | 229 | Medium |

### User Management Scripts (6 scripts)

| Script | Purpose | Lines | Database Operations |
|--------|---------|-------|---------------------|
| **user-list.sh** | Query and list users with filters (all/admin/user/pending) | 56 | SELECT |
| **user-approve.sh** | Approve pending user (change role to 'user') | 47 | UPDATE |
| **user-promote-admin.sh** | Promote user to admin role | 47 | UPDATE |
| **user-demote-admin.sh** | Demote admin to user (with primary admin check) | 56 | UPDATE |
| **user-promote-primary.sh** | Make admin the primary (earliest created_at timestamp) | 55 | UPDATE |
| **user-delete.sh** | Comprehensive user deletion with cascading cleanup | 132 | DELETE (10+ tables) |

### Asset Management Scripts (2 scripts)

| Script | Purpose | Lines | Key Functions |
|--------|---------|----------|---------------|
| **apply-branding.sh** | Download logo from URL, generate variants, apply to container | 345 | `check_dependencies`, `generate_logo_variants`, `apply_branding_to_container`, `download_and_apply_branding` |
| **generate-text-logo.sh** | Generate text-based logos (1-2 letters) with custom fonts/colors | 379 | `check_dependencies`, `generate_text_logo_variants`, `apply_branding_to_container`, `generate_and_apply_text_logo` |

## Issues Identified

### 1. Code Duplication (Critical - 15% of codebase)

#### Duplicate Function: `apply_branding_to_container`
- **Location**: Both `apply-branding.sh` and `generate-text-logo.sh`
- **Lines**: 115 lines (identical in both files)
  - `apply-branding.sh`: lines 157-269
  - `generate-text-logo.sh`: lines 204-316
- **Impact**: Changes require updates in 2 places
- **Fix**: Extract to `lib/asset-helpers.sh`

#### Duplicate Function: `check_dependencies`
- **Location**: Both asset management scripts
- **Lines**: ~25 lines each
- **Difference**: `apply-branding.sh` checks for `curl` + `imagemagick`, `generate-text-logo.sh` only checks `imagemagick`
- **Fix**: Extract to `lib/asset-helpers.sh` with parameterized dependency list

#### Duplicate Color Definitions
- **Location**: 4 scripts (quick-setup.sh, cleanup-for-rebuild.sh, both asset scripts)
- **Lines**: 5-6 lines per script
- **Pattern**:
  ```bash
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  BLUE='\033[0;34m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  NC='\033[0m'
  ```
- **Fix**: Extract to `lib/colors.sh`

#### Duplicate Docker Database Execution Pattern
- **Location**: All 6 user management scripts
- **Lines**: ~30 lines per script (180 total)
- **Pattern**:
  ```bash
  docker exec "$CONTAINER_NAME" python3 -c "
  import sqlite3
  conn = sqlite3.connect('/app/backend/data/webui.db')
  cursor = conn.cursor()
  # ... operations ...
  conn.close()
  "
  ```
- **Fix**: Create `lib/db-helpers.sh` with wrapper functions

**Total Duplication**: ~400+ lines across all scripts

### 2. Hard-Coded Values (High Priority)

| Value | Location | Occurrences | Should Be |
|-------|----------|-------------|-----------|
| `/app/backend/data/webui.db` | All user scripts | 6 | Config variable `DB_PATH` |
| `openwebui-` container prefix | cleanup script | 2 | Config variable `CONTAINER_PREFIX` |
| `/opt/openwebui-nginx` | cleanup, quick-setup | 3 | Config variable `NGINX_CONFIG_DIR` |
| `qbmgr` username | quick-setup, cleanup | 15+ | Config variable `DEPLOY_USER` |
| `https://github.com/imagicrafter/open-webui.git` | quick-setup | 1 | Config variable `REPO_URL` |
| Container paths (5+ different paths) | Asset scripts | 20+ | Config array `CONTAINER_PATHS` |

**Total Hard-Coded References**: 50+

### 3. Missing Centralized Configuration

**Current State**: No shared configuration file exists. Each script defines its own:
- Color codes
- Path constants
- Container names
- Database paths
- Network names

**Impact**: Changes to paths/names require updates in multiple files

### 4. Inconsistent Error Handling

**User Management Scripts**:
- Mix of `exit 0` vs `exit 1` returns
- Some scripts exit on error, others continue
- No consistent logging pattern
- Missing `set -euo pipefail` (only in asset scripts)

**Asset Scripts**:
- Better error handling with trap cleanup
- Consistent return codes
- Good use of `set -euo pipefail`

### 5. Lack of Input Validation

**User Scripts**:
- Email format not validated
- Container name existence not verified upfront
- No SQL injection protection (though using Python parameterized queries mitigates this)

**Asset Scripts**:
- Better validation (URL format, image file type)
- Dependency checks before execution

### 6. Common Functions Scattered

Functions that could be shared:
- Container existence/running checks (used in 8+ scripts)
- Docker exec wrapper with error handling (used in 8+ scripts)
- Database query wrapper (used in 6 scripts)
- Progress/status display formatting (used in all scripts)
- Confirmation prompts (used in cleanup + delete scripts)

## Refactoring Proposal

### Phase 1: Create Shared Library Infrastructure ⭐ High Priority

**Goal**: Eliminate duplication, centralize configuration

**Create New Directory Structure**:
```
mt/setup/lib/
├── config.sh              # Central configuration
├── colors.sh              # Color codes and formatting
├── docker-helpers.sh      # Docker operation wrappers
├── db-helpers.sh          # Database query helpers
├── validation.sh          # Input validation functions
└── asset-helpers.sh       # Shared asset management code
```

#### lib/config.sh
```bash
#!/bin/bash
# MT/Setup Configuration - Single Source of Truth

# Project configuration
PROJECT_NAME="open-webui"
CONTAINER_PREFIX="openwebui-"
NETWORK_NAME="openwebui-network"
NGINX_CONTAINER="openwebui-nginx"

# Paths
NGINX_CONFIG_DIR="/opt/openwebui-nginx"
DB_PATH="/app/backend/data/webui.db"
BACKEND_STATIC="/app/backend/open_webui/static"
BUILD_DIR="/app/build"
BUILD_STATIC="/app/build/static"

# Container paths for branding
CONTAINER_LOGO_PATHS=(
    "/app/backend/open_webui/static/favicon.png"
    "/app/backend/open_webui/static/logo.png"
    "/app/build/favicon.png"
    "/app/build/static/favicon.png"
    "/app/build/static/logo.png"
)

# User management
DEPLOY_USER="qbmgr"
REPO_URL="https://github.com/imagicrafter/open-webui.git"

# Memory configuration
CONTAINER_MEMORY_LIMIT="700m"
CONTAINER_MEMORY_RESERVATION="600m"
CONTAINER_MEMORY_SWAP="1400m"
```

#### lib/colors.sh
```bash
#!/bin/bash
# Color definitions for consistent output

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'  # No Color

# Helper functions for colored output
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
```

#### lib/docker-helpers.sh
```bash
#!/bin/bash
# Docker operation helper functions

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"

# Check if container exists and is running
container_is_running() {
    local container_name="$1"
    docker ps --format '{{.Names}}' | grep -q "^${container_name}$"
}

# Check if container exists (running or stopped)
container_exists() {
    local container_name="$1"
    docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"
}

# Execute command in container with error handling
docker_exec_safe() {
    local container_name="$1"
    shift

    if ! container_is_running "$container_name"; then
        print_error "Container '$container_name' is not running"
        return 1
    fi

    docker exec "$container_name" "$@"
}

# Restart container safely with verification
docker_restart_safe() {
    local container_name="$1"

    if ! container_exists "$container_name"; then
        print_error "Container '$container_name' does not exist"
        return 1
    fi

    print_info "Restarting container: $container_name"
    if docker restart "$container_name" >/dev/null 2>&1; then
        print_success "Container restarted successfully"
        return 0
    else
        print_error "Failed to restart container"
        return 1
    fi
}

# Get list of all Open WebUI containers
list_openwebui_containers() {
    docker ps -a --filter "name=${CONTAINER_PREFIX}" --format "{{.Names}}"
}
```

#### lib/db-helpers.sh
```bash
#!/bin/bash
# Database operation helper functions

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/docker-helpers.sh"

# Execute Python database query
db_exec() {
    local container_name="$1"
    local python_code="$2"

    if ! container_is_running "$container_name"; then
        print_error "Container '$container_name' is not running"
        return 1
    fi

    docker_exec_safe "$container_name" python3 -c "
import sqlite3
import sys
import json

conn = sqlite3.connect('$DB_PATH')
cursor = conn.cursor()

try:
    $python_code
    conn.commit()
except Exception as e:
    conn.rollback()
    print(json.dumps({'error': str(e)}), file=sys.stderr)
    sys.exit(1)
finally:
    conn.close()
"
}

# Get user by email (returns JSON)
db_get_user() {
    local container_name="$1"
    local email="$2"

    db_exec "$container_name" "
cursor.execute('SELECT id, email, role, created_at, name FROM user WHERE email = ?', ('$email',))
result = cursor.fetchone()
if result:
    print(json.dumps({
        'id': result[0],
        'email': result[1],
        'role': result[2],
        'created_at': result[3],
        'name': result[4]
    }))
else:
    print(json.dumps({'error': 'User not found'}), file=sys.stderr)
    sys.exit(1)
"
}

# Update user role
db_update_user_role() {
    local container_name="$1"
    local email="$2"
    local new_role="$3"

    db_exec "$container_name" "
cursor.execute('UPDATE user SET role = ? WHERE email = ?', ('$new_role', '$email'))
if cursor.rowcount == 0:
    print(json.dumps({'error': 'User not found'}), file=sys.stderr)
    sys.exit(1)
print(json.dumps({'success': True, 'updated': cursor.rowcount}))
"
}

# Check if user is primary admin (earliest created_at with role='admin')
db_is_primary_admin() {
    local container_name="$1"
    local email="$2"

    db_exec "$container_name" "
cursor.execute('''
    SELECT email FROM user
    WHERE role = 'admin'
    ORDER BY created_at ASC
    LIMIT 1
''')
result = cursor.fetchone()
is_primary = result and result[0] == '$email'
print(json.dumps({'is_primary': is_primary}))
"
}
```

#### lib/asset-helpers.sh
```bash
#!/bin/bash
# Asset management helper functions

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
source "$(dirname "${BASH_SOURCE[0]}")/docker-helpers.sh"

# Check for required dependencies
check_dependencies() {
    local deps=("$@")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing dependencies: ${missing[*]}"
        echo "Install with: apt-get install -y ${missing[*]}"
        return 1
    fi
    return 0
}

# Apply branding to container (115 lines - extracted from both asset scripts)
apply_branding_to_container() {
    local container_name="$1"
    local source_logo="$2"
    local temp_dir="$3"

    # Verify container is running
    if ! container_is_running "$container_name"; then
        print_error "Container '$container_name' is not running"
        return 1
    fi

    print_info "Applying branding to container: $container_name"

    # Copy logo variants to all container paths
    for path in "${CONTAINER_LOGO_PATHS[@]}"; do
        local filename=$(basename "$path")
        local source_file="$temp_dir/$filename"

        if [ ! -f "$source_file" ]; then
            print_warning "Variant not found: $filename (skipping)"
            continue
        fi

        print_info "Copying $filename to $path"
        if docker cp "$source_file" "$container_name:$path" 2>/dev/null; then
            print_success "Applied: $path"
        else
            print_warning "Failed to copy to: $path (may not exist)"
        fi
    done

    # Restart container to apply changes
    print_info "Restarting container to apply changes..."
    if docker_restart_safe "$container_name"; then
        print_success "Branding applied successfully!"
        return 0
    else
        print_error "Failed to restart container"
        return 1
    fi
}
```

#### lib/validation.sh
```bash
#!/bin/bash
# Input validation helper functions

source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"

# Validate email format
validate_email() {
    local email="$1"
    local regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"

    if [[ ! "$email" =~ $regex ]]; then
        print_error "Invalid email format: $email"
        return 1
    fi
    return 0
}

# Validate container name format
validate_container_name() {
    local name="$1"
    local regex="^[a-zA-Z0-9][a-zA-Z0-9_.-]+$"

    if [[ ! "$name" =~ $regex ]]; then
        print_error "Invalid container name: $name"
        echo "Container names must start with alphanumeric and contain only [a-zA-Z0-9_.-]"
        return 1
    fi
    return 0
}

# Validate URL format
validate_url() {
    local url="$1"
    local regex="^https?://.+"

    if [[ ! "$url" =~ $regex ]]; then
        print_error "Invalid URL format: $url"
        return 1
    fi
    return 0
}

# Prompt for confirmation
confirm_action() {
    local message="$1"
    local response

    echo -e "${YELLOW}${message} (y/N): ${NC}"
    read -r response

    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        print_info "Action cancelled"
        return 1
    fi
}
```

### Phase 2: Refactor Existing Scripts ⭐ High Priority

**Goal**: Update all scripts to use shared libraries

**Scripts to Update** (11 total):
1. **quick-setup.sh** - Source config.sh, colors.sh
2. **cleanup-for-rebuild.sh** - Source config.sh, colors.sh, docker-helpers.sh
3. **user-list.sh** - Source all libs
4. **user-approve.sh** - Source all libs
5. **user-delete.sh** - Source all libs
6. **user-promote-admin.sh** - Source all libs
7. **user-demote-admin.sh** - Source all libs
8. **user-promote-primary.sh** - Source all libs
9. **apply-branding.sh** - Source config.sh, colors.sh, asset-helpers.sh
10. **generate-text-logo.sh** - Source config.sh, colors.sh, asset-helpers.sh

**Standard Header Pattern**:
```bash
#!/bin/bash
# Script description

# Determine script location and find lib directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Support multiple directory depths (scripts/ vs scripts/asset_management/)
if [ -d "$SCRIPT_DIR/../lib" ]; then
    LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
elif [ -d "$SCRIPT_DIR/../../lib" ]; then
    LIB_DIR="$(cd "$SCRIPT_DIR/../../lib" && pwd)"
else
    echo "Error: Cannot find lib directory"
    exit 1
fi

# Source required libraries
source "$LIB_DIR/config.sh"
source "$LIB_DIR/colors.sh"
source "$LIB_DIR/docker-helpers.sh"  # If needed
source "$LIB_DIR/db-helpers.sh"      # If needed
source "$LIB_DIR/validation.sh"      # If needed
source "$LIB_DIR/asset-helpers.sh"   # If needed

# Enable strict error handling
set -euo pipefail
```

**Example Refactored Script** (user-promote-admin.sh):
```bash
#!/bin/bash
# Promote a user to admin role

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"

source "$LIB_DIR/config.sh"
source "$LIB_DIR/colors.sh"
source "$LIB_DIR/docker-helpers.sh"
source "$LIB_DIR/db-helpers.sh"
source "$LIB_DIR/validation.sh"

set -euo pipefail

# Validate input
if [ $# -ne 2 ]; then
    print_error "Usage: $0 <container_name> <user_email>"
    exit 1
fi

CONTAINER_NAME="$1"
USER_EMAIL="$2"

# Validate inputs
validate_container_name "$CONTAINER_NAME" || exit 1
validate_email "$USER_EMAIL" || exit 1

# Check container is running
if ! container_is_running "$CONTAINER_NAME"; then
    print_error "Container '$CONTAINER_NAME' is not running"
    exit 1
fi

# Update user role
print_info "Promoting $USER_EMAIL to admin..."
if db_update_user_role "$CONTAINER_NAME" "$USER_EMAIL" "admin"; then
    print_success "User promoted to admin successfully"
    exit 0
else
    print_error "Failed to promote user"
    exit 1
fi
```

### Phase 3: Reorganize Directory Structure 🔵 Medium Priority

**Goal**: Better organization and clearer categorization

**Proposed Structure**:
```
mt/setup/
├── README.md
├── QUICKSTART-FRESH-DEPLOYMENT.md
├── lib/                                    # NEW: Shared libraries (from Phase 1)
│   ├── config.sh
│   ├── colors.sh
│   ├── docker-helpers.sh
│   ├── db-helpers.sh
│   ├── validation.sh
│   └── asset-helpers.sh
├── bin/                                    # NEW: Primary executables
│   ├── quick-setup.sh                     # Moved from root
│   └── cleanup-for-rebuild.sh             # Moved from root
└── scripts/
    ├── user-management/                   # NEW: Group related scripts
    │   ├── user-list.sh
    │   ├── user-approve.sh
    │   ├── user-delete.sh
    │   ├── user-promote-admin.sh
    │   ├── user-demote-admin.sh
    │   └── user-promote-primary.sh
    └── asset-management/                  # Already exists
        ├── README.md
        ├── IMPLEMENTATION_SUMMARY.md
        ├── apply-branding.sh
        └── generate-text-logo.sh
```

**Changes Required**:
1. Create `bin/` directory
2. Move `quick-setup.sh` and `cleanup-for-rebuild.sh` to `bin/`
3. Create `scripts/user-management/` directory
4. Move all `user-*.sh` files to `scripts/user-management/`
5. Update all path references in documentation
6. Update symlinks or references from other scripts

### Phase 4: Standardization & Polish 🟢 Low Priority

**Goal**: Consistent error handling, validation, documentation

**Tasks**:
1. Add `set -euo pipefail` to all scripts (currently only in asset scripts)
2. Standardize exit codes (0 = success, 1 = error, 2 = invalid input)
3. Add comprehensive inline documentation to all functions
4. Create unit tests for shared library functions
5. Add logging capability (optional file output for debugging)
6. Create man pages or --help output for all scripts

## Metrics & Impact

### Current State (Before Refactoring)
- **Total Lines**: ~2,700
- **Duplicated Code**: ~400 lines (15%)
- **Scripts with Hard-coded Values**: 11/11 (100%)
- **Config Centralization**: 0%
- **Shared Functions**: 0
- **Maintainability Score**: 4/10

### After Phase 1 (Library Infrastructure)
- **Total Lines**: ~2,500 (-7%)
- **Duplicated Code**: ~200 lines (8%)
- **Scripts with Hard-coded Values**: 11/11 (100%)
- **Config Centralization**: 100% (lib/config.sh created)
- **Shared Functions**: 20+
- **Maintainability Score**: 6/10

### After Phase 2 (Script Refactoring)
- **Total Lines**: ~2,000 (-26%)
- **Duplicated Code**: 0 lines (0%)
- **Scripts with Hard-coded Values**: 0/11 (0%)
- **Config Centralization**: 100%
- **Shared Functions**: 20+
- **Maintainability Score**: 8/10

### After All Phases
- **Total Lines**: ~2,000 (-26%)
- **Duplicated Code**: 0 lines (0%)
- **Scripts with Hard-coded Values**: 0/11 (0%)
- **Config Centralization**: 100%
- **Shared Functions**: 25+
- **Directory Organization**: Clear categorization
- **Error Handling**: Standardized across all scripts
- **Documentation**: Comprehensive inline docs
- **Maintainability Score**: 9/10

## Implementation Recommendations

### Approach: Incremental (Recommended)

**Advantages**:
- Lower risk - test each phase independently
- Can stop at any phase if needed
- Easier to debug issues
- Can be spread across multiple work sessions

**Timeline**:
- **Phase 1**: 1-2 hours (create lib/ infrastructure)
- **Phase 2**: 2-3 hours (refactor 11 scripts)
- **Phase 3**: 1 hour (reorganize directories)
- **Phase 4**: 2-3 hours (polish and documentation)
- **Total**: 6-9 hours (can be split into multiple sessions)

### Testing Strategy

After each phase:
1. **Syntax Check**: Run `bash -n <script>` on all modified scripts
2. **Dry Run**: Test scripts with echo statements instead of actual operations
3. **Integration Test**: Run on test droplet/container
4. **Verification**: Compare outputs with pre-refactor behavior
5. **Documentation Update**: Update README files with new structure

### Rollback Plan

Each phase is self-contained:
- **Phase 1**: Simply don't source new libraries (no impact on existing scripts)
- **Phase 2**: Revert individual script changes via git
- **Phase 3**: Move files back to original locations
- **Phase 4**: Revert standardization changes

## Priority Ranking

| Phase | Priority | Impact | Effort | Risk | Recommendation |
|-------|----------|--------|--------|------|----------------|
| **Phase 1** | ⭐⭐⭐ Critical | High | Medium | Low | Do First |
| **Phase 2** | ⭐⭐ High | High | High | Medium | Do Second |
| **Phase 3** | 🔵 Medium | Medium | Low | Low | Optional |
| **Phase 4** | 🟢 Low | Low | Medium | Low | Nice to Have |

## Dependencies on Other mt/ Features

### Cross-Feature Implications
Once `mt/setup/lib/` is created, other mt/ features can leverage it:

- **mt/client-manager.sh**: Could use docker-helpers.sh, colors.sh
- **mt/start-template.sh**: Could use config.sh for container settings
- **mt/nginx-container/**: Could use docker-helpers.sh
- **mt/DB_MIGRATION/**: Could use db-helpers.sh, validation.sh
- **mt/SYNC/**: Could use docker-helpers.sh, config.sh

**Recommendation**: Start with mt/setup/ as the foundation, then extend libraries to support other features.

## Next Steps

1. **Review this analysis** with stakeholders
2. **Approve Phase 1** implementation
3. **Create mt/setup/lib/** directory structure
4. **Implement shared libraries** one at a time
5. **Test each library** independently
6. **Proceed to Phase 2** (refactor scripts)

---

## Notes

- Analysis completed: 2025-10-29
- Analyzed by: Claude Code exploration agent
- Next analysis: mt/nginx-container/
- Overall mt/ refactoring strategy: TBD (after all features analyzed)
