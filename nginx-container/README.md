# Containerized nginx for Open WebUI Multi-Tenant Setup

This directory contains tools and scripts for deploying nginx as a Docker container to serve as a reverse proxy for multiple Open WebUI instances.

## 🚀 Quick Start (Automated)

**The easiest way to set up nginx and SSL for clients is through the client-manager.sh script**, which automates the entire process:

```bash
cd /path/to/open-webui/mt
./client-manager.sh

# Choose option 5: "Generate nginx config for existing client"
# The script will:
# - Auto-detect if SSL certificates exist
# - Deploy HTTP-only config (if no SSL) or HTTPS config (if SSL exists)
# - Auto-generate SSL certificates with certbot
# - Auto-update config after SSL obtained
# - Auto-test and reload nginx
```

**For troubleshooting or manual setup**, see [MANUAL_SSL_SETUP.md](MANUAL_SSL_SETUP.md).

## Overview

**Why Containerized nginx?**
- **Isolation**: nginx runs in its own container, separate from the host system
- **Portability**: Easy to move the entire setup between servers
- **Container-to-Container Communication**: Direct networking between nginx and Open WebUI containers without exposing ports to the host
- **Simplified Management**: All configuration in one directory structure
- **Docker Network Benefits**: Automatic DNS resolution, network isolation, and service discovery
- **Automated SSL Setup**: Built-in integration with Let's Encrypt for HTTPS

## How SSL Setup Works

This setup uses **Let's Encrypt** with the **HTTP-01 challenge method** for automated SSL certificate issuance and renewal.

### Let's Encrypt HTTP-01 Challenge Process

The SSL certificate process works as follows:

1. **Certbot requests certificate** from Let's Encrypt for your domain (e.g., `chat.quantabase.io`)
2. **Let's Encrypt validates domain ownership** by requiring a challenge file to be served at:
   ```
   http://yourdomain.com/.well-known/acme-challenge/RANDOM_TOKEN
   ```
3. **nginx serves the challenge file** from the mounted webroot directory (`/opt/openwebui-nginx/webroot/`)
4. **Let's Encrypt verifies ownership** by making an HTTP request to the challenge URL
5. **Certificate is issued** and installed automatically

### Requirements for SSL to Work

For Let's Encrypt to successfully issue certificates, you need:

- ✅ **Domain DNS** pointing to your droplet IP address (A record)
- ✅ **Port 80 accessible** - Required for HTTP-01 challenge validation
- ✅ **Port 443 accessible** - Required for HTTPS traffic after certificate issuance
- ✅ **nginx webroot** configured at `/opt/openwebui-nginx/webroot/`
- ✅ **DNS propagation complete** - Domain must resolve before requesting certificate

### Why This Works with Any DNS Provider

The Let's Encrypt process is **domain-registrar agnostic** - it doesn't matter where your domain is hosted (GoDaddy, Cloudflare, Namecheap, etc.) as long as:

- The domain's DNS A record points to your server's IP
- HTTP traffic on port 80 reaches your nginx container
- The domain is publicly resolvable

This means you can use domains from **any DNS provider** with this setup. See the "DNS Provider Compatibility" section below for provider-specific configuration details.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         Host System                          │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │           openwebui-network (Custom Bridge)            │ │
│  │                                                         │ │
│  │  ┌──────────────────┐      ┌──────────────────┐       │ │
│  │  │  openwebui-nginx │      │  openwebui-chat- │       │ │
│  │  │                  │─────▶│  quantabase-io   │       │ │
│  │  │  :80, :443       │      │  :8080           │       │ │
│  │  └──────────────────┘      └──────────────────┘       │ │
│  │                                                         │ │
│  │                            ┌──────────────────┐       │ │
│  │                            │  openwebui-docs- │       │ │
│  │                            │  example-com     │       │ │
│  │                            │  :8080           │       │ │
│  │                            └──────────────────┘       │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  Port Mappings:                                              │
│  - 80:80   (HTTP)  → openwebui-nginx                        │
│  - 443:443 (HTTPS) → openwebui-nginx                        │
└─────────────────────────────────────────────────────────────┘
```

**Key Components:**
- **openwebui-nginx**: Main nginx reverse proxy container
- **openwebui-network**: Custom Docker bridge network for inter-container communication
- **Open WebUI Containers**: Named using FQDN pattern (`openwebui-DOMAIN-WITH-DASHES`)
- **Configuration**: Mounted from `/opt/openwebui-nginx/` on host

## Directory Structure

```
mt/nginx-container/
├── README.md                                    # This file
├── MANUAL_SSL_SETUP.md                          # Comprehensive troubleshooting guide
├── deploy-nginx-container.sh                    # Main deployment script
├── create-ssl-options.sh                        # Generate SSL configuration files
├── nginx-template-containerized.conf            # HTTPS nginx config template (with SSL)
└── nginx-template-containerized-http-only.conf  # HTTP-only nginx config template (pre-SSL)
```

**Note**: The client-manager.sh script (in mt/) handles all configuration generation and deployment automatically.

## Prerequisites

Before deploying containerized nginx:

- [ ] Docker installed and running
- [ ] Root or sudo access
- [ ] Existing Open WebUI containers (optional - can deploy nginx first)
- [ ] Domain names configured and pointing to server
- [ ] SSL certificates (if using HTTPS immediately)
- [ ] Ports 80 and 443 available on host

**Check Port Availability:**
```bash
# Check if ports are in use
sudo netstat -tlnp | grep -E ':80|:443'

