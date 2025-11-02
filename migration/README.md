# Open WebUI Migration Scripts

This directory contains migration scripts for different storage architecture transitions.

## Migration Types

### 1. Docker Volumes → Bind Mounts
📁 **Directory:** `docker-volumes-TO-bind-mounts/`

**Purpose:** Migrate from Docker-managed volumes to host bind mounts for better control and accessibility.

**Use Case:**
- You have existing Open WebUI deployments using Docker volumes
- You want direct access to data on the host filesystem
- You need easier backup/restore capabilities
- You want to prepare for multi-tenant architecture

**Documentation:** [docker-volumes-TO-bind-mounts/README.md](docker-volumes-TO-bind-mounts/README.md)

**Quick Start:**
```bash
cd docker-volumes-TO-bind-mounts
sudo bash 1-discover-deployments.sh
sudo bash 2-backup-deployment.sh openwebui-container-name
sudo bash 4-migrate-deployment.sh openwebui-container-name
```

---

### 2. Local Bind Mounts → External Volume
📁 **Directory:** `local-bind-mount-TO-external-volume/`

**Purpose:** Migrate from local bind mounts to Digital Ocean block storage volumes for portability and scalability.

**Use Case:**
- You want to move data between droplets easily
- You need to scale storage independently from compute
- You want better disaster recovery options
- You're running out of local disk space

**Documentation:** [local-bind-mount-TO-external-volume/README.md](local-bind-mount-TO-external-volume/README.md)

**Quick Start:**
```bash
cd local-bind-mount-TO-external-volume
sudo bash 1-create-and-attach-volume.sh
sudo bash 2-migrate-to-external-volume.sh
bash 3-verify-external-volume.sh
```

## Migration Paths

### Common Migration Scenarios

```
┌─────────────────────┐
│  Docker Volumes     │
│  (Legacy)           │
└──────────┬──────────┘
           │
           │ Migration 1: docker-volumes-TO-bind-mounts
           ▼
┌─────────────────────┐
│  Local Bind Mounts  │
│  /opt/openwebui     │
└──────────┬──────────┘
           │
           │ Migration 2: local-bind-mount-TO-external-volume
           ▼
┌─────────────────────┐
│  External Volume    │
│  (DO Block Storage) │
└─────────────────────┘
```

### Path 1: Fresh Install → Production
**For new deployments:**
1. Start with bind mounts (Phase 1) using `mt/client-manager.sh`
2. Optionally migrate to external volume when scaling needs arise

### Path 2: Legacy → Modern Multi-Tenant
**For existing Docker volume deployments:**
1. Run Migration 1: Docker volumes → bind mounts
2. Optionally run Migration 2: Bind mounts → external volume

### Path 3: Droplet Migration
**When moving to a new server:**
1. Create external volume on old server (Migration 2)
2. Take volume snapshot in DO dashboard
3. Create new droplet and attach snapshot volume
4. Mount and start containers

## Feature Comparison

| Feature | Docker Volumes | Local Bind Mounts | External Volume |
|---------|---------------|-------------------|-----------------|
| **Host Access** | ❌ Difficult | ✅ Direct | ✅ Direct |
| **Backup** | Complex | Easy (rsync/cp) | Easy + Snapshots |
| **Multi-Tenant** | ❌ No | ✅ Yes | ✅ Yes |
| **Portability** | ❌ Bound to host | ❌ Bound to host | ✅ Detachable |
| **Scalability** | Limited | Limited | Independent |
| **Performance** | Fast (local) | Fast (local) | Good (network) |
| **Cost** | Included | Included | +$0.10/GB/mo |
| **Disaster Recovery** | Manual | Manual backups | Volume snapshots |
| **Droplet Migration** | Complex | Complex | Detach/Attach |

## Choosing Your Migration Path

### Stay with Local Bind Mounts if:
- ✅ Single droplet deployment
- ✅ Small data size (<50GB)
- ✅ No plans to migrate between servers
- ✅ Cost-sensitive deployment
- ✅ Maximum performance needed

### Migrate to External Volume if:
- ✅ Need to move between droplets
- ✅ Large data size (>50GB)
- ✅ Want independent storage scaling
- ✅ Need better disaster recovery
- ✅ Multiple environments (staging/prod)
- ✅ Compliance requires data isolation

## Safety Features

