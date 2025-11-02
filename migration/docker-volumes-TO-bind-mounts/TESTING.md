# Migration Scripts Testing Guide

## Test Environment Setup

Before running on production (45.55.182.177), test the migration process on a test server.

### Prerequisites

1. **Test Server Requirements:**
   - Ubuntu 22.04 or similar
   - Docker installed
   - At least one Open WebUI deployment on release branch
   - SSH access as qbmgr user
   - Sufficient disk space (2x current data size)

2. **Test Deployment Setup:**
   ```bash
   # On test server, create a deployment using release branch
   git clone https://github.com/imagicrafter/open-webui.git
   cd open-webui
   git checkout release

   # Create test deployment with some data
   cd mt
   ./start-template.sh test 8081 test.example.com openwebui-test-example-com test.example.com

   # Add some test data
   # - Create user accounts
   # - Create test chats
   # - Upload test files (if applicable)
   ```

### Testing Steps

#### 1. Test Discovery Script

```bash
bash 1-discover-deployments.sh

# Verify output includes:
# - Container name: openwebui-test-example-com
# - Volume name: openwebui-test-example-com-data
# - Current branch: release
# - Data size
```

**Expected Output:**
```
=== Open WebUI Deployment Discovery ===
Server: test-server
Date: 2025-11-01

=== Containers ===
NAME                           IMAGE                                    STATUS
openwebui-test-example-com     ghcr.io/imagicrafter/open-webui:release  Up X minutes (healthy)

=== Docker Volumes ===
DRIVER    VOLUME NAME
local     openwebui-test-example-com-data

=== Volume Details ===
Container: openwebui-test-example-com
Mounts:
  volume: /var/lib/docker/volumes/openwebui-test-example-com-data/_data -> /app/backend/data
Environment:
  [Environment variables]
Status: running (Health: healthy)

=== Volume Disk Usage ===
openwebui-test-example-com-data: 10M

=== Repository Status ===
Branch: release
...
```

**Pass Criteria:**
- ✅ Container detected
- ✅ Volume detected
- ✅ Current branch is "release"
- ✅ Data size reported

#### 2. Test Backup Script

```bash
bash 2-backup-deployment.sh openwebui-test-example-com

# Verify backup created
sudo ls -la /root/migration-backups/*/

# Test backup integrity
tar tzf /root/migration-backups/*/openwebui-test-example-com-data.tar.gz | head -20
```

**Expected Output:**
```
=== Backing up: openwebui-test-example-com ===
Backup location: /root/migration-backups/20251101_123456

1. Exporting container config...
✅ Config exported
2. Exporting environment variables...
✅ Environment exported
3. Backing up data volume (this may take a few minutes)...
✅ Volume backed up
4. Verifying backup...
✅ Backup created: openwebui-test-example-com-data.tar.gz (8.5M)
5. Testing backup integrity...
✅ Backup integrity verified (XXX files)
6. Saving metadata...
✅ Metadata saved

=== Backup Complete ===
Location: /root/migration-backups/20251101_123456
Files created:
[List of backup files]
```

**Pass Criteria:**
- ✅ Backup file created
- ✅ Integrity test passed
- ✅ Metadata file created
- ✅ Backup size reasonable (similar to volume size)

#### 3. Test Preparation Script

```bash
bash 3-prepare-environment.sh

# Verify environment prepared
ls -la /opt/openwebui/defaults/static/
cd ~/open-webui && git branch --show-current
```

**Expected Output:**
```
=== Preparing Migration Environment ===

1. Updating repository to main branch...
✅ Repository updated (branch: main)
2. Creating directory structure...
✅ Directories created
3. Setting ownership...
✅ Ownership set
4. Extracting default static assets...
[Extraction output]
5. Verifying default assets...
✅ Default assets extracted: 19 files
   Sample files:
     /opt/openwebui/defaults/static/favicon.png
     /opt/openwebui/defaults/static/logo.png
     ...
6. Setting permissions...
✅ Permissions set
7. Verifying directory structure...
   /opt/openwebui:
   [Directory listing]

=== Migration Environment Ready ===
Repository: main branch
Directory: /opt/openwebui/
Default assets: 19 files
```

**Pass Criteria:**
- ✅ Repository switched to main branch
- ✅ /opt/openwebui directory created
- ✅ Default static assets extracted (>10 files)
- ✅ Correct ownership (qbmgr:qbmgr)

#### 4. Test Migration Script

```bash
bash 4-migrate-deployment.sh \
    openwebui-test-example-com \
    test.example.com \
    test

# Monitor progress
watch 'docker ps | grep openwebui-test-example-com'
```