# If host nginx is running, you'll need to stop it first
sudo systemctl status nginx
```

## DNS Provider Compatibility

The nginx SSL setup works with **any DNS provider** - the configuration is provider-agnostic. This section documents tested providers and their specific configuration requirements.

> **Note**: This section will be updated as additional DNS providers are tested and verified.

### Tested DNS Providers

| Provider | Status | Proxy Feature | Notes |
|----------|--------|---------------|-------|
| **Cloudflare** | ✅ Verified | Yes (optional) | Works with or without proxy enabled |
| **GoDaddy** | ✅ Verified | No | Direct DNS only, no proxy feature |

### Key Differences Between DNS Providers

| Aspect | Cloudflare | GoDaddy |
|--------|-----------|---------|
| **Primary Service** | CDN + Proxy + DNS | Domain Registrar + DNS |
| **Proxy Feature** | Yes (orange cloud) - proxies traffic | No - direct DNS only |
| **SSL Options** | Flexible SSL, Full SSL, Full (Strict) | N/A - just DNS |
| **IP Visibility** | Can hide origin IP | Shows real droplet IP |
| **DNS Propagation** | Fast (seconds to minutes) | Standard (minutes to hours) |
| **DDoS Protection** | Yes (when proxied) | No |
| **Caching** | Yes (when proxied) | No |

### Cloudflare Configuration

Cloudflare offers two modes: **Proxied** (orange cloud) or **DNS only** (gray cloud).

#### Option 1: DNS Only Mode (Gray Cloud) - Recommended for Simplicity

**Configuration:**
1. Log in to Cloudflare dashboard
2. Go to DNS management
3. Add A record:
   - **Type**: A
   - **Name**: `chat` (or your subdomain)
   - **IPv4 address**: Your Digital Ocean droplet IP
   - **Proxy status**: **DNS only** (gray cloud icon)
   - **TTL**: Auto
4. Save and wait for propagation (usually instant)

**SSL Configuration:**
- No special Cloudflare SSL settings needed
- Let's Encrypt handles SSL directly on your server
- This is the simplest configuration

#### Option 2: Proxied Mode (Orange Cloud) - Advanced

**Configuration:**
1. Add A record as above but set **Proxy status**: **Proxied** (orange cloud icon)
2. Configure Cloudflare SSL/TLS settings:
   - Go to **SSL/TLS** → **Overview**
   - Set mode to **Full** or **Full (Strict)**
   - **Do NOT use "Flexible"** - this causes redirect loops

**How It Works:**
- Cloudflare sits between users and your server
- Traffic flows: User → Cloudflare (HTTPS) → Your Server (HTTPS)
- Cloudflare's IP is publicly visible, not your droplet IP
- Provides DDoS protection and caching

**Advantages:**
- ✅ Hides your origin server IP
- ✅ DDoS protection
- ✅ CDN caching for static assets
- ✅ Web Application Firewall (WAF) available

**Considerations:**
- Cloudflare sees all traffic (man-in-the-middle)
- Slightly higher latency due to extra hop
- Let's Encrypt still validates via HTTP-01 (works fine)

### GoDaddy Configuration

GoDaddy provides **DNS only** - no proxy feature available.

**Configuration:**
1. Log in to GoDaddy account
2. Go to **My Products** → **DNS** for your domain
3. Click **Add** to create a new record
4. Add A record:
   - **Type**: A
   - **Name**: `chat` (or your subdomain)
   - **Value**: Your Digital Ocean droplet IP
   - **TTL**: 600 (10 minutes) or 3600 (1 hour)
5. Save and wait for propagation (typically 10-30 minutes)

**Characteristics:**
- ✅ Simple, direct configuration
- ✅ Lower latency (no intermediary)
- ✅ What you configure is what you get
- ⚠️ Your droplet IP is publicly visible
- ⚠️ No built-in DDoS protection
- ⚠️ No caching layer

### Testing DNS Propagation

Before attempting SSL setup, verify DNS is working:

```bash
# Test DNS resolution
dig chat.yourdomain.com +short
# Should return your droplet IP

