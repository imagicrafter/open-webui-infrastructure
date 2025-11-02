# Open WebUI Migration Scripts
## Docker Volumes → Bind Mounts (Release → Main Branch)

This directory contains scripts to migrate production Open WebUI deployments from Docker volumes to bind mounts.

---

## Quick Start

### Prerequisites
- SSH access to production server (as qbmgr user)
- Sufficient disk space (2x current data size)
- Maintenance window scheduled (5-10 minutes per deployment)

### Migration Steps

```bash
# 1. Discover current deployments
bash 1-discover-deployments.sh

# 2. Backup deployment
bash 2-backup-deployment.sh openwebui-chat-lawnloonies-com

# 3. Prepare environment (one-time per server)
bash 3-prepare-environment.sh

# 4. Migrate deployment
bash 4-migrate-deployment.sh \
    openwebui-chat-lawnloonies-com \
    chat.lawnloonies.com \
    chat

# 5. Verify migration
bash 5-verify-migration.sh \
    openwebui-chat-lawnloonies-com \
    chat.lawnloonies.com

# 6. Manual testing (REQUIRED!)
# - Open https://chat.lawnloonies.com
# - Login and verify data
# - Test chat functionality

# 7. Cleanup old volume (after verification)
bash 6-cleanup-old-volume.sh openwebui-chat-lawnloonies-com
```

---

## Script Reference

### 0-check-active-users.sh
**Purpose:** Check for active users before migration
**Output:** Activity report and safety recommendation
**Risk:** None (read-only)
**Duration:** < 1 minute

```bash
bash 0-check-active-users.sh openwebui-chat-lawnloonies-com
```

**Checks:**
- Registered users and last login times
- Recent activity (last 24 hours, last hour)
- Active sessions
- Last chat activity timestamp
- Recent API requests
- Active network connections

**Safety Recommendations:**
- 🔴 **NOT SAFE**: Active users in last hour (wait for completion)
- 🟡 **CAUTION**: Activity in last 24 hours (notify users first)
- 🟢 **SAFE**: No recent activity (proceed with migration)

### 1-discover-deployments.sh
**Purpose:** Document current state of server
**Output:** Container list, volumes, sizes, branch info
**Risk:** None (read-only)
**Duration:** < 1 minute

```bash
bash 1-discover-deployments.sh > current-state.txt
```

### 2-backup-deployment.sh
**Purpose:** Create backup of deployment before migration
**Output:** Backup in `/root/migration-backups/<timestamp>/`
**Risk:** Low (requires sudo for backup directory)
**Duration:** 2-5 minutes

```bash
bash 2-backup-deployment.sh openwebui-chat-lawnloonies-com
```

**Backup includes:**
- Container configuration JSON
- Environment variables
- Complete data volume archive
- Metadata file

**Verification:**
```bash
# List backup contents
tar tzf /root/migration-backups/*/openwebui-*-data.tar.gz | head -20

# Check for database
tar tzf /root/migration-backups/*/openwebui-*-data.tar.gz | grep webui.db
```

### 3-prepare-environment.sh
**Purpose:** Set up server for bind mount architecture (one-time)
**Changes:**
- Switches repo to main branch
- Creates `/opt/openwebui/` structure
- Extracts default static assets
**Risk:** Low (creates new directories)
**Duration:** 5-10 minutes

```bash
bash 3-prepare-environment.sh
```

**What it does:**
1. Updates repository to main branch
2. Creates `/opt/openwebui/defaults/static/`
3. Extracts default Open WebUI assets
4. Sets correct ownership and permissions

### 4-migrate-deployment.sh
**Purpose:** Migrate single deployment to bind mounts
**Changes:**
- Stops container
- Creates bind mount directories
- Copies data from volume to directory
- Launches new container with bind mounts
**Risk:** Medium (active migration, ~2 min downtime)
**Duration:** 3-5 minutes
**Downtime:** ~2 minutes

```bash
bash 4-migrate-deployment.sh \
    openwebui-chat-lawnloonies-com \
    chat.lawnloonies.com \
    chat
```

**Parameters:**
- `container-name`: Full container name (e.g., openwebui-chat-lawnloonies-com)
- `fqdn`: Full domain name (e.g., chat.lawnloonies.com)
- `subdomain`: Subdomain only (e.g., chat)

**Safety features:**
- Verifies backup exists before starting
- Checks directory creation success
- Verifies database file after copy
- Keeps old volume for rollback
- Preserves environment variables

### 5-verify-migration.sh
**Purpose:** Automated verification of migration success
**Output:** Detailed status report
**Risk:** None (read-only)
**Duration:** < 1 minute

```bash
bash 5-verify-migration.sh \
    openwebui-chat-lawnloonies-com \
    chat.lawnloonies.com
```