**Expected Output:**
```
=== Migrating Deployment ===
Container: openwebui-test-example-com
CLIENT_ID: test-example-com
FQDN: test.example.com
Subdomain: test
Target Directory: /opt/openwebui/test-example-com

✅ Backup verified: /root/migration-backups/.../openwebui-test-example-com-data.tar.gz

⚠️  WARNING: This will stop and recreate the container
   Estimated downtime: 2-5 minutes

Continue? (y/N): y

Step 1: Stopping container...
✅ Container stopped
Step 2: Creating directory structure...
✅ Directories created
Step 3: Migrating data (this may take a few minutes)...
✅ Data migrated: 47 files (9.8M)
Step 4: Initializing static assets...
✅ Static assets initialized (19 files)
Step 5: Extracting environment variables...
  OAuth Domains: martins.net
  Secret Key: Nd-82HUo5i...
✅ Environment extracted
Step 6: Removing old container...
✅ Old container removed (volume preserved for rollback)
Step 7: Determining network configuration...
  Using port: 8081
Step 8: Launching new container...
[Container startup output]
Waiting for container to become healthy...
✅ Container is healthy
Step 9: Verifying migration...
✅ Bind mounts configured correctly (2 mounts found)
✅ Database file exists (256K)
✅ Static assets present: 19 files
Container status: running

=== Migration Complete ===
Container: openwebui-test-example-com
Status: running
Health: healthy
Data Directory: /opt/openwebui/test-example-com/data
Static Directory: /opt/openwebui/test-example-com/static

Next Steps (REQUIRED):
1. Test the deployment: https://test.example.com
2. Verify login and data integrity
3. Test chat functionality
4. Check custom branding (if any)
```

**Pass Criteria:**
- ✅ Container stopped successfully
- ✅ Directories created
- ✅ Data migrated (file count matches volume)
- ✅ Static assets initialized
- ✅ New container started
- ✅ Container becomes healthy
- ✅ 2 bind mounts configured
- ✅ Database file exists

#### 5. Test Verification Script

```bash
bash 5-verify-migration.sh \
    openwebui-test-example-com \
    test.example.com
```

**Expected Output:**
```
=== Migration Verification ===
Container: openwebui-test-example-com
FQDN: test.example.com

1. Container Status:
   Status: running
   Health: healthy
   ✅ Container running and healthy

2. Mount Configuration:
  bind: /opt/openwebui/test-example-com/data -> /app/backend/data
  bind: /opt/openwebui/test-example-com/static -> /app/backend/open_webui/static
   ✅ Bind mounts configured (2 found)

3. Environment Variables:
   CLIENT_ID: test-example-com
   FQDN: test.example.com
   SUBDOMAIN: test
   ✅ Environment variables correct

4. Data Integrity:
   Database: 256K
   Total Data: 9.8M (47 files)
   ✅ Database file exists

5. Static Assets:
   Files: 19
   Size: 2.1M
   ✅ Static assets present

6. HTTP Connectivity:
   Status: 200
   ✅ Web interface accessible

7. Permissions:
   Owner: qbmgr:qbmgr
   ✅ Correct ownership

8. Old Volume Status:
   ⚠️  Old volume still exists: openwebui-test-example-com-data (9.5M)
   After confirming migration success, run:
   bash 6-cleanup-old-volume.sh openwebui-test-example-com

=== Verification Summary ===
✅ All checks passed!

Manual Tests Required:
1. Open https://test.example.com in browser
2. Login with existing account
3. Verify chat history is intact
4. Test sending a new message
5. Check custom branding (if any)
```

**Pass Criteria:**
- ✅ All automated checks pass
- ✅ No errors reported
- ✅ Old volume still exists (safety feature)

#### 6. Manual Testing

**Critical Tests:**
1. **Access Test**
   ```bash
   curl -k https://test.example.com
   # Should return HTML (status 200 or 302)
   ```

2. **Login Test**
   - Open https://test.example.com in browser
   - Login with test account
   - Verify successful login

3. **Data Integrity Test**
   - Check that chat history is visible
   - Verify user accounts intact
   - Check uploaded files (if any)

4. **Functionality Test**
   - Send a new test message
   - Verify message appears in chat
   - Test any custom features

5. **Branding Test** (if applicable)
   - Check logo displays correctly
   - Verify favicon shows
   - Check any custom styling

**Pass Criteria:**
- ✅ Web interface accessible
- ✅ Login successful
- ✅ Chat history intact
- ✅ Can send new messages
- ✅ Branding correct (if applicable)

#### 7. Test Cleanup Script

```bash
bash 6-cleanup-old-volume.sh openwebui-test-example-com

# Verify volume removed
docker volume ls | grep openwebui-test-example-com-data
# Should return nothing
```