# Alternative using nslookup
nslookup chat.yourdomain.com
# Should show your droplet IP in the answer

# Test from multiple DNS servers
dig @8.8.8.8 chat.yourdomain.com +short  # Google DNS
dig @1.1.1.1 chat.yourdomain.com +short  # Cloudflare DNS
```

**When DNS is ready:**
- All commands should return your droplet IP
- You can proceed with client deployment and SSL setup

### Security Considerations by Provider

#### With GoDaddy (Direct DNS)

Since your droplet IP is publicly visible, configure firewall protection:

```bash
# Configure UFW firewall
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 80/tcp   # HTTP (needed for Let's Encrypt)
sudo ufw allow 443/tcp  # HTTPS
sudo ufw enable

# Install fail2ban for SSH protection
sudo apt-get install fail2ban -y
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

#### With Cloudflare (Proxied)

If using Cloudflare proxy (orange cloud):

```bash
# Optional: Restrict access to Cloudflare IPs only
# This prevents direct IP access bypassing Cloudflare
# See: https://www.cloudflare.com/ips/

# Basic firewall (same as GoDaddy)
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

### Adding New DNS Providers

When testing with additional DNS providers, document:

1. **Provider name** and primary service type
2. **DNS record configuration** steps
3. **Special features** (proxy, CDN, etc.)
4. **DNS propagation time** observed
5. **Any gotchas or special considerations**

Update this section with findings for future reference.

## Deployment Options

### Option 1: Fresh Deployment (Recommended for New Setups)

Deploy nginx container first, then create Open WebUI containers on the custom network.

**Advantages:**
- Clean setup from the start
- No migration needed
- Open WebUI containers don't need port mappings

**Steps:**
1. Deploy nginx container
2. Create Open WebUI containers with `--network openwebui-network` (no `-p` flags needed)
3. Configure nginx and SSL

### Option 2: Migration from Host nginx

Migrate existing setup where nginx runs on host and Open WebUI containers have port mappings.

**Advantages:**
- Preserves existing setup
- Can test before full migration
- Gradual transition possible

**Steps:**
1. Deploy nginx container
2. Migrate Open WebUI containers to custom network
3. Convert nginx configs
4. Test connectivity
5. Stop host nginx

## Quick Start

### 1. Deploy nginx Container

```bash
cd /path/to/open-webui/mt/nginx-container
sudo ./deploy-nginx-container.sh
```

**What This Does:**
- Creates `openwebui-network` custom bridge network
- Creates directory structure at `/opt/openwebui-nginx/`
- Generates main `nginx.conf`
- Deploys `openwebui-nginx` container
- Mounts SSL certificates if available at `/etc/letsencrypt/`
- Creates health check endpoint at `/health`

**Expected Output:**
```
╔════════════════════════════════════════╗
║   Deploy Containerized nginx           ║
╚════════════════════════════════════════╝

Step 1: Create custom Docker network
✅ Created network 'openwebui-network'

Step 2: Create nginx config directories
✅ Created directories:
   - /opt/openwebui-nginx/conf.d
   - /opt/openwebui-nginx/ssl
   - /opt/openwebui-nginx/webroot

Step 3: Create main nginx.conf
✅ Created /opt/openwebui-nginx/nginx.conf

Step 4: Migrate existing nginx configs
No existing nginx configs found at /etc/nginx/sites-available

Step 5: Deploy nginx container
✅ nginx container deployed