**Checks:**
- Container status and health
- Bind mount configuration (2 mounts)
- Environment variables
- Database file existence
- Static assets count
- HTTP connectivity
- File permissions

### 6-cleanup-old-volume.sh
**Purpose:** Remove old Docker volume after successful migration
**Changes:** Deletes Docker volume
**Risk:** Low (only after verification)
**Duration:** < 1 minute

```bash
bash 6-cleanup-old-volume.sh openwebui-chat-lawnloonies-com
```

**Safety features:**
- Confirms container is running
- Verifies bind mounts are active
- Requires manual "DELETE" confirmation
- Shows volume size before deletion

### 9-rollback-deployment.sh
**Purpose:** Rollback to Docker volumes if migration fails
**Changes:**
- Removes bind mount container
- Recreates container with old volume
- Optionally removes bind mount directories
**Risk:** Low (restores to previous state)
**Duration:** 2-3 minutes

```bash
bash 9-rollback-deployment.sh openwebui-chat-lawnloonies-com
```

**When to use:**
- Migration failed
- Container won't start
- Data issues discovered
- Need to revert for any reason

**Requirements:**
- Old Docker volume must still exist
- If volume deleted, use backup restore instead

---

## Migration Workflow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  DISCOVERY PHASE                                                │
│  ────────────────                                               │
│  1. Run discovery script                                        │
│  2. Document current state                                      │
│  3. Verify disk space                                           │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│  BACKUP PHASE                                                   │
│  ─────────────                                                  │
│  1. Run backup script                                           │
│  2. Verify backup integrity                                     │
│  3. Note backup location                                        │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│  PREPARATION PHASE (One-time per server)                        │
│  ──────────────────                                             │
│  1. Switch to main branch                                       │
│  2. Create /opt/openwebui structure                             │
│  3. Extract default assets                                      │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│  MIGRATION PHASE                                                │
│  ────────────────                                               │
│  1. Stop container                          ← Rollback point    │
│  2. Create bind mount directories           ← Rollback point    │
│  3. Copy data to directories                ← Rollback point    │
│  4. Remove old container                    ← Rollback point    │
│  5. Start new container with bind mounts    ← Rollback point    │
│  6. Wait for healthy status                                     │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│  VERIFICATION PHASE                                             │
│  ───────────────────                                            │
│  1. Run verification script                                     │
│  2. Check automated tests                                       │
│  3. Perform manual tests:                                       │
│     • Login                                                     │
│     • Check chat history                                        │
│     • Send test message                                         │
│     • Verify branding                                           │
└─────────────────────────────────────────────────────────────────┘
                            ↓
                    ┌───────────────┐
                    │  Success?     │
                    └───────┬───────┘
                            │
              ┌─────────────┴─────────────┐
              ↓                           ↓
    ┌──────────────────┐        ┌─────────────────┐
    │  YES - CLEANUP   │        │  NO - ROLLBACK  │
    │  ──────────────  │        │  ─────────────  │
    │  1. Remove old   │        │  1. Run rollback│
    │     volume       │        │     script      │
    │  2. Monitor      │        │  2. Investigate │
    │  3. Document     │        │  3. Fix issues  │
    └──────────────────┘        │  4. Retry       │
                                └─────────────────┘
```

---

## Troubleshooting

### Issue: Container Not Healthy After Migration

**Symptoms:**
- Container status: running
- Health status: unhealthy

**Resolution:**
```bash
# Check logs
docker logs openwebui-chat-lawnloonies-com --tail 100

# Common fixes:

# 1. Permission issue
sudo chown -R qbmgr:qbmgr /opt/openwebui/chat-lawnloonies-com/

# 2. Missing static assets
cp -a /opt/openwebui/defaults/static/. /opt/openwebui/chat-lawnloonies-com/static/

# 3. Wait longer (health checks take up to 30 seconds)
watch 'docker inspect openwebui-chat-lawnloonies-com --format "{{.State.Health.Status}}"'
```

### Issue: Database Missing After Migration

**Symptoms:**
- Empty chat history
- Database file very small or missing

**Resolution:**
```bash
# Check if data was copied
ls -lah /opt/openwebui/chat-lawnloonies-com/data/

# Compare to volume
docker run --rm -v openwebui-chat-lawnloonies-com-data:/data alpine ls -lah /data/

# If data missing, rollback immediately
bash 9-rollback-deployment.sh openwebui-chat-lawnloonies-com
```

### Issue: Permission Denied Errors

**Symptoms:**
```
Error: Failed to create /opt/openwebui/chat-lawnloonies-com/data
Permission denied
```

**Resolution:**
```bash
# Fix ownership
sudo chown -R qbmgr:qbmgr /opt/openwebui

# Fix permissions
sudo chmod -R 755 /opt/openwebui

