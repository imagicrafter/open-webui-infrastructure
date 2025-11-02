# Secrets & Environment Variable Management

**Multi-stage approach for secure deployment-specific configuration**

This directory contains documentation for managing custom environment variables and secrets across Open WebUI deployments, from simple filesystem-based POC to enterprise-grade Vault integration.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Current Implementation (Phase 1)](#current-implementation-phase-1)
- [Future Migration (Phase 2)](#future-migration-phase-2)
- [Documentation Index](#documentation-index)
- [Quick Start](#quick-start)
- [Migration Timeline](#migration-timeline)

---

## Overview

### The Problem

Open WebUI deployments need custom environment variables for:
- **Google Cloud Services**: Drive, Maps, Gmail API credentials
- **AI Services**: OpenAI, Anthropic, custom LLM endpoints
- **Custom Integrations**: Third-party APIs, webhooks, feature flags
- **Per-Client Configuration**: Client-specific settings without modifying core scripts

### The Solution

**Two-Phase Approach:**

```
┌─────────────────────────────────────────────────────────┐
│  Phase 1: Filesystem (POC/Development)                  │
│  ✅ Quick to implement                                  │
│  ✅ No external dependencies                            │
│  ✅ Easy to understand and debug                        │
│  ⚠️  Secrets stored in plain text files                 │
│  ⚠️  Manual backup/rotation required                    │
└─────────────────────────────────────────────────────────┘
                        │
                        │ Migration Path
                        ▼
┌─────────────────────────────────────────────────────────┐
│  Phase 2: HashiCorp Vault (Production)                  │
│  ✅ Enterprise-grade security                           │
│  ✅ Encrypted storage                                   │
│  ✅ Audit logging                                       │
│  ✅ Access control                                      │
│  ✅ Automatic rotation                                  │
│  ✅ High availability                                   │
└─────────────────────────────────────────────────────────┘
```

### Key Design Principle

**Abstraction Layer**: The same menu interface and workflow works for both phases. Only the backend storage changes.

---

## Current Implementation (Phase 1)

### Filesystem-Based Secrets Management

**Status:** ✅ **Ready for immediate use**

Custom environment variables are stored in plain text files at:
```
/opt/openwebui-configs/{container-name}.env
```

### Architecture

```
┌────────────────────────────────────────────────┐
│         client-manager.sh                      │
│  (User Interface - Menu Option 11)             │
└────────────────┬───────────────────────────────┘
                 │
                 ▼
┌────────────────────────────────────────────────┐
│      env-manager-menu.sh                       │
│  (Interactive Menu System)                     │
│  - View variables                              │
│  - Create/update variables                     │
│  - Delete variables                            │
│  - Validate format                             │
│  - Apply changes                               │
└────────────────┬───────────────────────────────┘
                 │
                 ▼
┌────────────────────────────────────────────────┐
│    env-manager-functions.sh                    │
│  (Core Operations)                             │
│  - set_env_var()                               │
│  - get_env_var()                               │
│  - delete_env_var()                            │
│  - list_env_var_names()                        │
│  - validate_env_file()                         │
└────────────────┬───────────────────────────────┘
                 │
                 ▼
┌────────────────────────────────────────────────┐
│  /opt/openwebui-configs/*.env                  │
│  (Filesystem Storage)                          │
│  Format: KEY=VALUE                             │
│  Permissions: 600 (owner only)                 │
└────────────────────────────────────────────────┘
                 │
                 ▼
┌────────────────────────────────────────────────┐
│     Docker Container                           │
│  Loaded via: --env-file flag                   │
│  Available to: Open WebUI application          │
└────────────────────────────────────────────────┘
```

### Features (Phase 1)

✅ **Interactive Menu**
- View all custom variables (values masked for security)
- Create/update variables
- Delete individual or all variables
- Direct file editing for advanced users
- Validation before applying

✅ **Security**
- File permissions: 600 (owner read/write only)
- Masked values in display
- Confirmation prompts for destructive operations
- Automatic backups before deletion

✅ **Validation**
- Format checking (KEY=VALUE)
- Variable name validation
- No duplicate keys
- Real-time error reporting

✅ **Integration**
- Seamless with client-manager.sh
- No changes to core deployment scripts
- Compatible with all deployment types
- Zero downtime for variable updates (just recreate container)

### Current Limitations

⚠️ **Security Concerns:**
- Secrets stored in plain text files
- No encryption at rest
- File-based access control only
- Manual backup required

⚠️ **Operational:**
- No centralized secrets management
- No audit trail
- Manual rotation process
- No secret versioning

---

## Future Migration (Phase 2)

### HashiCorp Vault Integration

**Status:** 🔄 **Planned - Migration path designed**

Replace filesystem storage with Vault while maintaining the same user interface.

### Architecture (Post-Migration)

```
┌────────────────────────────────────────────────┐
│         client-manager.sh                      │
│  (UNCHANGED - Same Menu Interface)             │
└────────────────┬───────────────────────────────┘
                 │
                 ▼
┌────────────────────────────────────────────────┐
│      secrets-manager.sh                        │
│  (NEW - Provider Abstraction Layer)            │
│  SECRETS_PROVIDER=filesystem|vault             │
└────────────────┬───────────────────────────────┘
                 │
         ┌───────┴────────┐
         ▼                ▼
┌─────────────────┐  ┌──────────────────┐
│ Filesystem      │  │ Vault Provider   │
│ Provider        │  │ (Production)     │
│ (POC/Dev)       │  │                  │
└─────────────────┘  └──────┬───────────┘
                            │
                            ▼
                  ┌──────────────────────┐
                  │  HashiCorp Vault     │
                  │  - Encrypted storage │
                  │  - Access control    │
                  │  - Audit logging     │
                  │  - Auto-rotation     │
                  │  - High availability │
                  └──────────────────────┘
```

### Vault Features

✅ **Security**
- Encrypted storage (AES-256)
- TLS for all communication
- AppRole authentication
- Fine-grained access control policies
- Automatic secret rotation
- MFA for admin access

✅ **Operations**
- Centralized secrets management
- Complete audit trail
- Secret versioning
- Automatic backups
- High availability (3-node cluster)
- Cloud KMS auto-unseal

✅ **Compliance**
- SOC 2 compliant
- GDPR compatible
- Audit logs for compliance
- Secret access tracking

### Migration Process

```
┌─────────────────────────────────────────────────────┐
│  Step 1: Deploy Vault                               │
│  - Install Vault on dedicated server                │
│  - Configure TLS/SSL                                │
│  - Initialize and unseal                            │
│  - Enable KV secrets engine                         │
└─────────────────────────────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────┐
│  Step 2: Configure Integration                      │
│  - Create AppRole for Open WebUI                    │
│  - Configure policies                               │
│  - Test connection                                  │
│  - Update secrets-config.conf                       │
└─────────────────────────────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────┐
│  Step 3: Migrate Secrets                            │
│  - Run: ./scripts/migrate-secrets-to-vault.sh       │
│  - Validates all .env files                         │
│  - Writes to Vault                                  │
│  - Verifies migration                               │
└─────────────────────────────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────┐
│  Step 4: Switch Provider                            │
│  - Update: SECRETS_PROVIDER=vault                   │
│  - Test with client-manager.sh                      │
│  - Verify variables load correctly                  │
└─────────────────────────────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────┐
│  Step 5: Cleanup                                    │
│  - Backup .env files                                │
│  - Delete filesystem secrets                        │
│  - Revoke root Vault token                         │
│  - Enable monitoring/alerts                         │
└─────────────────────────────────────────────────────┘
```

### Zero User Impact

**The menu stays exactly the same:**

```
╔════════════════════════════════════════╗
║         Env Management                 ║
╚════════════════════════════════════════╝

1) View All Custom Variables        ← Same menu
2) Create/Update Variable            ← Same workflow
3) Delete Variable                   ← Same interface
4) View Raw Env File                 ← (Shows Vault path)
5) Edit Env File (Advanced)          ← (Uses Vault CLI)
6) Validate Env File                 ← Same validation
7) Apply Changes (Recreate Container)← Same process
8) Delete All Custom Variables       ← Same confirmation
9) Return to Deployment Menu

Backend: Vault (was: Filesystem)     ← Only this changes
```

---

## Documentation Index

### Phase 1: Filesystem Implementation (Current)

| Document | Description | Lines | Status |
|----------|-------------|-------|--------|
| **ENV_MANAGEMENT_README.md** | Quick start guide, features, troubleshooting | 600+ | ✅ Ready |
| **ENV_MANAGEMENT_INTEGRATION_GUIDE.md** | Complete integration instructions with code examples | 600+ | ✅ Ready |

**Supporting Files:**
- `env-manager-functions.sh` - Core helper functions (334 lines)
- `env-manager-menu.sh` - Interactive menu (630 lines)
- `install-env-management.sh` - Automated installer (200+ lines)
- `test-env-management.sh` - Test suite with 27 tests (330+ lines)

### Phase 2: Vault Migration (Future)

| Document | Description | Lines | Status |
|----------|-------------|-------|--------|
| **VAULT_DEPLOYMENT_GUIDE.md** | Production Vault deployment guide | 1,500+ | ✅ Ready |

**What's Covered:**
- Quick start (dev mode)
- Production deployment with TLS
- High availability (3-node Raft cluster)
- Security hardening (AppRole, MFA, auto-unseal)
- Monitoring and audit
- Backup and disaster recovery
- Complete troubleshooting section

---

## Quick Start

### Install Environment Management (Phase 1)

```bash
cd /path/to/open-webui/mt

# Run automated installation
cd VAULT/scripts
./install-env-management.sh

# Follow manual steps in output
# (Add menu option 11 to client-manager.sh)

# Test installation
./test-env-management.sh
```

### Use Env Management

```bash
# Start client manager
./client-manager.sh

# Navigate to:
# 3) Manage Client Deployment
# → Select your client (e.g., openwebui-localhost-8081)
# → 11) Env Management

# Example: Add Google Drive credentials
# → 2) Create/Update Variable
#    Name: GOOGLE_DRIVE_CLIENT_ID
#    Value: your-client-id

# → 2) Create/Update Variable (again)
#    Name: GOOGLE_DRIVE_CLIENT_SECRET
#    Value: your-secret

# → 7) Apply Changes (Recreate Container)
#    Type: RECREATE
```

### Verify Variables Loaded

```bash
# Check env file
cat /opt/openwebui-configs/openwebui-localhost-8081.env

# Check in container
docker exec openwebui-localhost-8081 env | grep GOOGLE_DRIVE
```

---

## Migration Timeline

### Phase 1: Filesystem (Immediate)

**Timeline:** Available now
**Use For:** Development, testing, POC deployments
**Deployment:** 10 minutes
**Complexity:** Low

**Checklist:**
- [x] Core functions implemented
- [x] Interactive menu created
- [x] Integration guide written
- [x] Test suite completed
- [x] Installation script ready
- [ ] User completes integration
- [ ] User tests with deployment

### Phase 2: Vault Migration (Future)

**Timeline:** When needed (production scale-up)
**Use For:** Production, multi-team, compliance scenarios
**Deployment:** 2-4 hours
**Complexity:** Medium

**Trigger Conditions:**
- Scaling beyond 5+ deployments
- Multiple administrators
- Compliance requirements
- Automated secret rotation needed
- Audit trail required

**Prerequisites:**
- [ ] Dedicated server/droplet for Vault
- [ ] TLS certificates (Let's Encrypt or custom)
- [ ] Backup strategy defined
- [ ] Monitoring configured
- [ ] Team trained on unsealing

**Migration Checklist:**
- [ ] Deploy Vault (see VAULT_DEPLOYMENT_GUIDE.md)
- [ ] Configure AppRole authentication
- [ ] Test Vault connection
- [ ] Run migration script
- [ ] Switch provider in config
- [ ] Verify all deployments
- [ ] Backup and delete filesystem secrets
- [ ] Set up monitoring/alerts

---

## File Structure

```
mt/
├── client-manager.sh                      (modified - sourcing from VAULT/scripts/)
├── start-template.sh                      (modified - --env-file support)
│
└── VAULT/
    ├── README.md                          (this file - overview & roadmap)
    ├── VAULT_DEPLOYMENT_GUIDE.md          (production Vault setup)
    ├── ENV_MANAGEMENT_README.md           (Phase 1 quick start)
    ├── ENV_MANAGEMENT_INTEGRATION_GUIDE.md (Phase 1 integration)
    │
    └── scripts/
        ├── env-manager-functions.sh       (core functions)
        ├── env-manager-menu.sh            (interactive menu)
        ├── install-env-management.sh      (automated installer)
        └── test-env-management.sh         (test suite - 27 tests)

/opt/openwebui-configs/
└── *.env                                  (per-deployment secrets)
```

---

## Use Cases

### Development / Testing
**Recommendation:** Phase 1 (Filesystem)
- Quick setup
- Easy to debug
- Direct file access
- No external dependencies

### Small Production (1-5 clients)
**Recommendation:** Phase 1 (Filesystem)
- Simple to maintain
- Adequate security with file permissions
- Manual backup acceptable
- Single administrator

### Medium Production (5-20 clients)
**Recommendation:** Consider Phase 2 (Vault)
- Centralized management
- Audit trail helpful
- Multiple administrators
- Automated rotation beneficial

### Large Production (20+ clients)
**Recommendation:** Phase 2 (Vault)
- Enterprise security required
- Compliance needs
- High availability critical
- Team collaboration essential

---

## Security Comparison

| Feature | Filesystem (Phase 1) | Vault (Phase 2) |
|---------|---------------------|-----------------|
| **Encryption at rest** | ❌ Plain text | ✅ AES-256 |
| **Encryption in transit** | ❌ N/A | ✅ TLS |
| **Access control** | 🟡 File permissions | ✅ Policies + MFA |
| **Audit logging** | ❌ No | ✅ Complete |
| **Secret versioning** | ❌ No | ✅ Yes |
| **Automatic rotation** | ❌ Manual | ✅ Automatic |
| **High availability** | ❌ Single file | ✅ 3-node cluster |
| **Backup** | 🟡 Manual | ✅ Automated |
| **Compliance** | ❌ Limited | ✅ SOC2, GDPR |

Legend: ✅ Full support | 🟡 Partial | ❌ Not supported

---

## Common Questions

### Q: Can I start with filesystem and migrate to Vault later?
**A:** Yes! That's the designed migration path. The menu interface stays the same.

### Q: Will my deployments go down during migration?
**A:** No. Migration happens in the background. You switch the provider, then recreate containers one at a time.

### Q: What if I never need Vault?
**A:** The filesystem approach is perfectly fine for small deployments. You can use it indefinitely.

### Q: How long does Vault migration take?
**A:** Vault deployment: 2-4 hours. Secrets migration: 5-10 minutes. Testing: 30 minutes.

### Q: Can I use both filesystem and Vault simultaneously?
**A:** Technically yes (per-deployment provider), but not recommended. Pick one for consistency.

### Q: What happens to my secrets during container recreation?
**A:** Nothing! They're stored separately (filesystem or Vault) and loaded into the new container.

---

## Support & Resources

### Documentation
- **Phase 1 Quick Start**: `ENV_MANAGEMENT_README.md`
- **Phase 1 Integration**: `ENV_MANAGEMENT_INTEGRATION_GUIDE.md`
- **Phase 2 Vault Deployment**: `VAULT_DEPLOYMENT_GUIDE.md`

### Testing
```bash
# Test Phase 1 installation
./test-env-management.sh

# Test Vault connection (Phase 2)
source secrets-manager.sh
SECRETS_PROVIDER=vault secrets_test_connection
```

### Community
- **Issues**: https://github.com/imagicrafter/open-webui/issues
- **Discussions**: https://github.com/imagicrafter/open-webui/discussions

### HashiCorp Vault
- **Documentation**: https://developer.hashicorp.com/vault
- **Community**: https://discuss.hashicorp.com/c/vault

---

## Roadmap

### ✅ Completed
- [x] Phase 1: Filesystem implementation
- [x] Interactive menu system
- [x] Integration documentation
- [x] Test suite
- [x] Vault deployment guide

### 🔄 In Progress
- [ ] User testing and feedback
- [ ] Documentation refinements

### 📋 Planned
- [ ] Phase 2: Vault provider implementation
- [ ] Migration automation script
- [ ] secrets-manager.sh with provider abstraction
- [ ] AWS Secrets Manager provider (optional)
- [ ] Azure Key Vault provider (optional)

---

## Summary

This directory provides a **complete secrets management solution** for Open WebUI deployments:

**Today:** Use the filesystem-based system for quick, simple environment variable management.

**Tomorrow:** Migrate to Vault when you need enterprise-grade security, compliance, or scale.

**Key Benefit:** The same menu, same workflow, different backend. Your team doesn't need to learn new tools.

---

**Last Updated:** 2025-01-22
**Current Phase:** Phase 1 (Filesystem) - Ready for use
**Next Phase:** Phase 2 (Vault) - Documentation ready, implementation pending
**Status:** ✅ Production Ready (Phase 1)