Step 6: Verify deployment
✅ nginx container is running
✅ Health check passed
```

### 2. Connect Open WebUI Containers to Network

**For New Containers:**
Use `client-manager.sh` which auto-detects containerized nginx:

```bash
cd /path/to/open-webui/mt
./client-manager.sh
# Choose "Deploy new client"
# Script will auto-detect nginx container and generate appropriate config
```

**For Existing Containers:**
Use the migration script:

```bash
sudo ./migrate-containers-to-network.sh
```

**Migration Options:**
1. **Option 1 - Keep Port Mappings**: Adds containers to custom network while preserving existing port mappings (safer, allows rollback)
2. **Option 2 - Recreate Without Ports**: Removes containers and recreates them on custom network only (more secure, nginx-only access)

### 3. Configure nginx for Each Client

**Method 1: Using client-manager.sh (Recommended)**

The `client-manager.sh` script auto-detects containerized nginx and generates appropriate configs:

```bash
cd /path/to/open-webui/mt
./client-manager.sh
# Choose option 5: "Generate nginx config for existing client"
# Script will create config in /tmp/ with setup instructions
```

**Method 2: Manual Configuration**

Create nginx config file:

```nginx
# /opt/openwebui-nginx/conf.d/chat.quantabase.io.conf

server {
    listen 80;
    listen [::]:80;
    server_name chat.quantabase.io;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name chat.quantabase.io;

    ssl_certificate /etc/letsencrypt/live/chat.quantabase.io/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/chat.quantabase.io/privkey.pem;

    # SSL configuration (inline)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        # Use container name instead of localhost:PORT
        proxy_pass http://openwebui-chat-quantabase-io:8080;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_cache_bypass $http_upgrade;

        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;

        proxy_buffering off;
        proxy_request_buffering off;
        client_max_body_size 100M;
    }
}
```

**Apply Configuration:**

```bash
# Test nginx configuration
docker exec openwebui-nginx nginx -t

# Reload nginx
docker exec openwebui-nginx nginx -s reload
```

### 4. SSL Certificate Setup

**Option A: Host Certbot (Recommended)**

Continue using certbot on the host with nginx container:

```bash
# Install certbot if not already installed
sudo apt-get update
sudo apt-get install certbot

# Obtain certificate (standalone mode while nginx container handles HTTP)
sudo certbot certonly --webroot \
    -w /opt/openwebui-nginx/webroot \
    -d chat.quantabase.io

# Reload nginx after certificate issuance
docker exec openwebui-nginx nginx -s reload
```

**Renewal Setup:**

Certbot auto-renewal works automatically. Verify with:

```bash
# Test renewal
sudo certbot renew --dry-run

# Check renewal timer
sudo systemctl status certbot.timer
```

Add post-renewal hook to reload nginx container:

```bash
# Create renewal hook
sudo mkdir -p /etc/letsencrypt/renewal-hooks/deploy/
sudo nano /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

```bash
#!/bin/bash
docker exec openwebui-nginx nginx -s reload
```

```bash
# Make executable
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

**Option B: Certbot Container**

Use a certbot container for certificate management:

```bash
# Create certificates directory
sudo mkdir -p /opt/openwebui-nginx/letsencrypt

# Obtain certificate
docker run --rm \
    -v /opt/openwebui-nginx/letsencrypt:/etc/letsencrypt \
    -v /opt/openwebui-nginx/webroot:/var/www/html \
    certbot/certbot certonly --webroot \
    -w /var/www/html \
    -d chat.quantabase.io \
    --email admin@quantabase.io \
    --agree-tos \
    --no-eff-email

# Update nginx container to mount new cert location
# (Redeploy nginx or update mounts)
```

## Fresh Deployment

**For new setups**, deploy nginx container first, then create Open WebUI containers on the custom network:

1. **Deploy nginx Container**:
   ```bash
   cd /path/to/open-webui/mt/nginx-container
   sudo ./deploy-nginx-container.sh
   ```

2. **Deploy Open WebUI Clients** using client-manager.sh:
   ```bash
   cd /path/to/open-webui/mt
   ./client-manager.sh
   # Choose "Deploy new client"
   # Script auto-detects nginx container and configures everything
   ```

3. **Configure HTTPS** (automated through client-manager.sh or see [MANUAL_SSL_SETUP.md](MANUAL_SSL_SETUP.md))

## Verification & Testing

### Health Checks

```bash
# Check nginx container is running
docker ps --filter "name=openwebui-nginx"

