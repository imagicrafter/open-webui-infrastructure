# Open WebUI Version Change Feature

**Document Version:** 1.0
**Date:** 2025-11-03
**Status:** Design Document
**Related:** Phase 2 Infrastructure

---

## Overview

This document outlines two implementation approaches for adding "Change Open WebUI Version" functionality to client-manager.sh, allowing administrators to upgrade/downgrade Open WebUI deployments with proper data protection.

---

## Table of Contents

1. [Background](#background)
2. [Key Challenges](#key-challenges)
3. [Option A: Simple Version Change](#option-a-simple-version-change-6-8-hours)
4. [Option B: Smart Version Change](#option-b-smart-version-change-21-31-hours)
5. [Implementation Details](#implementation-details)
6. [Testing Strategy](#testing-strategy)
7. [Recommendations](#recommendations)

---

## Background

### Current State

Users can select Open WebUI image version during **initial deployment** via client-manager.sh:
- `latest` - Stable release (recommended)
- `main` - Development branch
- Custom tag (e.g., `v0.5.1`)

However, there's **no feature to change versions** for existing deployments.

### User Request

> "I need to see what a client Open WebUI version is from the Managing client deployment menu, and I need a 'Change Open WebUI version' feature that cleanly handles database schema compatibility with backup and migration path between versions."

### Current Status Display

**Before:**
```
Status: Up 10 minutes (healthy)
Ports:  0.0.0.0:8081->8080/tcp, [::]:8081->8080/tcp
Domain: chat-test-01.quantabase.io
Database: SQLite (default)
```

**After (Implemented):**
```
Status: Up 10 minutes (healthy)
Ports:  0.0.0.0:8081->8080/tcp, [::]:8081->8080/tcp
Domain: chat-test-01.quantabase.io
Database: SQLite (default)
Image:    ghcr.io/open-webui/open-webui:latest
```

---

## Key Challenges

### 1. Database Schema Compatibility ⚠️ CRITICAL

Open WebUI uses **Alembic migrations** for database schema management:

```python
# On container startup, Open WebUI checks schema version
# If mismatch detected → runs Alembic migrations
# This can fail or corrupt data if:
#   - Downgrading versions (backward migrations risky)
#   - Skipping multiple versions
#   - Schema has breaking changes
```

**Examples of Potential Issues:**

| Version Change | Risk Level | Issue |
|----------------|-----------|-------|
| `v0.5.0` → `v0.5.1` | Low | Patch release, forward migration |
| `v0.4.0` → `v0.5.0` | Medium | Major version, new tables/columns |
| `v0.5.0` → `v0.4.0` | **HIGH** | Downgrade, data loss possible |
| `v0.3.0` → `v0.6.0` | **HIGH** | Skip versions, untested migration path |

### 2. Database Type Complexity

Different backup/restore strategies needed:

**SQLite (Default):**
- Backup: Copy `/opt/openwebui/client-name/data/webui.db`
- Restore: Replace file
- Simple, fast, atomic

**PostgreSQL/Supabase:**
- Backup: `pg_dump` to SQL file
- Restore: Drop schema + `psql` restore
- Requires credentials, network access
- More complex error handling

### 3. Rollback Safety

If version change fails:
- Container won't start (health check fails)
- Data might be partially migrated
- Need clear rollback path
- User must not lose data

### 4. Container Recreation Workflow

Current deployment uses volume mounts:
- `/opt/openwebui/client-name/data` → `/app/backend/data` (SQLite, uploads)
- `/opt/openwebui/client-name/static` → `/app/backend/open_webui/static` (branding)

**Version change requires:**
1. Stop container
2. Remove container
3. Pull new image
4. Recreate with same volumes
5. Wait for health check

**Risk:** If new version incompatible, container won't become healthy.

---

## Option A: Simple Version Change (6-8 hours)

### Philosophy

**"Provide tools, user maintains control"**

- Create backup automatically
- Show clear warnings
- Let user decide on risk
- Provide rollback instructions
- Don't try to be too smart

### Features

✅ Display current version
✅ Create timestamped backup before change
✅ Pull new image
✅ Recreate container with new version
✅ Monitor health check
✅ Show rollback instructions if failure
❌ No automatic schema compatibility checking
❌ No automatic rollback on failure
❌ No migration monitoring

### Implementation Complexity

| Component | Difficulty | Time |
|-----------|-----------|------|
| Menu option | Easy | 30 min |
| Backup creation (SQLite) | Easy | 1 hour |
| Backup creation (PostgreSQL) | Medium | 2 hours |
| Container recreation | Easy | 1 hour |
| Health monitoring | Easy | 1 hour |
| Rollback instructions | Easy | 30 min |
| Testing | Medium | 2 hours |
| **TOTAL** | **Easy-Medium** | **6-8 hours** |

### User Experience

```
╔════════════════════════════════════════╗
║   Managing: chat-test-01               ║
╚════════════════════════════════════════╝

Status: Up 10 minutes (healthy)
Image:  ghcr.io/open-webui/open-webui:latest
Database: SQLite (default)

1) Start deployment
2) Stop deployment
...
14) Change Open WebUI version    <-- NEW OPTION
15) Return to deployment list

Select option: 14

╔════════════════════════════════════════╗
║      Change Open WebUI Version         ║
╚════════════════════════════════════════╝

Current version: ghcr.io/open-webui/open-webui:latest

Select new version:
  1) latest (stable release - recommended)
  2) main (development branch - bleeding edge)
  3) v0.5.1 (specific stable version)
  4) Custom tag (enter manually)
  5) Cancel

Selection: 1

⚠️  IMPORTANT: Version changes may require database schema migration
⚠️  This can fail or cause data loss, especially when downgrading

Pre-change checklist:
  ✓ Creating backup: /opt/openwebui/chat-test-01/backup-20251103-143022.tar.gz
  ✓ Backup size: 45MB
  ✓ Current image: ghcr.io/open-webui/open-webui:latest
  → New image:     ghcr.io/open-webui/open-webui:latest

Continue with version change? (y/N): y

Changing Open WebUI version...
  ✓ Stopping container: openwebui-chat-test-01
  ✓ Removing container
  ✓ Pulling new image: ghcr.io/open-webui/open-webui:latest
  ✓ Recreating container with new version
  ⏳ Waiting for health check (timeout: 120s)...

  10s... 20s... 30s... ✓ Container healthy!

✅ Version change successful!

New status:
  Image:    ghcr.io/open-webui/open-webui:latest
  Status:   Up 5 seconds (healthy)
  Database: SQLite (default)

Backup retained at: /opt/openwebui/chat-test-01/backup-20251103-143022.tar.gz
Keep this backup for at least 7 days.

Press Enter to continue...
```

### Failure Scenario

```
⏳ Waiting for health check (timeout: 120s)...
  10s... 20s... 30s... 40s... 50s... 60s... ❌ Timeout!

❌ Version change failed - container not healthy

Container status: Restarting (Exit 1)

Possible causes:
  - Database schema incompatibility
  - Missing dependencies in new version
  - Configuration incompatibility

📋 Rollback Instructions:

Option 1: Restore previous version manually
  1. Stop container:    docker stop openwebui-chat-test-01
  2. Remove container:  docker rm openwebui-chat-test-01
  3. Pull old image:    docker pull ghcr.io/open-webui/open-webui:main
  4. Recreate:          cd /Users/justinmartin/github/open-webui-infrastructure
                        ./start-template.sh chat-test-01 8081 chat-test-01.quantabase.io ...

Option 2: Restore from backup
  1. Stop container:    docker stop openwebui-chat-test-01
  2. Extract backup:    cd /opt/openwebui/chat-test-01
                        tar -xzf backup-20251103-143022.tar.gz
  3. Restart:           docker restart openwebui-chat-test-01

View container logs:  docker logs openwebui-chat-test-01

Press Enter to continue...
```

### Pseudocode (Option A)

```bash
change_openwebui_version() {
    local client_name="$1"
    local container_name="openwebui-${client_name}"
    local client_dir="/opt/openwebui/${client_name}"

    # Get current version
    local current_image=$(docker inspect "$container_name" --format '{{.Config.Image}}' 2>/dev/null)

    echo "Current version: $current_image"
    echo ""
    echo "Select new version:"
    echo "  1) latest (stable release - recommended)"
    echo "  2) main (development branch - bleeding edge)"
    echo "  3) v0.5.1 (specific stable version)"
    echo "  4) Custom tag (enter manually)"
    echo "  5) Cancel"

    read -p "Selection: " choice

    local new_tag
    case $choice in
        1) new_tag="latest" ;;
        2) new_tag="main" ;;
        3) new_tag="v0.5.1" ;;
        4)
            read -p "Enter custom tag: " new_tag
            if [[ -z "$new_tag" ]]; then
                echo "❌ Invalid tag"
                return 1
            fi
            ;;
        5)
            echo "Cancelled."
            return 0
            ;;
        *)
            echo "❌ Invalid selection"
            return 1
            ;;
    esac

    # Construct new image reference
    local image_repo="${OPENWEBUI_IMAGE:-ghcr.io/open-webui/open-webui}"
    local new_image="${image_repo}:${new_tag}"

    # Check if same version
    if [[ "$current_image" == "$new_image" ]]; then
        echo "⚠️  Already using $new_image"
        return 0
    fi

    echo ""
    echo "⚠️  IMPORTANT: Version changes may require database schema migration"
    echo "⚠️  This can fail or cause data loss, especially when downgrading"
    echo ""

    # Create backup
    echo "Pre-change checklist:"
    local backup_timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="${client_dir}/backup-${backup_timestamp}.tar.gz"

    echo "  ⏳ Creating backup..."
    if tar -czf "$backup_file" -C "${client_dir}" data 2>/dev/null; then
        local backup_size=$(du -h "$backup_file" | cut -f1)
        echo "  ✓ Backup created: $backup_file"
        echo "  ✓ Backup size: $backup_size"
    else
        echo "  ❌ Backup failed"
        read -p "Continue without backup? (y/N): " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            return 1
        fi
    fi

    echo "  ✓ Current image: $current_image"
    echo "  → New image:     $new_image"
    echo ""

    read -p "Continue with version change? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        return 0
    fi

    echo ""
    echo "Changing Open WebUI version..."

    # Stop container
    echo "  ⏳ Stopping container: $container_name"
    if docker stop "$container_name" >/dev/null 2>&1; then
        echo "  ✓ Container stopped"
    else
        echo "  ❌ Failed to stop container"
        return 1
    fi

    # Remove container
    echo "  ⏳ Removing container"
    if docker rm "$container_name" >/dev/null 2>&1; then
        echo "  ✓ Container removed"
    else
        echo "  ❌ Failed to remove container"
        return 1
    fi

    # Pull new image
    echo "  ⏳ Pulling new image: $new_image"
    if docker pull "$new_image" >/dev/null 2>&1; then
        echo "  ✓ Image pulled"
    else
        echo "  ❌ Failed to pull image"
        echo ""
        echo "Rollback: Recreate with old image manually"
        return 1
    fi

    # Get original container configuration
    # This is complex - need to extract all original docker run parameters
    # For now, show manual recreation instructions

    echo "  ⚠️  Container removed - manual recreation required"
    echo ""
    echo "To recreate with new version:"
    echo "  1. Export new version: export OPENWEBUI_IMAGE_TAG=$new_tag"
    echo "  2. Use client-manager.sh or start-template.sh to recreate"
    echo ""
    echo "Backup retained at: $backup_file"

    # Alternative: Programmatic recreation (requires extracting all params)
    # recreate_container "$client_name" "$new_image"

    return 0
}

# Helper function to recreate container with all original parameters
recreate_container() {
    local client_name="$1"
    local new_image="$2"

    # This would need to:
    # 1. Extract all environment variables from original
    # 2. Extract all volume mounts
    # 3. Extract port mappings
    # 4. Extract network configuration
    # 5. Extract resource limits
    # 6. Recreate with identical config except image

    # Example (simplified):
    docker run -d \
        --name "openwebui-${client_name}" \
        --restart unless-stopped \
        -p "${port}:8080" \
        -v "${client_dir}/data:/app/backend/data" \
        -v "${client_dir}/static:/app/backend/open_webui/static" \
        -e "WEBUI_NAME=${webui_name}" \
        -e "..." \
        "$new_image"

    # Wait for health check
    local timeout=120
    local elapsed=0
    echo "  ⏳ Waiting for health check (timeout: ${timeout}s)..."

    while [ $elapsed -lt $timeout ]; do
        sleep 5
        elapsed=$((elapsed + 5))

        local health=$(docker inspect "$container_name" --format '{{.State.Health.Status}}' 2>/dev/null)
        if [[ "$health" == "healthy" ]]; then
            echo "  ✓ Container healthy!"
            return 0
        fi

        printf "  %ds... " "$elapsed"
    done

    echo ""
    echo "  ❌ Health check timeout"
    return 1
}
```

### Pros & Cons

**Pros:**
- ✅ Simple, clear implementation
- ✅ User maintains control
- ✅ Explicit about risks
- ✅ Creates safety backup
- ✅ Clear failure modes
- ✅ Fast to implement (6-8 hours)

**Cons:**
- ❌ No automatic compatibility checking
- ❌ No automatic rollback on failure
- ❌ User must manually recreate container
- ❌ Requires technical knowledge
- ❌ No migration monitoring

---

## Option B: Smart Version Change (21-31 hours)

### Philosophy

**"Intelligent automation with safety nets"**

- Check version compatibility automatically
- Detect schema changes
- Auto-rollback on failure
- Monitor migration progress
- Minimize user intervention

### Features

✅ Display current version
✅ Create timestamped backup before change
✅ **Automatic version compatibility checking**
✅ **Schema version detection**
✅ Pull new image
✅ Recreate container with new version
✅ **Monitor Alembic migration logs**
✅ **Automatic rollback on failure**
✅ **Data integrity validation**
✅ **Retain backups for 7 days**
✅ **Migration success confirmation**

### Implementation Complexity

| Component | Difficulty | Time |
|-----------|-----------|------|
| Menu option | Easy | 30 min |
| Backup creation (SQLite) | Easy | 1 hour |
| Backup creation (PostgreSQL) | Medium | 2 hours |
| Version compatibility matrix | Medium | 3 hours |
| Schema version detection | Hard | 4 hours |
| Container recreation | Medium | 2 hours |
| Migration monitoring | Hard | 5 hours |
| Auto-rollback logic | Medium-Hard | 4 hours |
| Data integrity validation | Medium | 3 hours |
| Testing matrix | Hard | 8 hours |
| **TOTAL** | **Medium-Hard** | **21-31 hours** |

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Version Change Orchestrator                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Phase 1: Pre-Change Validation                             │
├─────────────────────────────────────────────────────────────┤
│  • Get current version from container                       │
│  • Get current schema version from database                 │
│  • Check target version compatibility matrix                │
│  • Warn if downgrade detected                               │
│  • Calculate migration path                                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Phase 2: Backup Creation                                   │
├─────────────────────────────────────────────────────────────┤
│  • Create timestamped backup directory                      │
│  • Backup data (SQLite file OR pg_dump)                     │
│  • Backup container environment variables                   │
│  • Record current version metadata                          │
│  • Validate backup integrity (checksum)                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Phase 3: Container Recreation                              │
├─────────────────────────────────────────────────────────────┤
│  • Extract all container configuration                      │
│  • Stop and remove old container                            │
│  • Pull new image version                                   │
│  • Recreate with identical config + new image               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Phase 4: Migration Monitoring                              │
├─────────────────────────────────────────────────────────────┤
│  • Watch container logs for Alembic migration messages      │
│  • Detect migration start/progress/completion               │
│  • Monitor for errors in migration                          │
│  • Timeout if stuck (configurable, default 300s)            │
│  • Validate schema version post-migration                   │
└─────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴──────────┐
                    │                    │
                    ▼                    ▼
          ┌──────────────────┐  ┌──────────────────┐
          │   Success Path   │  │   Failure Path   │
          └──────────────────┘  └──────────────────┘
                    │                    │
                    ▼                    ▼
┌─────────────────────────────┐ ┌──────────────────────────────┐
│  Phase 5a: Success          │ │  Phase 5b: Auto-Rollback     │
├─────────────────────────────┤ ├──────────────────────────────┤
│  • Health check passes      │ │  • Stop failed container     │
│  • Data integrity check     │ │  • Remove failed container   │
│  • Validate key tables      │ │  • Restore from backup       │
│  • Mark backup for cleanup  │ │  • Recreate old container    │
│  • Show success message     │ │  • Verify rollback success   │
└─────────────────────────────┘ └──────────────────────────────┘
```

### Version Compatibility Matrix

Store compatibility information in `config/openwebui-versions.conf`:

```bash
# Open WebUI Version Compatibility Matrix
# Format: version:min_schema:max_schema:safe_upgrade_from:safe_downgrade_to

declare -A OWUI_VERSION_COMPAT=(
    ["latest"]="unknown:unknown:*:"
    ["main"]="unknown:unknown:*:"
    ["v0.5.1"]="50:50:v0.5.0,v0.4.5:v0.5.0"
    ["v0.5.0"]="49:49:v0.4.5,v0.4.0:v0.4.5"
    ["v0.4.5"]="45:45:v0.4.0,v0.3.10:v0.4.0"
    ["v0.4.0"]="40:40:v0.3.10,v0.3.5:v0.3.10"
)

# Migration risk levels
declare -A MIGRATION_RISK=(
    ["v0.4.0->v0.5.0"]="medium"  # Major version jump
    ["v0.5.0->v0.4.0"]="high"    # Downgrade
    ["v0.5.0->v0.5.1"]="low"     # Patch release
)
```

### Schema Version Detection

```bash
# Detect current schema version from Alembic metadata
get_schema_version() {
    local client_name="$1"
    local container_name="openwebui-${client_name}"
    local database_type="$2"  # sqlite or postgresql

    if [[ "$database_type" == "sqlite" ]]; then
        # Query SQLite database for Alembic version
        local db_path="/opt/openwebui/${client_name}/data/webui.db"
        local schema_version=$(sqlite3 "$db_path" \
            "SELECT version_num FROM alembic_version LIMIT 1;" 2>/dev/null)
        echo "$schema_version"
    else
        # Query PostgreSQL for Alembic version
        local schema_version=$(docker exec "$container_name" \
            psql "$DATABASE_URL" -t -c \
            "SELECT version_num FROM alembic_version LIMIT 1;" 2>/dev/null | tr -d ' ')
        echo "$schema_version"
    fi
}

# Example usage
current_schema=$(get_schema_version "chat-test-01" "sqlite")
echo "Current schema version: $current_schema"
# Output: Current schema version: a8fc0456328e
```

### Migration Monitoring

```bash
# Monitor container logs for Alembic migration progress
monitor_migration() {
    local container_name="$1"
    local timeout=300  # 5 minutes
    local start_time=$(date +%s)

    echo "  ⏳ Monitoring database migration..."

    # Follow logs and watch for migration keywords
    docker logs -f "$container_name" 2>&1 | while read -r line; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        # Check for migration start
        if echo "$line" | grep -q "Running migration"; then
            echo "  ⏳ Migration in progress..."
        fi

        # Check for migration success
        if echo "$line" | grep -q "Migration complete" ||
           echo "$line" | grep -q "Database is up to date"; then
            echo "  ✓ Migration completed successfully"
            return 0
        fi

        # Check for migration errors
        if echo "$line" | grep -qi "error\|exception\|failed"; then
            echo "  ❌ Migration error detected:"
            echo "     $line"
            return 1
        fi

        # Timeout check
        if [ $elapsed -ge $timeout ]; then
            echo "  ❌ Migration timeout (${timeout}s)"
            return 1
        fi
    done
}
```

### Automatic Rollback

```bash
# Rollback to previous version on failure
auto_rollback() {
    local client_name="$1"
    local backup_dir="$2"
    local old_image="$3"
    local container_name="openwebui-${client_name}"

    echo ""
    echo "🔄 Auto-rollback initiated..."

    # Stop failed container
    echo "  ⏳ Stopping failed container..."
    docker stop "$container_name" >/dev/null 2>&1
    docker rm "$container_name" >/dev/null 2>&1
    echo "  ✓ Failed container removed"

    # Restore data from backup
    echo "  ⏳ Restoring data from backup..."
    local client_dir="/opt/openwebui/${client_name}"

    # Clear current data
    rm -rf "${client_dir}/data"/*

    # Extract backup
    tar -xzf "${backup_dir}/data.tar.gz" -C "${client_dir}"
    echo "  ✓ Data restored from backup"

    # Recreate container with old image
    echo "  ⏳ Recreating container with previous version..."
    export OPENWEBUI_IMAGE_TAG="${old_image##*:}"

    # Call start-template.sh or recreate programmatically
    recreate_container "$client_name" "$old_image"

    # Verify rollback
    sleep 10
    local health=$(docker inspect "$container_name" --format '{{.State.Health.Status}}' 2>/dev/null)

    if [[ "$health" == "healthy" ]]; then
        echo "  ✓ Rollback successful - container healthy"
        echo ""
        echo "✅ System restored to previous state"
        echo "   Image:   $old_image"
        echo "   Backup:  $backup_dir"
        return 0
    else
        echo "  ❌ Rollback failed - manual intervention required"
        echo ""
        echo "Manual recovery steps:"
        echo "  1. Check logs: docker logs $container_name"
        echo "  2. Backup location: $backup_dir"
        echo "  3. Contact support if needed"
        return 1
    fi
}
```

### Data Integrity Validation

```bash
# Validate data integrity after migration
validate_data_integrity() {
    local client_name="$1"
    local container_name="openwebui-${client_name}"
    local database_type="$2"

    echo "  ⏳ Validating data integrity..."

    if [[ "$database_type" == "sqlite" ]]; then
        # SQLite integrity check
        local db_path="/opt/openwebui/${client_name}/data/webui.db"

        # Run SQLite integrity check
        local integrity=$(sqlite3 "$db_path" "PRAGMA integrity_check;" 2>/dev/null)
        if [[ "$integrity" == "ok" ]]; then
            echo "  ✓ SQLite integrity check passed"
        else
            echo "  ❌ SQLite integrity check failed: $integrity"
            return 1
        fi

        # Check key tables exist
        local tables=$(sqlite3 "$db_path" \
            "SELECT name FROM sqlite_master WHERE type='table';" 2>/dev/null)

        local required_tables=("user" "auth" "chat" "document")
        for table in "${required_tables[@]}"; do
            if echo "$tables" | grep -q "$table"; then
                echo "  ✓ Table '$table' exists"
            else
                echo "  ⚠️  Table '$table' missing (might be OK for new schema)"
            fi
        done

        return 0
    else
        # PostgreSQL integrity check
        echo "  ⏳ Checking PostgreSQL connection..."
        docker exec "$container_name" \
            psql "$DATABASE_URL" -c "SELECT 1;" >/dev/null 2>&1

        if [ $? -eq 0 ]; then
            echo "  ✓ PostgreSQL connection OK"
            return 0
        else
            echo "  ❌ PostgreSQL connection failed"
            return 1
        fi
    fi
}
```

### Complete Workflow (Option B)

```bash
smart_version_change() {
    local client_name="$1"
    local container_name="openwebui-${client_name}"
    local client_dir="/opt/openwebui/${client_name}"

    # Phase 1: Pre-Change Validation
    echo "╔════════════════════════════════════════╗"
    echo "║   Smart Version Change: $client_name   ║"
    echo "╚════════════════════════════════════════╝"
    echo ""

    # Get current version
    local current_image=$(docker inspect "$container_name" --format '{{.Config.Image}}')
    local current_tag="${current_image##*:}"

    # Get database type
    local database_url=$(docker exec "$container_name" env | grep "DATABASE_URL=" | cut -d'=' -f2-)
    local database_type="sqlite"
    [[ -n "$database_url" ]] && database_type="postgresql"

    # Get schema version
    local current_schema=$(get_schema_version "$client_name" "$database_type")

    echo "Current Configuration:"
    echo "  Image:    $current_image"
    echo "  Schema:   $current_schema"
    echo "  Database: $database_type"
    echo ""

    # User selects new version (same as Option A)
    # ... version selection code ...

    local new_tag="latest"  # Example
    local image_repo="${OPENWEBUI_IMAGE:-ghcr.io/open-webui/open-webui}"
    local new_image="${image_repo}:${new_tag}"

    # Check compatibility
    echo "Compatibility Check:"
    check_version_compatibility "$current_tag" "$new_tag" "$current_schema"

    # Phase 2: Backup Creation
    local backup_timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_dir="${client_dir}/backups/backup-${backup_timestamp}"
    mkdir -p "$backup_dir"

    echo ""
    echo "Creating comprehensive backup..."

    # Backup data
    if [[ "$database_type" == "sqlite" ]]; then
        tar -czf "${backup_dir}/data.tar.gz" -C "${client_dir}" data
    else
        # PostgreSQL dump
        docker exec "$container_name" \
            pg_dump "$database_url" > "${backup_dir}/database.sql"
    fi

    # Backup container config
    docker inspect "$container_name" > "${backup_dir}/container-config.json"

    # Save metadata
    cat > "${backup_dir}/metadata.txt" <<EOF
Backup Created: $(date)
Client: $client_name
Old Image: $current_image
New Image: $new_image
Schema Version: $current_schema
Database Type: $database_type
EOF

    echo "  ✓ Backup created: $backup_dir"

    # Phase 3: Container Recreation
    echo ""
    read -p "Proceed with version change? (y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return 0

    echo ""
    echo "Changing version to $new_image..."

    docker stop "$container_name"
    docker rm "$container_name"
    docker pull "$new_image"
    recreate_container "$client_name" "$new_image"

    # Phase 4: Migration Monitoring
    if monitor_migration "$container_name"; then
        # Phase 5a: Success Path
        echo ""
        if validate_data_integrity "$client_name" "$database_type"; then
            echo ""
            echo "✅ Version change completed successfully!"
            echo ""
            echo "New Configuration:"
            echo "  Image:  $new_image"
            echo "  Status: $(docker inspect "$container_name" --format '{{.State.Status}}')"
            echo ""
            echo "Backup retained: $backup_dir"
            echo "Auto-cleanup in 7 days"
            return 0
        else
            echo "⚠️  Migration succeeded but data validation failed"
            echo "Initiating rollback for safety..."
        fi
    fi

    # Phase 5b: Failure Path - Auto-Rollback
    auto_rollback "$client_name" "$backup_dir" "$current_image"
}
```

### Pros & Cons

**Pros:**
- ✅ Intelligent compatibility checking
- ✅ Automatic rollback on failure
- ✅ Data integrity validation
- ✅ Professional user experience
- ✅ Handles edge cases
- ✅ Minimal user intervention
- ✅ Comprehensive backup strategy

**Cons:**
- ❌ Complex implementation (21-31 hours)
- ❌ Requires extensive testing
- ❌ Compatibility matrix needs maintenance
- ❌ Hard to cover all edge cases
- ❌ May give false sense of safety
- ❌ Debugging is harder

---

## Implementation Details

### Menu Integration

Add to client management menu in `client-manager.sh`:

```bash
# Around line 2085 (after existing options)
echo "14) Change Open WebUI version"
echo "15) Return to deployment list"
```

### File Structure

```
/Users/justinmartin/github/open-webui-infrastructure/
├── config/
│   └── openwebui-versions.conf        # NEW: Version compatibility matrix
├── setup/
│   └── lib/
│       ├── version-manager.sh         # NEW: Version change logic
│       └── backup-manager.sh          # NEW: Backup/restore logic
├── client-manager.sh                  # MODIFIED: Add menu option
└── migration/
    ├── OWUI_UPGRADE_FEATURE.md       # THIS DOCUMENT
    └── backups/                       # Auto-created per client
        └── client-name/
            └── backup-YYYYMMDD-HHMMSS/
                ├── data.tar.gz
                ├── container-config.json
                └── metadata.txt
```

### Backup Retention Policy

```bash
# Auto-cleanup old backups (run daily via cron)
cleanup_old_backups() {
    local retention_days=7
    local backup_base="/opt/openwebui"

    find "$backup_base" -type d -name "backup-*" -mtime +$retention_days -exec rm -rf {} \;
}
```

---

## Testing Strategy

### Test Matrix

| Test Case | Description | Expected Result |
|-----------|-------------|-----------------|
| **Upgrade Tests** | | |
| T1 | Upgrade `latest` → `main` (SQLite) | Success, forward migration |
| T2 | Upgrade `v0.5.0` → `v0.5.1` (SQLite) | Success, patch release |
| T3 | Upgrade `v0.4.0` → `v0.5.0` (PostgreSQL) | Success, major version |
| **Downgrade Tests** | | |
| T4 | Downgrade `main` → `latest` (SQLite) | Warning shown, user confirms |
| T5 | Downgrade `v0.5.1` → `v0.5.0` (SQLite) | Possible data loss warning |
| **Failure Tests** | | |
| T6 | Incompatible schema migration | Auto-rollback triggered |
| T7 | Network failure during image pull | Graceful error, container intact |
| T8 | Migration timeout (stuck) | Timeout, rollback |
| **Edge Cases** | | |
| T9 | Same version selected | Skip, inform user |
| T10 | Custom tag not found | Error before backup |
| T11 | Disk full during backup | Fail early, no changes |

### Testing Procedure

```bash
# Setup test environment
git checkout -b feature/version-change-testing
cd /Users/justinmartin/github/open-webui-infrastructure

# Deploy test client
./client-manager.sh
# > Create deployment: test-version-change
# > Image: v0.5.0
# > Port: 9999

# Test upgrade (Option A)
./client-manager.sh
# > Manage: test-version-change
# > 14) Change Open WebUI version
# > Select: latest
# > Verify: Backup created, container recreated

# Test downgrade
# > 14) Change Open WebUI version
# > Select: v0.4.0
# > Verify: Warning shown, rollback instructions

# Test failure scenario
# Manually corrupt database before change
sqlite3 /opt/openwebui/test-version-change/data/webui.db "DROP TABLE alembic_version;"
# > 14) Change Open WebUI version
# > Select: main
# > Verify: Migration fails, rollback triggered (Option B)
```

---

## Recommendations

### For Current Phase (Phase 2)

**Implement Option A (Simple Version Change)** because:

1. **User Base**: Your users are technical and can handle manual intervention
2. **Deployment Count**: Small number of clients (easier to manage)
3. **Testing Burden**: Less testing required (6-8 hours vs 21-31 hours)
4. **Risk vs Reward**: Option B's complexity doesn't justify the benefit yet

### When to Consider Option B

Upgrade to Option B when:
- Managing 10+ clients where manual intervention doesn't scale
- Non-technical users need to perform version changes
- Frequent version changes required (testing new features)
- Production SLA requires minimal downtime
- You have time/resources for comprehensive testing

### Hybrid Approach (Recommended Long-Term)

**Start with Option A, evolve to Option B incrementally:**

**Phase 1** (Week 1): Implement Option A
- Basic version change with backup
- Manual recreation
- Clear failure instructions

**Phase 2** (Month 2): Add basic automation
- Automatic container recreation
- Basic health monitoring
- Keep manual rollback

**Phase 3** (Month 3): Add intelligence
- Version compatibility checking
- Schema version detection
- Improved error messages

**Phase 4** (Month 4): Full automation
- Auto-rollback on failure
- Migration monitoring
- Data integrity validation

This spreads the 31-hour investment over 4 months while delivering immediate value.

---

## Appendix

### Related Documents

- `PHASE2_PROGRESS.md` - Phase 2 implementation status
- `OWUI_INFRAOPS_SEGREGATION_PLAN.md` - Overall infrastructure plan
- `client-manager.sh` - Main deployment management script
- `start-template.sh` - Container creation template

### Open WebUI Migration Resources

- [Open WebUI GitHub](https://github.com/open-webui/open-webui)
- [Alembic Documentation](https://alembic.sqlalchemy.org/)
- [Docker Inspect Reference](https://docs.docker.com/engine/reference/commandline/inspect/)

### Future Enhancements

- **Blue-Green Deployments**: Run old and new versions side-by-side
- **Canary Testing**: Test migration on subset of data first
- **Migration Preview**: Show what will change before applying
- **Version Pinning**: Lock deployments to specific versions
- **Automated Testing**: CI/CD pipeline for version compatibility

---

**Document Status:** Complete
**Next Actions:** Review with user, decide on Option A or B, create implementation task in Archon