# Retry migration
bash 4-migrate-deployment.sh openwebui-chat-lawnloonies-com chat.lawnloonies.com chat
```

### Issue: Old Container Won't Stop

**Symptoms:**
```
Error: Failed to stop container
Container is still running
```

**Resolution:**
```bash
# Force stop
docker kill openwebui-chat-lawnloonies-com

# Wait a moment
sleep 2

# Verify stopped
docker ps | grep openwebui-chat-lawnloonies-com

# Retry migration
bash 4-migrate-deployment.sh openwebui-chat-lawnloonies-com chat.lawnloonies.com chat
```

---

## Architecture Changes

### Before (Release Branch - Docker Volumes)

```
Container: openwebui-chat-lawnloonies-com
Image: ghcr.io/imagicrafter/open-webui:release
Storage: Docker volume
Location: /var/lib/docker/volumes/openwebui-chat-lawnloonies-com-data/_data/

Mounts:
  -v openwebui-chat-lawnloonies-com-data:/app/backend/data

Backup: docker run --rm -v openwebui-chat-lawnloonies-com-data:/data ...
```

### After (Main Branch - Bind Mounts)

```
Container: openwebui-chat-lawnloonies-com
Image: ghcr.io/imagicrafter/open-webui:main
Storage: Host directories
Location: /opt/openwebui/chat-lawnloonies-com/

Mounts:
  -v /opt/openwebui/chat-lawnloonies-com/data:/app/backend/data
  -v /opt/openwebui/chat-lawnloonies-com/static:/app/backend/open_webui/static

Backup: tar czf backup.tar.gz /opt/openwebui/chat-lawnloonies-com/

Environment additions:
  -e CLIENT_ID=chat-lawnloonies-com
  -e SUBDOMAIN=chat
  -e FQDN=chat.lawnloonies.com
```

---

## Benefits After Migration

### 1. Simpler Backups
```bash
# Before
docker run --rm -v openwebui-data:/data -v $(pwd):/backup alpine tar czf /backup/backup.tar.gz -C /data .

# After
tar czf backup.tar.gz /opt/openwebui/chat-lawnloonies-com/
```

### 2. Easier Server Migration
```bash
# Copy to new server
rsync -avz /opt/openwebui/chat-lawnloonies-com/ newserver:/opt/openwebui/chat-lawnloonies-com/

# Recreate container
./client-manager.sh  # Create new deployment
```

### 3. Direct File Access
```bash
# View database
sqlite3 /opt/openwebui/chat-lawnloonies-com/data/webui.db

# Update branding
cp new-logo.png /opt/openwebui/chat-lawnloonies-com/static/logo.png
docker restart openwebui-chat-lawnloonies-com
```

### 4. Troubleshooting
```bash
# Check logs
tail -f /opt/openwebui/chat-lawnloonies-com/data/logs/*.log

# Check database size
du -sh /opt/openwebui/chat-lawnloonies-com/data/webui.db

# List uploaded files
ls -lh /opt/openwebui/chat-lawnloonies-com/data/uploads/
```

---

## Safety Features

All migration scripts include:

1. **Backup Verification** - Won't start without verified backup
2. **Directory Validation** - Confirms directories created before proceeding
3. **Data Integrity** - Verifies database file after copy
4. **Rollback Capability** - Keeps old volume until cleanup confirmed
5. **Health Monitoring** - Waits for container to become healthy
6. **Manual Confirmation** - Requires explicit approval for destructive operations

---

## Timeline Estimates

### Single Deployment
- Discovery: 1 minute
- Backup: 2-5 minutes (depends on data size)
- Preparation: 10 minutes (one-time per server)
- Migration: 3-5 minutes
- Verification: 10 minutes (includes manual testing)
- Cleanup: 1 minute
- **Total: ~30 minutes** (20 minutes for subsequent deployments)

### Multiple Deployments
- First deployment: 30 minutes
- Each additional: 20 minutes
- Example (3 deployments): 70 minutes

---

## Support

For issues during migration:

1. **Check logs:** `docker logs <container-name>`
2. **Review troubleshooting section** in this README
3. **Consult main migration plan:** `../MIGRATION_PLAN.md`
4. **Rollback if needed:** `bash 9-rollback-deployment.sh <container-name>`

---

## File Manifest

```
migration/
├── README.md (this file)
├── 1-discover-deployments.sh - Discovery and documentation
├── 2-backup-deployment.sh - Create backup
├── 3-prepare-environment.sh - One-time server setup
├── 4-migrate-deployment.sh - Perform migration
├── 5-verify-migration.sh - Automated verification
├── 6-cleanup-old-volume.sh - Remove old volume
└── 9-rollback-deployment.sh - Rollback to volumes
```

---

**Version:** 1.0
**Last Updated:** 2025-11-01
**Tested On:** Ubuntu 22.04, Docker 24.x
**Validated With:** openwebui-chat-lawnloonies-com on 45.55.182.177