# Test nginx health endpoint
curl http://localhost/health
# Expected: "healthy"

# Check container logs
docker logs openwebui-nginx

# Verify network membership
docker network inspect openwebui-network
```

### Connectivity Tests

```bash
# Test container-to-container connectivity
docker exec openwebui-nginx ping -c 2 openwebui-chat-quantabase-io

# Test HTTP connectivity from nginx to Open WebUI
docker exec openwebui-nginx wget -O- http://openwebui-chat-quantabase-io:8080/health

# Test external HTTPS access
curl -I https://chat.quantabase.io
```

### Configuration Tests

```bash
# Validate nginx configuration
docker exec openwebui-nginx nginx -t

# Check which configs are loaded
docker exec openwebui-nginx ls -la /etc/nginx/conf.d/

# View specific config
docker exec openwebui-nginx cat /etc/nginx/conf.d/chat.quantabase.io.conf
```

## Common Operations

### Reload nginx Configuration

```bash
# After modifying configs in /opt/openwebui-nginx/conf.d/
docker exec openwebui-nginx nginx -s reload
```

### View Logs

```bash
# Follow nginx access logs
docker exec openwebui-nginx tail -f /var/log/nginx/access.log

# Follow nginx error logs
docker exec openwebui-nginx tail -f /var/log/nginx/error.log

# View Docker logs
docker logs -f openwebui-nginx

# View last 100 lines
docker logs --tail 100 openwebui-nginx
```

### Add New Client

**Recommended: Use client-manager.sh (Fully Automated)**

```bash
cd /path/to/open-webui/mt
./client-manager.sh

# Choose "Deploy new client" or "Generate nginx config for existing client"
# The script handles everything:
# - Detects if nginx container is running
# - Creates HTTP-only or HTTPS config based on SSL availability
# - Optionally generates SSL certificates with certbot
# - Auto-deploys, tests, and reloads nginx configuration
```

**Manual Method (For Advanced Users)**

If you need manual control:

```bash
# 1. Deploy Open WebUI container on custom network
docker run -d \
    --name openwebui-docs-example-com \
    --network openwebui-network \
    -e FQDN="docs.example.com" \
    -e CLIENT_NAME="docs" \
    -v openwebui-docs-example-com-data:/app/backend/data \
    --restart unless-stopped \
    ghcr.io/imagicrafter/open-webui:main

# 2. Generate nginx config (HTTP-only first)
# Use template at: nginx-template-containerized-http-only.conf
sudo nano /opt/openwebui-nginx/conf.d/docs.example.com.conf

# 3. Test and reload
docker exec openwebui-nginx nginx -t
docker exec openwebui-nginx nginx -s reload

# 4. Set up SSL with certbot
sudo certbot certonly --webroot \
    -w /opt/openwebui-nginx/webroot \
    -d docs.example.com

# 5. Update nginx config to HTTPS version
# Use template at: nginx-template-containerized.conf
sudo nano /opt/openwebui-nginx/conf.d/docs.example.com.conf

# 6. Test and reload again
docker exec openwebui-nginx nginx -t
docker exec openwebui-nginx nginx -s reload
```

**See [MANUAL_SSL_SETUP.md](MANUAL_SSL_SETUP.md) for detailed troubleshooting.**

### Update nginx Container

```bash
# Pull latest nginx image
docker pull nginx:alpine

# Stop and remove old container
docker stop openwebui-nginx
docker rm openwebui-nginx

# Redeploy (configs are preserved in /opt/openwebui-nginx/)
sudo ./deploy-nginx-container.sh
```

### Backup Configuration

```bash
# Backup nginx configs and SSL certs
sudo tar -czf nginx-backup-$(date +%Y%m%d).tar.gz \
    /opt/openwebui-nginx/ \
    /etc/letsencrypt/

# Restore from backup
sudo tar -xzf nginx-backup-20250117.tar.gz -C /
```

## Troubleshooting

### nginx Container Won't Start

**Check logs:**
```bash
docker logs openwebui-nginx
```

**Common issues:**
- Port 80 or 443 already in use (stop host nginx first)
- Invalid nginx.conf syntax
- Missing mounted directories

**Solutions:**
```bash
# Check ports
sudo netstat -tlnp | grep -E ':80|:443'