All migration scripts include:
- ✅ **Pre-flight checks** - Validate system state before starting
- ✅ **Automatic backups** - Create backups before making changes
- ✅ **Comprehensive logging** - Detailed logs in `/var/log/`
- ✅ **Verification scripts** - Test migration success
- ✅ **Rollback capability** - Undo migrations if needed
- ✅ **Dry-run options** - Preview changes before applying (where applicable)

## Best Practices

### Before Any Migration

1. **Test in staging first** - Never migrate production without testing
2. **Take snapshots** - Create droplet snapshot in DO dashboard
3. **Backup databases** - Export critical data separately
4. **Document current state** - Note container configs, versions, ports
5. **Schedule downtime** - Inform users of maintenance window
6. **Check disk space** - Ensure sufficient space for migration
7. **Verify backups work** - Test restore procedures

### During Migration

1. **Monitor logs** - Watch for errors in real-time
2. **Don't interrupt** - Let scripts complete fully
3. **Keep terminal open** - Don't close SSH session mid-migration
4. **Have rollback ready** - Know the rollback commands before starting

### After Migration

1. **Run verification** - Use provided verification scripts
2. **Test all features** - Don't just check if it starts, test functionality
3. **Monitor performance** - Watch for issues in first 24 hours
4. **Keep backups** - Don't delete backups for at least 1 week
5. **Update documentation** - Record new architecture details

## Troubleshooting

### Migration Failed Mid-Process

1. **Don't panic** - Backups are created automatically
2. **Check logs** - Review migration log in `/var/log/`
3. **Run rollback** - Use `9-rollback-*.sh` script
4. **Investigate** - Determine root cause before retrying
5. **Get help** - Review script documentation

### Containers Won't Start After Migration

```bash
# Check container logs
docker logs openwebui-{container-name}

# Check mount points
docker inspect openwebui-{container-name} | grep -A 10 Mounts

# Verify directory permissions
ls -la /opt/openwebui/

# Test bind mounts manually
docker run --rm -v /opt/openwebui/test:/test alpine ls -la /test
```

### Data Appears Missing

```bash
# For bind mount migrations - check source
ls -la /opt/openwebui/

# For external volume migrations - check symlink
ls -la /opt/openwebui
readlink -f /opt/openwebui

# Verify volume is mounted
df -h | grep openwebui
mountpoint /mnt/openwebui-volume
```

## Support and Documentation

### Migration Logs
- Docker Volumes → Bind Mounts: `/var/log/openwebui-migration-*.log`
- Bind Mounts → External Volume: `/var/log/openwebui-migration-external-*.log`
- Rollback Operations: `/var/log/openwebui-rollback-*.log`

### Related Documentation
- [Multi-Tenant Setup Guide](../README.md)
- [Client Manager Documentation](../client-manager.sh)
- [Branding System](../setup/README.md)
- [Phase 1 Architecture](../docs/ARCHITECTURE.md)

### Getting Help

1. **Check specific migration README** - Detailed troubleshooting in each migration directory
2. **Review logs** - Most issues explained in log files
3. **Test verification** - Run verification scripts to identify issues
4. **Use rollback** - Safe to rollback and retry

## Quick Reference

### Migration 1: Docker Volumes → Bind Mounts
```bash
cd docker-volumes-TO-bind-mounts
./0-check-active-users.sh                    # Check for active users
./1-discover-deployments.sh                  # Find containers to migrate
./2-backup-deployment.sh <container>         # Backup before migration
./4-migrate-deployment.sh <container>        # Execute migration
./5-verify-migration.sh <container>          # Verify success
./9-rollback-deployment.sh <container>       # Rollback if needed
```

### Migration 2: Local Bind Mounts → External Volume
```bash
cd local-bind-mount-TO-external-volume
./1-create-and-attach-volume.sh              # Setup external volume
./2-migrate-to-external-volume.sh            # Migrate all data
./3-verify-external-volume.sh                # Verify migration
./9-rollback-to-local.sh                     # Rollback if needed
```

## Version History

- **v1.0** (2025-11-01) - Initial release with both migration paths
  - Docker volumes to bind mounts migration (legacy support)
  - Local bind mounts to external volume migration (scaling support)
  - Comprehensive verification and rollback scripts
  - Full documentation and troubleshooting guides

---

**Last Updated:** 2025-11-01
**Maintained By:** QuantaBase Open WebUI Team
