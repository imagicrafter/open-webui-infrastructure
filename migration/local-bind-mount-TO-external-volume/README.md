# Migration: Local Bind Mounts to External Volume

This directory contains scripts for migrating Open WebUI deployments from local bind mounts (`/opt/openwebui`) to Digital Ocean block storage volumes.

## Overview

**Migration Strategy: Symlink Approach**

This migration uses a symlink-based approach for minimal downtime:
1. Data is copied to external volume mounted at `/mnt/openwebui-volume`
2. Original `/opt/openwebui` directory is backed up
3. Symlink created: `/opt/openwebui` → `/mnt/openwebui-volume/openwebui`
4. Containers continue using same mount paths, now pointing through symlink

**Benefits:**
- ✅ Minimal downtime (2-10 minutes)
- ✅ No container recreation needed
- ✅ Easy rollback with automatic backup
- ✅ Data persists on detachable external storage

## Prerequisites

### 1. Digital Ocean Block Storage Volume

You need to create and attach a block storage volume to your droplet.

**Option A: Automatic (with doctl CLI)**
- Script auto-detects `doctl` and creates volume automatically
- Provides interactive prompts for configuration

**Option B: Manual (DO Dashboard)**
- Create volume at: https://cloud.digitalocean.com/volumes
- Size: Recommended 100GB+ (adjust based on data size)
- Region: **Must match your droplet's region**
- Attach to your droplet

### 2. System Requirements

- Root access to the server
- Docker installed and running
- Sufficient disk space on external volume (2x current data size recommended)
- Active Open WebUI deployments using bind mounts at `/opt/openwebui`

### 3. Backup Recommendations

While scripts create automatic backups, consider:
- Taking snapshots of your droplet before migration
- Backing up critical databases separately
- Documenting current configuration

## Migration Steps

### Step 1: Create and Attach External Volume

```bash
sudo bash 1-create-and-attach-volume.sh
```

**What it does:**
- Auto-detects if `doctl` CLI is installed
- If yes: Creates and attaches DO volume automatically
- If no: Provides manual instructions for DO dashboard
- Formats volume with ext4 filesystem
- Mounts at `/mnt/openwebui-volume`
- Adds to `/etc/fstab` for persistent mounting

**Configuration (optional):**
```bash
# Customize volume settings
export VOLUME_SIZE_GB=200          # Default: 100GB
export VOLUME_NAME=openwebui-data  # Default: openwebui-data
export MOUNT_POINT=/mnt/my-volume  # Default: /mnt/openwebui-volume

sudo bash 1-create-and-attach-volume.sh
```

### Step 2: Migrate Data to External Volume

```bash
sudo bash 2-migrate-to-external-volume.sh
```

**What it does:**
1. **Pre-flight checks:**
   - Verifies external volume is mounted
   - Checks sufficient disk space
   - Validates current directory structure

2. **Stops containers:**
   - Gracefully stops all `openwebui-*` containers
   - Logs container states

3. **Copies data:**
   - Uses `rsync` for efficient copying with progress
   - Copies from `/opt/openwebui` to `/mnt/openwebui-volume/openwebui`
   - Verifies file count matches

4. **Creates symlink:**
   - Backs up original directory: `/opt/openwebui.backup-TIMESTAMP`
   - Creates symlink: `/opt/openwebui` → `/mnt/openwebui-volume/openwebui`
   - Verifies symlink points correctly

5. **Restarts containers:**
   - Starts all containers
   - Waits for healthy status
   - Logs any issues

**Expected Downtime:** 2-10 minutes depending on data size

**Log Location:** `/var/log/openwebui-migration-external-TIMESTAMP.log`

### Step 3: Verify Migration

```bash
bash 3-verify-external-volume.sh
```

**What it does:**
Runs comprehensive verification tests:
- ✓ External volume is mounted
- ✓ Symlink points to correct location
- ✓ Data directories exist with proper structure
- ✓ All containers are running and healthy
- ✓ Container mounts point through symlink
- ✓ Branding files exist
- ✓ `/etc/fstab` entry for persistent mounting
- ✓ Disk space is acceptable
- ✓ Write access to external volume