# Stop conflicting services
sudo systemctl stop nginx

# Validate config before starting
docker run --rm -v /opt/openwebui-nginx/nginx.conf:/etc/nginx/nginx.conf:ro nginx:alpine nginx -t
```

### Can't Reach Open WebUI Container from nginx

**Symptoms:**
- nginx returns 502 Bad Gateway
- nginx logs show "connect() failed"

**Check connectivity:**
```bash
# Verify both containers on same network
docker network inspect openwebui-network

# Test ping
docker exec openwebui-nginx ping -c 2 openwebui-chat-quantabase-io

# Check container name resolution
docker exec openwebui-nginx nslookup openwebui-chat-quantabase-io
```

**Common issues:**
- Container not connected to openwebui-network
- Wrong container name in proxy_pass directive
- Open WebUI container not running

**Solutions:**
```bash
# Connect container to network
docker network connect openwebui-network openwebui-chat-quantabase-io

# Verify container is running
docker ps --filter "name=openwebui-chat-quantabase-io"

# Check proxy_pass matches exact container name
docker exec openwebui-nginx cat /etc/nginx/conf.d/chat.quantabase.io.conf | grep proxy_pass
```

### SSL Certificate Issues

**Issue: Certificate not found**

```bash
# Check if certificates exist
docker exec openwebui-nginx ls -la /etc/letsencrypt/live/

# Verify mount
docker inspect openwebui-nginx | grep letsencrypt
```

**Solution:**
```bash
# Ensure certificates exist on host
sudo ls -la /etc/letsencrypt/live/

# Redeploy nginx with SSL mount
docker stop openwebui-nginx
docker rm openwebui-nginx
sudo ./deploy-nginx-container.sh
```

**Issue: Certificate auto-renewal not reloading nginx**

Ensure post-renewal hook is configured (see SSL Certificate Setup above).

### Configuration Not Taking Effect

**Check if file is mounted correctly:**
```bash
# View config inside container
docker exec openwebui-nginx cat /etc/nginx/conf.d/your-domain.conf

# Compare with host file
sudo cat /opt/openwebui-nginx/conf.d/your-domain.conf
```

**Solution:**
```bash
# Configs are mounted read-only, edit on host then reload
sudo nano /opt/openwebui-nginx/conf.d/your-domain.conf
docker exec openwebui-nginx nginx -t
docker exec openwebui-nginx nginx -s reload
```

### High Memory or CPU Usage

**Check nginx stats:**
```bash
docker stats openwebui-nginx
```

**Common causes:**
- Too many worker processes
- Connection leaks
- Slow backend (Open WebUI container issues)

**Solutions:**
```bash
# Check nginx worker configuration
docker exec openwebui-nginx cat /etc/nginx/nginx.conf | grep worker_processes

# Check Open WebUI container health
docker ps --filter "name=openwebui-"
docker stats $(docker ps --filter "name=openwebui-" --format "{{.Names}}")

# Check nginx connections
docker exec openwebui-nginx cat /var/log/nginx/access.log | tail -100
```

## Rollback Procedures

### Rollback to Host nginx

If you need to revert to host nginx:

```bash
# 1. Stop nginx container
docker stop openwebui-nginx

# 2. Start host nginx
sudo systemctl start nginx
sudo systemctl enable nginx

# 3. Verify host nginx is working
sudo systemctl status nginx
curl -I http://localhost

# 4. Optional: Remove nginx container (keeps configs)
docker rm openwebui-nginx

# 5. Optional: Restore original port mappings to Open WebUI containers
# (Use migrate-containers-to-network.sh Option 2 in reverse, or manually recreate)
```

**Note:** If you used Migration Option 1 (kept port mappings), rollback is instant - just stop nginx container and start host nginx. If you used Option 2 (removed port mappings), you'll need to recreate Open WebUI containers with `-p` flags.

### Emergency Fallback

If everything breaks:

```bash
# 1. Stop all containers
docker stop openwebui-nginx $(docker ps --filter "name=openwebui-" --format "{{.Names}}")

# 2. Start host nginx
sudo systemctl start nginx

# 3. Recreate Open WebUI containers with port mappings
# (Use client-manager.sh or manually with -p flags)