**Expected Output:**
```
=== Cleanup Old Volume ===
Volume: openwebui-test-example-com-data

Volume size: 9.5M

⚠️  WARNING: This will permanently delete the Docker volume: openwebui-test-example-com-data
   Make sure you have:
   1. Verified the migration is successful (bash 5-verify-migration.sh)
   2. Tested the deployment manually
   3. Confirmed all data is intact

Are you sure? Type 'DELETE' to confirm: DELETE

Removing volume...
✅ Volume removed: openwebui-test-example-com-data

Remaining volumes:
  (none)

=== Cleanup Complete ===
Old volume removed. Container now uses bind mounts exclusively.
```

**Pass Criteria:**
- ✅ Volume removed successfully
- ✅ No errors reported
- ✅ Container still running after cleanup

#### 8. Test Rollback Script

**Note:** Only test rollback AFTER testing cleanup, or create a new test deployment.

```bash
# Create another test deployment first
./start-template.sh test2 8082 test2.example.com openwebui-test2-example-com test2.example.com

# Backup and migrate
bash 2-backup-deployment.sh openwebui-test2-example-com
bash 4-migrate-deployment.sh openwebui-test2-example-com test2.example.com test2

# Test rollback (before cleanup)
bash 9-rollback-deployment.sh openwebui-test2-example-com
```

**Expected Output:**
```
=== Rollback Deployment ===
Container: openwebui-test2-example-com
Volume: openwebui-test2-example-com-data

✅ Old volume found: openwebui-test2-example-com-data (9.5M)

This will:
1. Stop and remove current container (with bind mounts)
2. Recreate container using old Docker volume
3. Optionally remove bind mount directories

Continue? (y/N): y

Step 1: Extracting configuration...
✅ Configuration extracted
Step 2: Removing current container...
✅ Container removed
Step 3: Determining network configuration...
  Using port: 8082
Step 4: Recreating container with Docker volume...
✅ Container recreated
Step 5: Waiting for container to become healthy...
✅ Container healthy
Step 6: Verifying rollback...
  Status: running
  Mount type: volume
✅ Container using Docker volume (rollback successful)

=== Rollback Complete ===
Container: openwebui-test2-example-com
Architecture: Docker volumes (release branch)
Status: running
Access: https://test2.example.com/oauth/google/callback

Bind mount directories still exist at: /opt/openwebui/test2-example-com
Remove bind mount directories? (y/N): y
✅ Bind mount directories removed

Rollback complete. Test the deployment to ensure it's working correctly.
```

**Pass Criteria:**
- ✅ Container recreated with volume mount
- ✅ Container becomes healthy
- ✅ Old data still accessible
- ✅ Uses Docker volume (not bind mount)

### Test Summary Checklist

- [ ] Discovery script works correctly
- [ ] Backup script creates verified backup
- [ ] Preparation script sets up environment
- [ ] Migration script completes without errors
- [ ] Verification script passes all checks
- [ ] Manual testing confirms data integrity
- [ ] Cleanup script removes old volume
- [ ] Rollback script restores to volumes

### Issues Found During Testing

Document any issues encountered:

1. **Issue:** [Description]
   **Solution:** [How it was resolved]

2. **Issue:** [Description]
   **Solution:** [How it was resolved]

### Performance Metrics

Track actual times for each step:

| Step | Expected | Actual | Notes |
|------|----------|--------|-------|
| Discovery | <1 min | | |
| Backup | 2-5 min | | |
| Preparation | 5-10 min | | |
| Migration | 3-5 min | | |
| Verification | <1 min | | |
| Manual Testing | 5-10 min | | |
| Cleanup | <1 min | | |
| **Total** | **~25 min** | | |

### Sign-Off

After successful testing, confirm:

- [ ] All scripts tested and working
- [ ] No data loss observed
- [ ] Rollback procedure verified
- [ ] Documentation accurate
- [ ] Ready for production deployment

**Tester:** _______________
**Date:** _______________
**Test Environment:** _______________

---

## Next Steps

After successful testing:

1. **Schedule production migration:**
   - Choose maintenance window
   - Notify deployment owners
   - Prepare rollback plan

2. **Run on production server (45.55.182.177):**
   ```bash
   ssh qbmgr@45.55.182.177
   cd ~/open-webui/mt/migration
   # Follow QUICK_START.md
   ```

3. **Monitor post-migration:**
   - Check logs for 24 hours
   - Collect user feedback
   - Monitor container health
   - Keep backups for 7 days

4. **Document results:**
   - Record actual times
   - Note any issues encountered
   - Update troubleshooting guide
   - Create post-migration report