**Example Output:**
```
[Test 1] External Volume Mount
✓ PASS: External volume is mounted at /mnt/openwebui-volume

[Test 2] Symlink Configuration
✓ PASS: Symlink points to correct location
         /opt/openwebui → /mnt/openwebui-volume/openwebui

[Test 4] Container Status
✓ PASS: All containers are running (3/3)
         ✓ openwebui-chat-blanecanada-ai (running, healthy)
         ✓ openwebui-chat-test-01-quantabase-io (running, healthy)
         ✓ openwebui-demo-client (running, healthy)

═══════════════════════════════════════════════════════
Test Summary
═══════════════════════════════════════════════════════
Passed:   9
Failed:   0
Warnings: 0
```

### Step 4: Manual Browser Testing

After verification passes:
1. **Test each deployment** by accessing in browser
2. **Verify branding** appears correctly
3. **Test functionality:**
   - Login/authentication
   - Creating new chats
   - Uploading files
   - Any custom features

### Step 5: Cleanup (After Successful Verification)

Once everything is verified working:

```bash
# Remove automatic backup directory
sudo rm -rf /opt/openwebui.backup-*

# Optional: Create final snapshot before cleanup
# (recommended in DO dashboard)
```

## Rollback Procedure

If migration fails or issues are discovered:

```bash
sudo bash 9-rollback-to-local.sh
```

**What it does:**
1. Stops all containers
2. Removes symlink
3. Restores from automatic backup (or copies from external volume if no backup)
4. Restarts containers
5. Optionally removes data from external volume

**Safety Features:**
- Preserves external volume data by default
- Uses automatic backup created during migration
- Verifies restoration before completing
- Comprehensive logging

## Architecture Details

### Before Migration
```
/opt/openwebui/
├── client1/
│   ├── data/          # Database and app data
│   ├── branding/      # Custom branding files
│   └── static/        # Served static files
└── client2/
    ├── data/
    ├── branding/
    └── static/

Containers bind mount directly to /opt/openwebui/{client}/
```

### After Migration
```
/mnt/openwebui-volume/
└── openwebui/         # Actual data location
    ├── client1/
    │   ├── data/
    │   ├── branding/
    │   └── static/
    └── client2/
        ├── data/
        ├── branding/
        └── static/

/opt/openwebui → /mnt/openwebui-volume/openwebui (symlink)

Containers still bind mount to /opt/openwebui/{client}/
(now transparently points to external volume)
```

### Why Symlink Approach?

**Advantages:**
1. **No container recreation** - Containers continue using same mount paths
2. **Minimal downtime** - Just stop/copy/symlink/start
3. **Easy rollback** - Remove symlink, restore backup
4. **Transparent to containers** - They don't know about the change
5. **No docker-compose edits** - Container configs unchanged

**Alternative Approaches Considered:**
- ❌ Direct mount path change - Requires container recreation, more downtime
- ❌ Docker volume migration - More complex, harder to rollback

## Troubleshooting

### External Volume Not Mounting

**Symptom:** `mountpoint: /mnt/openwebui-volume: No such file or directory`

**Solutions:**
1. Check volume is attached in DO dashboard
2. Find device: `lsblk` or `ls /dev/disk/by-id/`
3. Manually mount: `sudo mount /dev/disk/by-id/scsi-0DO_Volume_openwebui-data /mnt/openwebui-volume`
4. Re-run step 1 script

### Container Won't Start After Migration

**Symptom:** Containers fail to start or aren't healthy

**Solutions:**
1. Check container logs: `docker logs openwebui-{client}`
2. Verify symlink: `ls -la /opt/openwebui`
3. Check permissions: `ls -la /mnt/openwebui-volume/openwebui/`
4. Verify mount is accessible: `df -h /mnt/openwebui-volume`
5. If critical, rollback: `sudo bash 9-rollback-to-local.sh`

