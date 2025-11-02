# Phase 1 - Multi-Tenant Volume Mount Architecture

**Date:** 2025-10-31
**Branch:** `feature/volume-mount-prototype`
**Status:** ✅ **PRODUCTION VALIDATED**

---

## What Was Built

Phase 1 replaces Docker volumes with **bind mounts** for Open WebUI deployments, enabling:
- Portable data storage in `/opt/openwebui/{client-id}/`
- Simple backup and migration (standard file operations)
- Multi-tenant isolation via CLIENT_ID system
- Direct access to deployment data on host filesystem

---

## Architecture

### CLIENT_ID System

Every deployment gets a unique **CLIENT_ID** from its sanitized FQDN:

```
Input:
  Subdomain: chat
  FQDN: chat.imagicrafter.ai

Generated:
  CLIENT_ID: chat-imagicrafter-ai  (dots → dashes)
  Container: openwebui-chat-imagicrafter-ai
  Directory: /opt/openwebui/chat-imagicrafter-ai/
```

This prevents collisions when multiple clients use the same subdomain.

### Directory Structure

```
/opt/openwebui/
├── defaults/
│   └── static/              # Default assets (extracted once)
├── chat-imagicrafter-ai/
│   ├── data/                # Database, uploads, configs
│   └── static/              # Branding assets
└── chat-lawnloonies-com/
    ├── data/                # Separate database
    └── static/              # Separate branding
```

### Bind Mounts

Each container mounts its isolated directories:

```bash
-v /opt/openwebui/chat-imagicrafter-ai/data:/app/backend/data
-v /opt/openwebui/chat-imagicrafter-ai/static:/app/backend/open_webui/static
```

**Benefits:**
- Simple backup: `tar -czf backup.tar.gz /opt/openwebui/client-id/`
- Easy migration: copy directory to new server
- Direct file access for troubleshooting
- Custom branding without container access

---

## Components

### 1. Server Setup (`quick-setup.sh`)

Provisions server with Phase 1 architecture:

```bash
# Production server:
curl -fsSL https://raw.githubusercontent.com/imagicrafter/open-webui/main/mt/setup/quick-setup.sh | bash -s -- "" "production"

# Test server:
curl -fsSL https://raw.githubusercontent.com/imagicrafter/open-webui/main/mt/setup/quick-setup.sh | bash -s -- "" "test"
```

**What it does:**
- Creates qbmgr user with Docker access
- Clones repository (main or release branch)
- Creates `/opt/openwebui/defaults/` structure
- Extracts default static assets
- Configures 2GB swap for container stability

### 2. Client Manager (`client-manager.sh`)

Interactive deployment management:

```bash
cd ~/open-webui/mt
./client-manager.sh
```

**Features:**
- List all deployments
- Create new deployment (guided prompts)
- Start/stop/restart containers
- View logs
- Configure nginx and SSL

**UX Improvements:**
- Clear FQDN prompts with examples
- Validation to prevent container name collisions
- Auto-detects nginx mode (containerized vs host)
- Finds next available port automatically

### 3. Deployment Script (`start-template.sh`)

Creates isolated deployment with bind mounts:

```bash
# Called by client-manager.sh, or manually:
./mt/start-template.sh chat 8082 chat.imagicrafter.ai openwebui-chat-imagicrafter-ai chat.imagicrafter.ai
```

**What it does:**
1. Extracts CLIENT_ID from container name
2. Creates `/opt/openwebui/{CLIENT_ID}/{data,static}`
3. Initializes static assets from defaults
4. Launches container with bind mounts
5. Configures health checks and memory limits

**Key features:**
- Validates directory creation before mounting
- Memory limits: 700MB hard, 600MB reservation
- Health checks: 10s interval, 3 retries
- Supports port mapping or nginx network modes

### 4. Default Asset Extraction (`extract-default-static.sh`)

Extracts Open WebUI's static assets to host:

```bash
# Automatic during quick-setup.sh
# Or manually:
bash mt/setup/lib/extract-default-static.sh
```

Pulls logos, favicons, fonts from Docker image to `/opt/openwebui/defaults/static/`.

### 5. Cleanup Script (`cleanup-for-rebuild.sh`)

Restores server to clean state:

```bash
sudo bash mt/setup/cleanup-for-rebuild.sh
```

