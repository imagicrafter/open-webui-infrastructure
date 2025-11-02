# HOST nginx Deployment for Open WebUI

This directory contains scripts and templates for deploying nginx on the **HOST system** (non-containerized) for Open WebUI multi-tenant deployments.

## Overview

**HOST nginx** is the **RECOMMENDED** deployment mode for production environments. It runs nginx as a systemd service directly on the host operating system.

### Why HOST nginx?

✅ **Production-Ready**: Proven stable on server 159.65.34.41 (chat-bc.quantabase.io)
✅ **Function Pipes Work**: All Open WebUI features work correctly
✅ **Standard Deployment**: Follows industry-standard nginx deployment patterns
✅ **Easy SSL Management**: Integrates seamlessly with certbot/Let's Encrypt
✅ **Better Performance**: No container overhead
✅ **Simpler Troubleshooting**: Standard systemd logs and management

### vs. Containerized nginx

The containerized nginx (in `mt/nginx-container/`) is **EXPERIMENTAL** and has known issues:
- ❌ Function pipe saves fail (`/api/v1/utils/code/format` endpoint broken)
- ⚠️  Only use for testing and development

## Files in This Directory

```
mt/nginx/
├── README.md                         # This file
├── DEV_PLAN_FOR_NGINX_GET_WELL.md    # Integration development plan
├── scripts/                          # Feature-specific scripts
│   ├── install-nginx-host.sh         #   Installation script
│   ├── uninstall-nginx-host.sh       #   Uninstallation script
│   └── check-nginx-status.sh         #   Status checking script
└── templates/                        # Configuration templates
    └── nginx-template-host.conf      #   nginx config template for clients
```

## Installation

### Method 1: Via Client Manager (Recommended)

```bash
cd ~/open-webui/mt
./client-manager.sh

# Select: 5) Manage nginx Installation
# Select: 1) Install nginx on HOST (Production - Recommended)
```

### Method 2: Direct Script Execution

```bash
cd ~/open-webui/mt/nginx
./scripts/install-nginx-host.sh
```

Or run individual scripts:
```bash
# Install nginx
./scripts/install-nginx-host.sh

# Check status
./scripts/check-nginx-status.sh

# Uninstall nginx
./scripts/uninstall-nginx-host.sh
```

## What Gets Installed

The installation script installs:

1. **nginx** - Web server (systemd service)
2. **certbot** - SSL certificate manager
3. **python3-certbot-nginx** - nginx plugin for certbot
4. **Firewall rules** - Opens ports 80 and 443

## Configuration Template

The `nginx-template-host.conf` file is used when generating nginx configurations for client deployments. It includes:

- HTTP to HTTPS redirect
- SSL configuration (added by certbot)
- Security headers
- Proxy settings for Open WebUI containers
- WebSocket support
- API endpoint timeouts
- Static file caching

### Template Placeholders

- `DOMAIN_PLACEHOLDER` - Replaced with actual client domain
- `PORT_PLACEHOLDER` - Replaced with container port number

## Usage Workflow

### 1. Install nginx

```bash
./client-manager.sh
# Select: 5) Manage nginx Installation
# Select: 1) Install nginx on HOST
```

### 2. Create Client Deployment

```bash
# Select: 2) Create New Deployment
# Enter: client name, port, domain
```

### 3. Generate nginx Config

```bash
# Select: 5) Manage nginx Installation
# Select: 4) Generate nginx Configuration for Client
# Select your client from the list
```

This will:
- Generate config from template
- Copy to `/etc/nginx/sites-available/DOMAIN`
- Enable site (symlink to `/etc/nginx/sites-enabled/`)
- Test nginx configuration
- Reload nginx

### 4. Generate SSL Certificate

Choose from:
- **Production**: Real Let's Encrypt certificate (rate limited)
- **Staging**: Test certificate for development (no limits)

The config generation wizard prompts for SSL setup automatically.

## Management Commands

### Service Management

```bash
# Check status
sudo systemctl status nginx

# Start nginx
sudo systemctl start nginx

# Stop nginx
sudo systemctl stop nginx

# Reload (after config changes)
sudo systemctl reload nginx

# Restart
sudo systemctl restart nginx

# Enable on boot
sudo systemctl enable nginx
```

### Configuration Testing

```bash
# Test configuration
sudo nginx -t

# Test specific config file
sudo nginx -t -c /etc/nginx/nginx.conf
```

### SSL Certificate Management

```bash
# List certificates
sudo certbot certificates

# Generate production certificate
sudo certbot --nginx -d yourdomain.com

# Generate staging certificate (for testing)
sudo certbot --nginx -d yourdomain.com --staging

# Renew certificates (automatic via cron)
sudo certbot renew

# Renew with dry-run test
sudo certbot renew --dry-run

# Delete certificate
sudo certbot delete --cert-name yourdomain.com
```

### Log Files