### Branding Not Appearing

**Symptom:** Custom logos don't show after migration

**Check:**
1. Verify branding files exist: `ls -la /mnt/openwebui-volume/openwebui/{client}/branding/`
2. Check branding-monitor service: `systemctl status branding-monitor`
3. Restart branding-monitor: `sudo systemctl restart branding-monitor`
4. Manually trigger injection:
   ```bash
   sudo bash /home/qbmgr/open-webui/mt/setup/lib/inject-branding-post-startup.sh \
     openwebui-{client} {client} /opt/openwebui/{client}/branding
   ```
5. Purge Cloudflare cache if using

### Disk Space Issues

**Symptom:** Not enough space on external volume

**Solutions:**
1. Check current usage: `df -h /mnt/openwebui-volume`
2. Resize volume in DO dashboard (can be done live)
3. Resize filesystem: `sudo resize2fs /dev/disk/by-id/scsi-0DO_Volume_openwebui-data`
4. Verify new size: `df -h /mnt/openwebui-volume`

### Volume Not Mounting After Reboot

**Symptom:** External volume not available after server restart

**Check:**
1. Verify `/etc/fstab` entry: `grep openwebui /etc/fstab`
2. Test mount: `sudo mount -a`
3. Check systemd mount logs: `journalctl -u '*.mount'`
4. Manually add to fstab if missing:
   ```bash
   echo "/dev/disk/by-id/scsi-0DO_Volume_openwebui-data /mnt/openwebui-volume ext4 defaults,nofail,discard 0 0" | sudo tee -a /etc/fstab
   ```

## Benefits of External Volumes

### Operational Benefits
- **Detachable Storage:** Move data between droplets without copying
- **Independent Scaling:** Scale storage separately from compute
- **Backup Snapshots:** Take volume snapshots independently
- **Cost Optimization:** Right-size droplet without data constraints

### Disaster Recovery
- **Quick Migration:** Detach from failed droplet, attach to new one
- **Data Preservation:** Data survives droplet deletion
- **Regional Redundancy:** (Future) Replicate volumes across regions
- **Faster Rebuilds:** Recreate droplet, attach existing volume

### Use Cases
1. **Droplet Migration:** Moving to larger/smaller droplet size
2. **Multi-Environment:** Swap volumes between staging/production
3. **Data Isolation:** Keep customer data on separate volumes
4. **Compliance:** Encrypted volumes for sensitive data

## Performance Considerations

### Network Overhead
- Block storage volumes use network (not local disk)
- Latency: ~1-2ms additional vs local SSD
- Throughput: Up to 7,000 IOPS for volumes >500GB
- Generally negligible impact for typical web applications

### Optimization Tips
1. **Volume Size:** Larger volumes have better IOPS (consider pre-allocating)
2. **Filesystem:** ext4 with `discard` option (already configured)
3. **Cache:** Open WebUI's built-in caching mitigates latency
4. **Monitoring:** Watch for I/O bottlenecks with `iostat`

### Expected Performance
- **Read Performance:** ~100-500 MB/s
- **Write Performance:** ~100-300 MB/s
- **IOPS:** 3,000-7,000 depending on volume size
- **Latency:** <5ms for most operations

**For most Open WebUI deployments:** Performance difference is imperceptible to end users.

## Security Considerations

### Data Protection
- ✅ Volume data encrypted at rest (DO default)
- ✅ Network encryption for volume traffic (DO default)
- ✅ Filesystem permissions preserved during migration
- ✅ Automatic backup created before migration

### Access Control
- Volume accessible only when attached to droplet
- Standard Linux filesystem permissions apply
- Container isolation maintained
- Root access required for management

### Best Practices
1. Take snapshots before major changes
2. Test rollback procedure in staging
3. Monitor volume attachment in DO dashboard
4. Document volume IDs and attachment points
5. Set up monitoring/alerting for mount failures