Removes containers, volumes, `/opt/openwebui/`, nginx configs. Preserves Docker, SSH, and system packages.

---

## Production Usage

### Deploy New Client

```bash
# 1. Provision server
curl -fsSL https://raw.githubusercontent.com/imagicrafter/open-webui/main/mt/setup/quick-setup.sh | bash -s -- "" "production"

# 2. Create deployment
ssh qbmgr@your-server
cd ~/open-webui/mt
./client-manager.sh
# Select: 2) Create New Deployment
# Enter subdomain: chat
# Enter FQDN: chat.yourclient.com

# 3. Configure DNS (A record)
# chat.yourclient.com → your-server-ip

# 4. Configure nginx + SSL
# Use client-manager.sh option 5 or manual nginx config

# 5. Verify
docker ps | grep chat-yourclient-com
# Open https://chat.yourclient.com
```

### Backup Deployment

```bash
docker stop openwebui-chat-imagicrafter-ai
tar -czf backup.tar.gz /opt/openwebui/chat-imagicrafter-ai/
```

### Restore Deployment

```bash
tar -xzf backup.tar.gz -C /
docker start openwebui-chat-imagicrafter-ai
```

### Migrate to New Server

```bash
# Old server:
docker stop openwebui-chat-imagicrafter-ai
tar -czf deployment.tar.gz /opt/openwebui/chat-imagicrafter-ai/

# New server:
tar -xzf deployment.tar.gz -C /
# Recreate container with client-manager.sh
```

### Custom Branding

```bash
# Replace logo on host
cp custom-logo.png /opt/openwebui/chat-imagicrafter-ai/static/logo.png
docker restart openwebui-chat-imagicrafter-ai
```

---

## Multi-Tenant Examples

### Same Subdomain, Different Domains

```
Company A: chat.company-a.com
  → Container: openwebui-chat-company-a-com
  → Directory: /opt/openwebui/chat-company-a-com/

Company B: chat.company-b.com
  → Container: openwebui-chat-company-b-com
  → Directory: /opt/openwebui/chat-company-b-com/

Result: Completely isolated, no collision
```

### Multiple Subdomains, Same Domain

```
Chat:    chat.acme-corp.com    → openwebui-chat-acme-corp-com
Support: support.acme-corp.com → openwebui-support-acme-corp-com
Admin:   admin.acme-corp.com   → openwebui-admin-acme-corp-com

Result: All isolated with unique CLIENT_IDs
```

---

## Validation Results

**Server:** 159.65.240.58
**Deployments:** chat.imagicrafter.ai, chat.lawnloonies.com
**Test:** Two deployments with same subdomain ("chat"), different domains

**All checks passed:**
- ✅ Unique CLIENT_ID directories (no shared storage)
- ✅ Bind mounts operational (not Docker volumes)
- ✅ Correct environment variables (CLIENT_ID, SUBDOMAIN, FQDN)
- ✅ Separate databases (different inodes, true isolation)
- ✅ Static assets initialized (19 files each)
- ✅ Both containers healthy (4+ hours uptime)

---

## Resource Management

**Memory per container:**
- 700MB hard limit (prevents excessive usage)
- 600MB reservation (triggers garbage collection)
- 1400MB swap (2x memory, uses host swap)

**Capacity:**
- 2GB droplet: 2 containers
- 4GB droplet: 5 containers
- 8GB droplet: 11 containers

**Disk per deployment:**
- Fresh: ~3MB (264KB database + 2MB assets)
- With chat history: 100MB-1GB typical

---

## Phase 0 vs Phase 1

| Aspect | Phase 0 | Phase 1 |
|--------|---------|---------|
| Storage | Docker volumes | Bind mounts |
| Location | `/var/lib/docker/volumes/` | `/opt/openwebui/{client-id}/` |
| Backup | `docker volume` commands | `tar -czf` |
| Migration | Export/import volumes | Copy directory |
| Branding | Complex (in-container) | Simple (edit host files) |
| Setup | Manual | Automated |

---

## Ready for Phase 3

**Phase 1:** ✅ Complete
**Phase 2:** ⏸️ Deferred
**Next:** Phase 3 - nginx + SSL Automation

Phase 3 will add automated nginx configuration, Let's Encrypt SSL, and DNS integration.

---

**Ready for merge:** `feature/volume-mount-prototype` → `main`