```bash
# nginx error log
sudo tail -f /var/log/nginx/error.log

# nginx access log
sudo tail -f /var/log/nginx/access.log

# Client-specific logs
sudo tail -f /var/log/nginx/DOMAIN-access.log
sudo tail -f /var/log/nginx/DOMAIN-error.log

# systemd journal
sudo journalctl -u nginx -f
```

## Configuration File Locations

```
/etc/nginx/
├── nginx.conf                     # Main nginx configuration
├── sites-available/               # Available site configs
│   └── yourdomain.com             # Client config (generated)
├── sites-enabled/                 # Enabled sites (symlinks)
│   └── yourdomain.com -> ../sites-available/yourdomain.com
└── conf.d/                        # Additional configs

/etc/letsencrypt/
├── live/                          # Active certificates
│   └── yourdomain.com/
│       ├── fullchain.pem          # Certificate chain
│       ├── privkey.pem            # Private key
│       └── ...
├── renewal/                       # Auto-renewal configs
└── options-ssl-nginx.conf         # SSL options (certbot managed)
```

## Firewall Configuration

The installation script configures UFW to allow HTTP and HTTPS:

```bash
# Check firewall status
sudo ufw status

# Manually allow nginx (if needed)
sudo ufw allow 'Nginx Full'

# Or allow ports directly
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

## Troubleshooting

### nginx Won't Start

```bash
# Check logs
sudo journalctl -u nginx -n 50

# Test configuration
sudo nginx -t

# Check port conflicts
sudo lsof -i :80
sudo lsof -i :443
```

### SSL Certificate Issues

```bash
# Check certificate status
sudo certbot certificates

# Test renewal
sudo certbot renew --dry-run

# Check DNS resolves
dig yourdomain.com +short

# Manual certificate generation
sudo certbot --nginx -d yourdomain.com --dry-run
```

### Configuration Errors

```bash
# Test configuration
sudo nginx -t

# Check specific site config
sudo nginx -t -c /etc/nginx/sites-available/yourdomain.com

# Disable site temporarily
sudo rm /etc/nginx/sites-enabled/yourdomain.com
sudo systemctl reload nginx
```

### Permission Issues

```bash
# Ensure qbmgr has sudo access
sudo whoami  # Should return "root" without password

# Check sudoers file
sudo cat /etc/sudoers.d/qbmgr

# Fix permissions on config files
sudo chown root:root /etc/nginx/sites-available/*
sudo chmod 644 /etc/nginx/sites-available/*
```

## Uninstallation

### Via Client Manager

```bash
./client-manager.sh
# Select: 5) Manage nginx Installation
# Select: 6) Uninstall nginx
```

### Manual Uninstallation

```bash
# Stop nginx
sudo systemctl stop nginx
sudo systemctl disable nginx

# Remove packages
sudo apt-get remove --purge nginx nginx-common certbot python3-certbot-nginx

# Remove configuration files
sudo rm -rf /etc/nginx
sudo rm -rf /etc/letsencrypt

# Remove logs
sudo rm -rf /var/log/nginx
```

## Integration with Client Manager

The client-manager.sh script integrates with these HOST nginx scripts:

- **Installation**: Calls `mt/nginx/install-nginx-host.sh`
- **Config Generation**: Uses `mt/nginx/nginx-template-host.conf`
- **Status Checks**: Queries systemd status
- **Uninstallation**: Removes packages and configs

## Testing

See test plans in `mt/tests/`:
- `NGINX_BUILD_TEST.md` - Tests HOST nginx installation
- `CLIENT_DEPLOYMENT_TEST.md` - Tests end-to-end deployment with nginx

## Production Deployment

For production deployments:

1. ✅ Use HOST nginx (this directory)
2. ✅ Use production SSL certificates
3. ✅ Enable nginx on boot: `sudo systemctl enable nginx`
4. ✅ Set up automatic certificate renewal (certbot configures this)
5. ✅ Monitor logs regularly
6. ✅ Test configuration before reload: `sudo nginx -t`

## Security Considerations

- Certificates auto-renew via certbot cron job
- SSL configuration managed by certbot (best practices)
- Security headers included in template
- Firewall rules configured automatically
- Rate limiting can be added to config if needed

## Related Documentation

- **Main README**: `mt/README.md` (nginx Configuration & HTTPS Setup section)
- **Dev Plan**: `mt/nginx/DEV_PLAN_FOR_NGINX_GET_WELL.md`
- **Container nginx**: `mt/nginx-container/README.md` (experimental alternative)
- **Setup Guide**: `mt/setup/README.md`
- **Test Plans**: `mt/tests/NGINX_BUILD_TEST.md`, `mt/tests/CLIENT_DEPLOYMENT_TEST.md`

## Support

For issues or questions:
- Check logs: `sudo journalctl -u nginx -n 50`
- Test config: `sudo nginx -t`
- Review documentation: `mt/README.md`
- Check known issues: `mt/nginx/DEV_PLAN_FOR_NGINX_GET_WELL.md`