## Cost Considerations

### Digital Ocean Pricing (as of 2024)
- Block Storage: **$0.10/GB per month**
- Example: 100GB volume = **$10/month**

### Cost Comparison
| Storage Type | 100GB Cost | Detachable | Scalable |
|--------------|-----------|------------|----------|
| Droplet Disk | Included* | ❌ No      | ❌ No    |
| Block Volume | $10/month | ✅ Yes     | ✅ Yes   |

*Included with droplet base price, but requires larger droplet to scale

### When to Use External Volumes
- ✅ **Yes:** Need >50GB and might migrate between droplets
- ✅ **Yes:** Want to scale storage independently
- ✅ **Yes:** Multiple environments sharing data
- ❌ **Maybe:** Small deployments <20GB with single droplet
- ❌ **No:** Temporary/dev environments

## Monitoring and Maintenance

### Health Checks

**Monitor volume mount:**
```bash
# Check if volume is mounted
mountpoint /mnt/openwebui-volume

# Check disk space
df -h /mnt/openwebui-volume

# Check I/O stats
iostat -x 1 10
```

**Monitor containers:**
```bash
# Check container health
docker ps --filter "name=openwebui-" --format "table {{.Names}}\t{{.Status}}"

# Check branding monitor service
systemctl status branding-monitor

# View migration logs
tail -f /var/log/openwebui-migration-*.log
```

### Regular Maintenance

**Monthly:**
- Review disk space usage
- Check for failed containers
- Verify branding-monitor service running
- Review migration logs for errors

**Quarterly:**
- Test rollback procedure in staging
- Take volume snapshots
- Review and clean up old backups
- Audit permissions and access

## FAQ

### Q: Can I migrate back to local storage later?
**A:** Yes! Use `9-rollback-to-local.sh` at any time. The script handles everything automatically.

### Q: What happens if the volume gets detached?
**A:** Containers will fail to start (mount point unavailable). Reattach volume, verify mount, restart containers.

### Q: Can I migrate multiple times?
**A:** Yes, but each migration creates a new backup. Clean up old backups to save space.

### Q: Do containers need to be recreated?
**A:** No! The symlink approach means containers continue using the same mount paths.

### Q: Will branding still work after migration?
**A:** Yes, branding-monitor service automatically handles branding regardless of storage location.

### Q: How long is the downtime?
**A:** Typically 2-10 minutes depending on data size. Smaller deployments ~2-3 minutes.

### Q: Can I use a different mount point?
**A:** Yes, set `MOUNT_POINT` environment variable before running scripts.

### Q: What if doctl is not installed?
**A:** Script detects this and provides manual instructions for DO dashboard.

### Q: Can I resize the volume after migration?
**A:** Yes! Resize in DO dashboard, then run `sudo resize2fs /dev/disk/by-id/scsi-0DO_Volume_*`

### Q: Is this compatible with Phase 2 architecture?
**A:** Yes! This migration is storage-location agnostic and works with both Phase 1 and Phase 2.

## Support and Logs

### Log Files
- Migration: `/var/log/openwebui-migration-external-TIMESTAMP.log`
- Rollback: `/var/log/openwebui-rollback-TIMESTAMP.log`
- Branding Monitor: `/var/log/openwebui-branding-monitor.log`
- Container Logs: `docker logs openwebui-{client}`

### Getting Help

1. **Check verification output:** Run `3-verify-external-volume.sh`
2. **Review logs:** Check migration log in `/var/log/`
3. **Test in staging:** Always test migration in non-production first
4. **Rollback if needed:** Use `9-rollback-to-local.sh` for safety

## Related Documentation

- [Docker Volumes to Bind Mounts Migration](../docker-volumes-TO-bind-mounts/README.md)
- [Multi-Tenant Setup Guide](../../README.md)
- [Branding System Documentation](../../setup/README.md)

---

**Last Updated:** 2025-11-01
**Version:** 1.0
**Author:** QuantaBase Open WebUI Team
