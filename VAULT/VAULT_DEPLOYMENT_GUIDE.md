# HashiCorp Vault Deployment Guide for Open WebUI

**Production-Ready Secrets Management**

This guide covers deploying HashiCorp Vault as the secrets backend for Open WebUI multi-tenant deployments, replacing filesystem-based secrets storage with enterprise-grade secrets management.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Quick Start (Development)](#quick-start-development)
4. [Production Deployment](#production-deployment)
5. [High Availability Setup](#high-availability-setup)
6. [Security Hardening](#security-hardening)
7. [Integration with Open WebUI](#integration-with-open-webui)
8. [Migration from Filesystem](#migration-from-filesystem)
9. [Backup and Disaster Recovery](#backup-and-disaster-recovery)
10. [Monitoring and Audit](#monitoring-and-audit)
11. [Troubleshooting](#troubleshooting)
12. [Production Checklist](#production-checklist)

---

## Architecture Overview

### Vault Integration Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Open WebUI Multi-Tenant Infrastructure                 │
│                                                          │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐        │
│  │ Client A   │  │ Client B   │  │ Client C   │        │
│  │ Container  │  │ Container  │  │ Container  │        │
│  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘        │
│        │                │                │               │
│        └────────────────┴────────────────┘               │
│                         │                                │
│                  client-manager.sh                       │
│                         │                                │
│                  secrets-manager.sh                      │
│                         │                                │
└─────────────────────────┼────────────────────────────────┘
                          │
                          ▼
            ┌─────────────────────────────┐
            │   HashiCorp Vault Cluster   │
            │                             │
            │  ┌──────────┐ ┌──────────┐ │
            │  │ Vault    │ │ Vault    │ │
            │  │ Node 1   │ │ Node 2   │ │
            │  │ (Active) │ │(Standby) │ │
            │  └────┬─────┘ └────┬─────┘ │
            │       │            │        │
            │  ┌────┴────────────┴─────┐ │
            │  │   Consul Storage      │ │
            │  │   (HA Backend)        │ │
            │  └───────────────────────┘ │
            └─────────────────────────────┘
```

### Secrets Hierarchy in Vault

```
openwebui/
├── deployments/
│   ├── openwebui-localhost-8081/
│   │   ├── GOOGLE_DRIVE_CLIENT_ID
│   │   ├── GOOGLE_DRIVE_CLIENT_SECRET
│   │   ├── GOOGLE_MAPS_API_KEY
│   │   └── OPENAI_API_KEY
│   ├── openwebui-chat-quantabase-io/
│   │   ├── GMAIL_API_CREDENTIALS
│   │   └── CUSTOM_VAR
│   └── ...
└── system/
    ├── oauth-credentials/
    └── database-credentials/
```

---

## Prerequisites

### System Requirements

**Minimum (Development):**
- 1 CPU core
- 512 MB RAM
- 1 GB disk space

**Recommended (Production):**
- 2+ CPU cores
- 2 GB RAM
- 10 GB SSD storage
- Separate server/droplet from Open WebUI

**Network Requirements:**
- Port 8200 (Vault API)
- Port 8201 (Vault cluster communication)
- TLS certificates (Let's Encrypt or custom CA)

### Software Dependencies

- **Operating System**: Ubuntu 22.04 LTS (recommended)
- **Docker** (optional, for containerized deployment)
- **jq**: JSON processor for CLI operations
- **curl**: API communication

```bash
sudo apt-get update
sudo apt-get install -y curl jq unzip
```

---

## Quick Start (Development)

**⚠️ WARNING: Dev mode is NOT secure. Vault is unsealed and runs in-memory.**

### 1. Install Vault

```bash
# Download latest Vault
VAULT_VERSION="1.15.4"
wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip

# Extract and install
unzip vault_${VAULT_VERSION}_linux_amd64.zip
sudo mv vault /usr/local/bin/

# Verify installation
vault version
```

### 2. Start Vault in Dev Mode

```bash
# Start Vault (dev mode - non-persistent)
vault server -dev -dev-root-token-id="dev-token" &

# Export environment variables
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='dev-token'

# Verify connection
vault status
```

### 3. Enable KV Secrets Engine

```bash
# Enable KV v2 secrets engine
vault secrets enable -path=openwebui kv-v2

# Test secret storage
vault kv put openwebui/deployments/test-deployment \
    TEST_VAR="test-value"

# Read secret
vault kv get openwebui/deployments/test-deployment
```

### 4. Configure Open WebUI Integration

```bash
# Create secrets config
sudo mkdir -p /opt/openwebui-configs
sudo cat > /opt/openwebui-configs/secrets-config.conf << 'EOF'
SECRETS_PROVIDER=vault
VAULT_ADDR=http://127.0.0.1:8200
VAULT_MOUNT_PATH=openwebui
VAULT_TOKEN=dev-token
EOF

# Test connection
cd /path/to/open-webui/mt
source secrets-manager.sh
secrets_test_connection
```

**Expected Output:**
```
✅ Vault provider: Connected to http://127.0.0.1:8200
```

---

## Production Deployment

### Architecture Decisions

**Storage Backend Options:**

| Backend | Use Case | Pros | Cons |
|---------|----------|------|------|
| **Consul** | Production HA | High availability, proven | Requires separate Consul cluster |
| **Integrated Storage (Raft)** | Production HA | Built-in, no dependencies | Newer (v1.4+) |
| **Filesystem** | Single node | Simple | No HA, single point of failure |

**Recommended: Integrated Storage (Raft)** - Built-in HA without external dependencies.

---

### Production Deployment Steps

#### 1. Server Preparation

**Option A: Dedicated Vault Server (Recommended)**

```bash
# Create new Digital Ocean droplet
# - Ubuntu 22.04 LTS
# - 2 GB RAM / 1 vCPU
# - Enable private networking
# - Enable IPv6

# SSH to new server
ssh root@vault-server-ip
```

**Option B: Co-located with Open WebUI**

```bash
# Use existing Open WebUI server
# Ensure adequate resources (add 1 GB RAM for Vault)
```

#### 2. Create Vault User

```bash
# Create dedicated vault user (security best practice)
sudo useradd --system --home /etc/vault.d --shell /bin/false vault
```

#### 3. Install Vault (Production)

```bash
# Download Vault
VAULT_VERSION="1.15.4"
cd /tmp
wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip

# Extract and install
unzip vault_${VAULT_VERSION}_linux_amd64.zip
sudo mv vault /usr/local/bin/
sudo chown root:root /usr/local/bin/vault

# Allow Vault to use mlock (prevents memory swapping)
sudo setcap cap_ipc_lock=+ep /usr/local/bin/vault

# Verify
vault version
```

#### 4. Configure Vault

**Create configuration directory:**

```bash
sudo mkdir -p /etc/vault.d
sudo mkdir -p /opt/vault/data
sudo chown -R vault:vault /etc/vault.d /opt/vault
```

**Create Vault configuration file:**

`/etc/vault.d/vault.hcl`:

```hcl
# Vault Production Configuration
# Storage: Integrated Storage (Raft)

# Storage backend - Raft (HA, no external dependencies)
storage "raft" {
  path    = "/opt/vault/data"
  node_id = "vault-node-1"

  # For HA: Add other nodes here
  # retry_join {
  #   leader_api_addr = "https://vault-node-2:8200"
  # }
}

# API listener
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = false
  tls_cert_file = "/etc/vault.d/tls/vault-cert.pem"
  tls_key_file  = "/etc/vault.d/tls/vault-key.pem"
}

# Cluster listener (for HA)
listener "tcp" {
  address       = "0.0.0.0:8201"
  tls_disable   = false
  tls_cert_file = "/etc/vault.d/tls/vault-cert.pem"
  tls_key_file  = "/etc/vault.d/tls/vault-key.pem"

  # Purpose: cluster communication
  purpose = "cluster"
}

# API address (advertised to clients)
api_addr = "https://vault.yourdomain.com:8200"

# Cluster address (for HA node communication)
cluster_addr = "https://vault-node-1.internal:8201"

# UI (optional but recommended)
ui = true

# Disable mlock if running in container
# disable_mlock = true

# Telemetry (optional - recommended for production)
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname          = true
}

# Log level
log_level = "info"
```

**Set permissions:**

```bash
sudo chmod 640 /etc/vault.d/vault.hcl
sudo chown vault:vault /etc/vault.d/vault.hcl
```

#### 5. Generate TLS Certificates

**Option A: Let's Encrypt (Recommended for Internet-facing)**

```bash
# Install certbot
sudo apt-get install -y certbot

# Generate certificate
sudo certbot certonly --standalone \
  -d vault.yourdomain.com \
  --non-interactive \
  --agree-tos \
  --email admin@yourdomain.com

# Copy certificates to Vault directory
sudo mkdir -p /etc/vault.d/tls
sudo cp /etc/letsencrypt/live/vault.yourdomain.com/fullchain.pem \
  /etc/vault.d/tls/vault-cert.pem
sudo cp /etc/letsencrypt/live/vault.yourdomain.com/privkey.pem \
  /etc/vault.d/tls/vault-key.pem
sudo chown vault:vault /etc/vault.d/tls/*
sudo chmod 600 /etc/vault.d/tls/*

# Set up auto-renewal
sudo crontab -e
# Add: 0 0 * * * certbot renew --quiet --deploy-hook "systemctl reload vault"
```

**Option B: Self-Signed Certificate (Internal/Testing)**

```bash
sudo mkdir -p /etc/vault.d/tls

# Generate self-signed certificate
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/vault.d/tls/vault-key.pem \
  -out /etc/vault.d/tls/vault-cert.pem \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=vault.yourdomain.com"

sudo chown vault:vault /etc/vault.d/tls/*
sudo chmod 600 /etc/vault.d/tls/*
```

#### 6. Create Systemd Service

`/etc/systemd/system/vault.service`:

```ini
[Unit]
Description=HashiCorp Vault - A tool for managing secrets
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl

[Service]
Type=notify
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
```

**Enable and start service:**

```bash
sudo systemctl daemon-reload
sudo systemctl enable vault
sudo systemctl start vault

# Check status
sudo systemctl status vault
```

#### 7. Initialize Vault

```bash
# Set Vault address
export VAULT_ADDR='https://vault.yourdomain.com:8200'

# If using self-signed cert, skip verification (dev only)
# export VAULT_SKIP_VERIFY=true

# Initialize Vault (generates unseal keys and root token)
vault operator init -key-shares=5 -key-threshold=3

# CRITICAL: Save output securely!
# Example output:
# Unseal Key 1: abc123...
# Unseal Key 2: def456...
# Unseal Key 3: ghi789...
# Unseal Key 4: jkl012...
# Unseal Key 5: mno345...
#
# Initial Root Token: s.xyz789...
```

**⚠️ CRITICAL SECURITY STEPS:**

1. **Save unseal keys in multiple secure locations:**
   - Password manager (1Password, LastPass)
   - Encrypted USB drive (offline)
   - Paper in physical safe
   - Split among trusted team members

2. **Save root token separately:**
   - DO NOT store with unseal keys
   - Revoke after creating admin users

3. **Never commit to git or store in plain text**

#### 8. Unseal Vault

Vault starts in sealed state. Must unseal after every restart.

```bash
# Unseal with 3 keys (threshold)
vault operator unseal <key-1>
vault operator unseal <key-2>
vault operator unseal <key-3>

# Check status
vault status
# Should show: Sealed: false
```

#### 9. Login with Root Token

```bash
# Login
vault login <root-token>

# Verify access
vault token lookup
```

#### 10. Enable Audit Logging

```bash
# Enable audit log
sudo mkdir -p /var/log/vault
sudo chown vault:vault /var/log/vault

vault audit enable file file_path=/var/log/vault/audit.log

# Rotate logs with logrotate
sudo cat > /etc/logrotate.d/vault << 'EOF'
/var/log/vault/audit.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    create 0640 vault vault
    sharedscripts
    postrotate
        systemctl reload vault > /dev/null 2>&1 || true
    endscript
}
EOF
```

#### 11. Enable Secrets Engine

```bash
# Enable KV v2 for Open WebUI secrets
vault secrets enable -path=openwebui kv-v2

# Configure max versions (optional)
vault write openwebui/config max_versions=10

# Test write
vault kv put openwebui/deployments/test \
  TEST_KEY="test-value"

# Verify
vault kv get openwebui/deployments/test
```

---

## High Availability Setup

### Architecture: 3-Node Raft Cluster

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ Vault       │     │ Vault       │     │ Vault       │
│ Node 1      │────▶│ Node 2      │────▶│ Node 3      │
│ (Leader)    │◀────│ (Follower)  │◀────│ (Follower)  │
└─────────────┘     └─────────────┘     └─────────────┘
       │                   │                   │
       └───────────────────┴───────────────────┘
                    Raft Consensus
```

### Node Setup

**Prerequisites:**
- 3 servers (droplets) in same region
- Private networking enabled
- Same Vault version on all nodes

### Configuration for Each Node

**Node 1 (`/etc/vault.d/vault.hcl`):**

```hcl
storage "raft" {
  path    = "/opt/vault/data"
  node_id = "vault-node-1"

  # Initially empty - add after initialization
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = false
  tls_cert_file = "/etc/vault.d/tls/vault-cert.pem"
  tls_key_file  = "/etc/vault.d/tls/vault-key.pem"
}

listener "tcp" {
  address     = "0.0.0.0:8201"
  tls_disable = false
  tls_cert_file = "/etc/vault.d/tls/vault-cert.pem"
  tls_key_file  = "/etc/vault.d/tls/vault-key.pem"
  purpose     = "cluster"
}

api_addr = "https://vault-node-1.yourdomain.com:8200"
cluster_addr = "https://10.0.0.1:8201"  # Private IP

ui = true
```

**Node 2 and Node 3:**
- Same configuration
- Change `node_id` to `vault-node-2` and `vault-node-3`
- Update `api_addr` and `cluster_addr` accordingly

### Initialize Cluster

**On Node 1 (Leader):**

```bash
# Initialize
vault operator init -key-shares=5 -key-threshold=3

# Unseal Node 1
vault operator unseal <key-1>
vault operator unseal <key-2>
vault operator unseal <key-3>

# Login
vault login <root-token>
```

**On Node 2 and Node 3:**

```bash
# Join cluster
vault operator raft join https://vault-node-1.yourdomain.com:8200

# Unseal each node
vault operator unseal <key-1>
vault operator unseal <key-2>
vault operator unseal <key-3>
```

**Verify cluster:**

```bash
# On any node
vault operator raft list-peers

# Expected output:
# Node        Address              State       Voter
# ----        -------              -----       -----
# node-1      10.0.0.1:8201        leader      true
# node-2      10.0.0.2:8201        follower    true
# node-3      10.0.0.3:8201        follower    true
```

### Load Balancer Configuration

**Using nginx (recommended):**

```nginx
upstream vault_backend {
    least_conn;
    server vault-node-1.yourdomain.com:8200 max_fails=3 fail_timeout=30s;
    server vault-node-2.yourdomain.com:8200 max_fails=3 fail_timeout=30s;
    server vault-node-3.yourdomain.com:8200 max_fails=3 fail_timeout=30s;
}

server {
    listen 443 ssl http2;
    server_name vault.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/vault.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/vault.yourdomain.com/privkey.pem;

    location / {
        proxy_pass https://vault_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support (for UI)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

---

## Security Hardening

### 1. AppRole Authentication (Recommended for client-manager.sh)

Replace root token with AppRole for automated access.

**Create policy:**

```bash
# Create policy file
vault policy write openwebui-secrets - <<EOF
# Allow full access to openwebui/* secrets
path "openwebui/data/deployments/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "openwebui/metadata/deployments/*" {
  capabilities = ["read", "list", "delete"]
}

# Allow listing deployments
path "openwebui/metadata/deployments" {
  capabilities = ["list"]
}
EOF
```

**Enable and configure AppRole:**

```bash
# Enable AppRole auth
vault auth enable approle

# Create role
vault write auth/approle/role/openwebui-manager \
    token_policies="openwebui-secrets" \
    token_ttl=1h \
    token_max_ttl=4h \
    secret_id_ttl=0 \
    secret_id_num_uses=0

# Get role_id (not secret - can be in config)
vault read auth/approle/role/openwebui-manager/role-id

# Generate secret_id (SECRET - store securely)
vault write -f auth/approle/role/openwebui-manager/secret-id
```

**Update secrets-config.conf:**

```bash
# /opt/openwebui-configs/secrets-config.conf
SECRETS_PROVIDER=vault
VAULT_ADDR=https://vault.yourdomain.com:8200
VAULT_MOUNT_PATH=openwebui

# AppRole authentication (more secure than root token)
VAULT_ROLE_ID=your-role-id
VAULT_SECRET_ID=your-secret-id
```

**Update secrets-manager.sh to use AppRole:**

Add to `_vault_load_token()` function:

```bash
_vault_load_token() {
    if [ -z "$VAULT_TOKEN" ]; then
        # Try AppRole auth if role_id and secret_id are set
        if [ -n "$VAULT_ROLE_ID" ] && [ -n "$VAULT_SECRET_ID" ]; then
            VAULT_TOKEN=$(vault write -field=token auth/approle/login \
                role_id="$VAULT_ROLE_ID" \
                secret_id="$VAULT_SECRET_ID")
        elif [ -f "$VAULT_TOKEN_FILE" ]; then
            VAULT_TOKEN=$(cat "$VAULT_TOKEN_FILE")
        fi
    fi
}
```

### 2. Revoke Root Token

```bash
# After setting up AppRole
vault token revoke <root-token>
```

### 3. Enable MFA for Admin Access

```bash
# Enable TOTP MFA
vault auth enable userpass

# Create admin user
vault write auth/userpass/users/admin \
    password="secure-password" \
    policies="admin"

# Configure MFA
vault write sys/mfa/method/totp/my_totp \
    issuer=Vault \
    period=30 \
    key_size=32 \
    algorithm=SHA256
```

### 4. Network Security

**Firewall rules (UFW):**

```bash
# Allow Vault API only from Open WebUI server
sudo ufw allow from OPENWEBUI_SERVER_IP to any port 8200 proto tcp

# Allow cluster communication (HA only, private network)
sudo ufw allow from VAULT_NODE_2_PRIVATE_IP to any port 8201 proto tcp
sudo ufw allow from VAULT_NODE_3_PRIVATE_IP to any port 8201 proto tcp

# SSH
sudo ufw allow 22/tcp

# Enable firewall
sudo ufw enable
```

### 5. Auto-Unseal with Cloud KMS

**AWS KMS Example:**

```hcl
# In vault.hcl, replace storage section with:
seal "awskms" {
  region     = "us-east-1"
  kms_key_id = "your-kms-key-id"
}
```

**Benefits:**
- Vault unseals automatically on restart
- No manual intervention required
- Unseal keys managed by cloud provider

---

## Integration with Open WebUI

### Configure secrets-manager.sh

`/opt/openwebui-configs/secrets-config.conf`:

```bash
# Secrets Manager Configuration
SECRETS_PROVIDER=vault

# Vault Configuration
VAULT_ADDR=https://vault.yourdomain.com:8200
VAULT_MOUNT_PATH=openwebui

# Authentication (AppRole - recommended)
VAULT_ROLE_ID=your-role-id-here
VAULT_SECRET_ID=your-secret-id-here

# OR Token-based (less secure)
# VAULT_TOKEN_FILE=/opt/openwebui-configs/.vault-token
```

### Test Connection

```bash
cd /path/to/open-webui/mt
source secrets-manager.sh
secrets_test_connection
```

**Expected output:**
```
✅ Vault provider: Connected to https://vault.yourdomain.com:8200
```

### Set First Secret

```bash
# Using secrets-manager.sh
secrets_set "openwebui-localhost-8081" "GOOGLE_DRIVE_CLIENT_ID" "your-client-id"
secrets_set "openwebui-localhost-8081" "GOOGLE_DRIVE_CLIENT_SECRET" "your-secret"

# Verify
secrets_list "openwebui-localhost-8081"
```

---

## Migration from Filesystem

### Pre-Migration Checklist

- [ ] Vault is running and accessible
- [ ] AppRole authentication configured
- [ ] secrets-manager.sh tested with Vault
- [ ] Backup of existing .env files created

### Migration Process

**1. Backup existing secrets:**

```bash
cd /opt/openwebui-configs
tar czf secrets-backup-$(date +%Y%m%d-%H%M%S).tar.gz *.env
mv secrets-backup-*.tar.gz ~/backups/
```

**2. Test Vault connection:**

```bash
cd /path/to/open-webui/mt
source secrets-manager.sh

# Override provider for testing
SECRETS_PROVIDER=vault secrets_test_connection
```

**3. Run migration script:**

```bash
cd /path/to/open-webui/mt
./scripts/migrate-secrets-to-vault.sh
```

**Script will:**
1. Read all .env files
2. Parse key-value pairs
3. Write to Vault at `openwebui/deployments/{deployment-name}`
4. Verify each write
5. Generate migration report

**4. Update configuration:**

```bash
# Edit /opt/openwebui-configs/secrets-config.conf
sed -i 's/SECRETS_PROVIDER=filesystem/SECRETS_PROVIDER=vault/' \
  /opt/openwebui-configs/secrets-config.conf
```

**5. Verify migration:**

```bash
# Test reading from Vault
./client-manager.sh

# Select deployment → Option 11 → View secrets
# Should show: Provider: vault
```

**6. Test deployment restart:**

```bash
# Restart a test deployment
docker restart openwebui-localhost-8081

# Check logs
docker logs openwebui-localhost-8081

# Verify custom env vars loaded
docker exec openwebui-localhost-8081 env | grep GOOGLE_DRIVE
```

**7. Clean up filesystem secrets:**

```bash
# ONLY after verification!
# Keep backup for 30 days before permanent deletion
sudo rm /opt/openwebui-configs/*.env
```

---

## Backup and Disaster Recovery

### Automated Backup Script

`/opt/vault-backup/backup-vault.sh`:

```bash
#!/bin/bash

BACKUP_DIR="/opt/vault-backup/snapshots"
RETENTION_DAYS=30
DATE=$(date +%Y%m%d-%H%M%S)

mkdir -p "$BACKUP_DIR"

# Take snapshot
vault operator raft snapshot save "${BACKUP_DIR}/vault-snapshot-${DATE}.snap"

# Compress
gzip "${BACKUP_DIR}/vault-snapshot-${DATE}.snap"

# Delete old backups
find "$BACKUP_DIR" -name "*.snap.gz" -mtime +${RETENTION_DAYS} -delete

# Upload to cloud storage (optional)
# aws s3 cp "${BACKUP_DIR}/vault-snapshot-${DATE}.snap.gz" \
#   s3://your-backup-bucket/vault/
```

**Schedule with cron:**

```bash
sudo crontab -e
# Add: 0 2 * * * /opt/vault-backup/backup-vault.sh
```

### Restore from Backup

```bash
# Stop Vault
sudo systemctl stop vault

# Restore snapshot
vault operator raft snapshot restore /path/to/backup.snap

# Start Vault
sudo systemctl start vault

# Unseal
vault operator unseal <key-1>
vault operator unseal <key-2>
vault operator unseal <key-3>
```

### Disaster Recovery Scenarios

**Scenario 1: Single node failure (HA cluster)**
- **Impact**: None - automatic failover
- **Action**: Replace failed node, join cluster, unseal

**Scenario 2: Complete cluster failure**
- **Impact**: Service down
- **Recovery**:
  1. Restore from snapshot
  2. Unseal all nodes
  3. Verify data integrity

**Scenario 3: Lost unseal keys**
- **Impact**: Cannot unseal Vault
- **Recovery**:
  - If using cloud KMS auto-unseal: Restart Vault (auto-unseals)
  - If manual unsealing: Use backup unseal keys
  - **No recovery if all keys lost** - data is encrypted and inaccessible

---

## Monitoring and Audit

### Prometheus Metrics

Vault exposes Prometheus metrics at `/v1/sys/metrics`.

**Prometheus configuration:**

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'vault'
    metrics_path: '/v1/sys/metrics'
    params:
      format: ['prometheus']
    bearer_token: 'vault-token-with-metrics-read'
    static_configs:
      - targets: ['vault.yourdomain.com:8200']
```

**Key metrics to monitor:**

- `vault_core_unsealed` - Seal status (should be 1)
- `vault_runtime_alloc_bytes` - Memory usage
- `vault_runtime_num_goroutines` - Active operations
- `vault_audit_log_request` - Audit log write rate
- `vault_core_handle_request` - Request rate

### Grafana Dashboard

Import dashboard ID: 12904 (HashiCorp Vault)

**Custom alerts:**

```yaml
# Alert: Vault sealed
- alert: VaultSealed
  expr: vault_core_unsealed == 0
  for: 1m
  annotations:
    summary: "Vault is sealed"
    description: "Vault instance {{ $labels.instance }} is sealed"

# Alert: High memory usage
- alert: VaultHighMemory
  expr: vault_runtime_alloc_bytes > 1e9  # 1GB
  for: 5m
  annotations:
    summary: "Vault high memory usage"
```

### Audit Log Analysis

**View recent audit events:**

```bash
# Last 100 audit events
tail -100 /var/log/vault/audit.log | jq '.'

# Filter by specific deployment
grep "openwebui-localhost-8081" /var/log/vault/audit.log | jq '.'

# Count requests by type
jq -r '.request.operation' /var/log/vault/audit.log | sort | uniq -c
```

**Common audit queries:**

```bash
# Find all secret reads in last hour
awk -v date=$(date -d '1 hour ago' +%s) \
  '$1 > date' /var/log/vault/audit.log | \
  jq 'select(.request.operation == "read")'

# Track who accessed specific deployment
jq 'select(.request.path | contains("deployments/openwebui-chat-quantabase-io"))' \
  /var/log/vault/audit.log
```

### Health Check Endpoint

```bash
# Check Vault health
curl -s https://vault.yourdomain.com:8200/v1/sys/health | jq '.'

# Response codes:
# 200: Unsealed and active
# 429: Unsealed and standby
# 472: Disaster recovery mode
# 473: Performance standby
# 501: Not initialized
# 503: Sealed
```

---

## Troubleshooting

### Common Issues

#### 1. Cannot Connect to Vault

**Symptoms:**
```
❌ Vault provider: Cannot connect to http://127.0.0.1:8200
```

**Solutions:**

```bash
# Check Vault is running
sudo systemctl status vault

# Check port is listening
sudo netstat -tlnp | grep 8200

# Check firewall
sudo ufw status

# Test with curl
curl -k https://vault.yourdomain.com:8200/v1/sys/health
```

#### 2. Vault is Sealed

**Symptoms:**
```
Error: Vault is sealed
```

**Solution:**

```bash
# Unseal Vault
vault operator unseal <key-1>
vault operator unseal <key-2>
vault operator unseal <key-3>

# Check status
vault status
```

#### 3. Permission Denied

**Symptoms:**
```
Error: permission denied
```

**Solutions:**

```bash
# Check token capabilities
vault token capabilities openwebui/deployments/test

# Should show: create, read, update, delete, list

# Re-authenticate
vault login <token>

# Or regenerate AppRole secret_id
vault write -f auth/approle/role/openwebui-manager/secret-id
```

#### 4. High Memory Usage

**Symptoms:**
- Vault OOM killed
- Slow performance

**Solutions:**

```bash
# Check memory usage
docker stats vault  # If containerized
ps aux | grep vault

# Increase storage limits (in vault.hcl)
# max_lease_ttl = "168h"

# Clean up old leases
vault lease revoke -prefix auth/approle/

# Restart Vault
sudo systemctl restart vault
```

#### 5. Cluster Node Not Joining

**Symptoms:**
```
Error joining raft cluster: connection refused
```

**Solutions:**

```bash
# Check cluster_addr is correct
vault status | grep "Cluster Address"

# Verify TLS certificates
openssl s_client -connect vault-node-1:8201

# Check firewall allows 8201
sudo ufw allow from VAULT_NODE_IP to any port 8201

# Re-join cluster
vault operator raft join https://vault-node-1:8200
```

### Debug Mode

Enable debug logging:

```bash
# Edit /etc/vault.d/vault.hcl
log_level = "debug"

# Restart
sudo systemctl restart vault

# View logs
sudo journalctl -u vault -f
```

### Recovery Mode

For emergency recovery:

```bash
# Start in recovery mode (bypass seal check)
vault operator generate-root -init

# Follow prompts to generate new root token
# Use unseal keys to decrypt OTP
```

---

## Production Checklist

### Pre-Deployment

- [ ] Server requirements met (CPU, RAM, disk)
- [ ] TLS certificates generated (Let's Encrypt or custom)
- [ ] Firewall configured (ports 8200, 8201)
- [ ] Backup storage configured (local + cloud)
- [ ] Monitoring configured (Prometheus + Grafana)

### Vault Configuration

- [ ] Vault installed and configured
- [ ] Systemd service created and enabled
- [ ] Audit logging enabled
- [ ] Secrets engine enabled (`openwebui/`)
- [ ] AppRole authentication configured
- [ ] Root token revoked

### High Availability (Optional)

- [ ] 3+ nodes deployed
- [ ] Raft cluster initialized
- [ ] All nodes unsealed
- [ ] Load balancer configured
- [ ] Cluster health verified

### Security Hardening

- [ ] TLS enabled for all connections
- [ ] Network firewall configured
- [ ] MFA enabled for admin access
- [ ] Auto-unseal configured (cloud KMS)
- [ ] Audit logs rotated daily
- [ ] Least-privilege policies created

### Integration Testing

- [ ] secrets-manager.sh tested with Vault
- [ ] Test deployment created with custom secrets
- [ ] Container restart verified (env vars loaded)
- [ ] Migration from filesystem completed
- [ ] Backup/restore tested

### Monitoring

- [ ] Prometheus scraping Vault metrics
- [ ] Grafana dashboard configured
- [ ] Alerts configured (seal, memory, errors)
- [ ] Audit log analysis tools set up
- [ ] Health check endpoint monitored

### Documentation

- [ ] Unseal keys stored securely (3+ locations)
- [ ] Root token backup (separate from keys)
- [ ] AppRole credentials documented
- [ ] Recovery procedures documented
- [ ] Team trained on unsealing process

### Ongoing Maintenance

- [ ] Daily backups automated
- [ ] Weekly backup verification
- [ ] Monthly security updates
- [ ] Quarterly disaster recovery drills
- [ ] Audit log review (weekly)

---

## Additional Resources

### Official Documentation

- **Vault Documentation**: https://www.vaultproject.io/docs
- **Production Hardening**: https://developer.hashicorp.com/vault/tutorials/operations/production-hardening
- **Raft Storage**: https://developer.hashicorp.com/vault/docs/configuration/storage/raft
- **AppRole Auth**: https://developer.hashicorp.com/vault/docs/auth/approle

### Community Resources

- **Vault GitHub**: https://github.com/hashicorp/vault
- **HashiCorp Learn**: https://developer.hashicorp.com/vault/tutorials
- **Vault Community Forum**: https://discuss.hashicorp.com/c/vault

### Open WebUI Integration

- **secrets-manager.sh**: `../secrets-manager.sh`
- **Migration Script**: `../scripts/migrate-secrets-to-vault.sh`
- **Client Manager**: `../client-manager.sh`

---

## Support

For issues specific to Open WebUI + Vault integration:
- Open an issue: https://github.com/imagicrafter/open-webui/issues
- Review: `mt/VAULT/` directory for additional documentation

For Vault product issues:
- HashiCorp Support: https://support.hashicorp.com/
- Community Forum: https://discuss.hashicorp.com/

---

**Last Updated**: 2025-01-22
**Vault Version**: 1.15.4
**Tested On**: Ubuntu 22.04 LTS, Digital Ocean Droplets