# 4. Restore host nginx configs
sudo cp /etc/nginx/sites-available/*.conf.backup /etc/nginx/sites-available/
sudo nginx -t
sudo systemctl reload nginx
```

## Best Practices

### Security

- **Remove Unnecessary Port Mappings**: After migration, use Option 2 to recreate containers without `-p` flags for better isolation
- **Read-Only Mounts**: nginx.conf and configs are mounted read-only (`:ro` flag)
- **SSL/TLS**: Always use HTTPS in production with valid certificates
- **Network Isolation**: Use custom network instead of default bridge
- **Regular Updates**: Keep nginx container image updated

### Performance

- **Worker Processes**: Set to `auto` to match CPU cores (default in config)
- **Gzip Compression**: Enabled by default for static assets
- **Connection Pooling**: Increase `worker_connections` if needed for high traffic
- **Buffer Sizes**: Adjust `client_max_body_size` based on upload requirements

### Maintenance

- **Backup Regularly**: Use backup command above before making changes
- **Test Before Reload**: Always run `nginx -t` before `nginx -s reload`
- **Monitor Logs**: Set up log rotation and monitoring
- **Document Changes**: Keep notes on custom configurations
- **Version Control**: Consider storing `/opt/openwebui-nginx/conf.d/` in git

### Monitoring

```bash
# Create simple monitoring script
cat > /opt/openwebui-nginx/check-health.sh << 'EOF'
#!/bin/bash
if ! docker ps | grep -q openwebui-nginx; then
    echo "ERROR: nginx container not running"
    exit 1
fi

if ! curl -sf http://localhost/health > /dev/null; then
    echo "ERROR: nginx health check failed"
    exit 1
fi

echo "OK: nginx healthy"
EOF

chmod +x /opt/openwebui-nginx/check-health.sh

# Add to crontab for monitoring
# */5 * * * * /opt/openwebui-nginx/check-health.sh
```

## Advanced Configuration

### Custom nginx.conf Settings

Edit the main configuration:

```bash
sudo nano /opt/openwebui-nginx/nginx.conf

# Test changes
docker exec openwebui-nginx nginx -t

# Reload
docker exec openwebui-nginx nginx -s reload
```

### Rate Limiting

Add to `/opt/openwebui-nginx/nginx.conf` in `http` block:

```nginx
# Rate limiting
limit_req_zone $binary_remote_addr zone=one:10m rate=10r/s;
limit_req_status 429;
```

Then in server block:

```nginx
location / {
    limit_req zone=one burst=20 nodelay;
    proxy_pass http://openwebui-chat-quantabase-io:8080;
    # ... other settings
}
```

### Custom Error Pages

```bash
# Create error pages directory
sudo mkdir -p /opt/openwebui-nginx/error-pages

# Create custom 502 page
sudo nano /opt/openwebui-nginx/error-pages/502.html

# Update server block
sudo nano /opt/openwebui-nginx/conf.d/your-domain.conf
```

Add to server block:

```nginx
error_page 502 /502.html;
location = /502.html {
    root /usr/share/nginx/html;
    internal;
}
```

### IP Whitelisting

Add to specific location or server block:

```nginx
location /admin {
    allow 192.168.1.0/24;
    deny all;
    proxy_pass http://openwebui-chat-quantabase-io:8080;
}
```

## Integration with client-manager.sh

The `client-manager.sh` script automatically detects containerized nginx:

```bash
# Auto-detection logic
if docker ps --filter "name=openwebui-nginx" | grep -q openwebui-nginx; then
    # Use containerized template
    template="/path/to/nginx-template-containerized.conf"
else
    # Use host nginx template
    template="/path/to/nginx-template.conf"
fi
```

**Features:**
- Generates configs using container names instead of localhost:PORT
- Provides containerized-specific setup instructions
- Creates configs in appropriate directory for each setup type

## References

- [nginx Docker Official Image](https://hub.docker.com/_/nginx)
- [Docker Networks](https://docs.docker.com/network/)
- [Let's Encrypt](https://letsencrypt.org/getting-started/)
- [nginx Configuration Guide](https://nginx.org/en/docs/)

## Support

For issues with these scripts:
1. Check troubleshooting section above
2. Review nginx container logs: `docker logs openwebui-nginx`
3. Verify network configuration: `docker network inspect openwebui-network`
4. Test individual components (nginx config, container connectivity, SSL certs)

## License

These scripts are part of the Open WebUI project and follow the same license terms.
