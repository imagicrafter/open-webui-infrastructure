# Manual SSL Setup Guide for nginx Container

This guide provides step-by-step instructions for manually setting up SSL certificates for Open WebUI client deployments when automation cannot be used.

## Prerequisites

Before starting, ensure:
- ✅ nginx container is running (`docker ps | grep openwebui-nginx`)
- ✅ Client container is deployed and running
- ✅ DNS is configured and propagated
- ✅ Ports 80 and 443 are accessible from the internet
- ✅ HTTP-only nginx configuration is deployed

## Step 1: Verify DNS Configuration

First, ensure your domain points to your server:

```bash
# Check DNS resolution
dig your-domain.com +short

# Should return your server's IP address
# If not, configure DNS and wait for propagation (5-60 minutes)
```

Test HTTP access:
```bash
# Should return HTTP 200
curl -I http://your-domain.com
```

## Step 2: Obtain SSL Certificate with Certbot

### Option A: Using Host Certbot (Recommended)

Install certbot if not already installed:
```bash
sudo apt-get update
sudo apt-get install certbot
```

Obtain certificate:
```bash
sudo certbot certonly --webroot \
    -w /opt/openwebui-nginx/webroot \
    -d your-domain.com \
    --agree-tos \
    --email your-email@example.com
```

### Option B: Using Certbot Container

```bash
docker run --rm \
    -v /etc/letsencrypt:/etc/letsencrypt \
    -v /opt/openwebui-nginx/webroot:/webroot \
    certbot/certbot certonly \
    --webroot -w /webroot \
    -d your-domain.com \
    --agree-tos \
    --email your-email@example.com
```

### Verification

Check if certificate was created:
```bash
sudo ls -la /etc/letsencrypt/live/your-domain.com/
```

You should see:
- `fullchain.pem` - Full certificate chain
- `privkey.pem` - Private key
- `cert.pem` - Certificate only
- `chain.pem` - Certificate chain

## Step 3: Update nginx Configuration to Use SSL

### Generate SSL-Enabled Configuration

```bash
cd /path/to/open-webui/mt
./client-manager.sh
# Choose option 5: Generate nginx Configuration
# Select your client
# Choose option 1: Production (HTTPS with Let's Encrypt)
```

The script will auto-detect that SSL certificates exist and use the SSL template.

### Verify Configuration File

```bash
cat /opt/openwebui-nginx/conf.d/your-domain.com.conf
```

Should contain:
- HTTP server block (redirects to HTTPS)
- HTTPS server block with SSL configuration
- Certificate paths pointing to `/etc/letsencrypt/live/your-domain.com/`

## Step 4: Test and Reload nginx

Test configuration:
```bash
docker exec openwebui-nginx nginx -t
```

Expected output:
```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

If test passes, reload nginx:
```bash
docker exec openwebui-nginx nginx -s reload
```

## Step 5: Verify HTTPS Access

Test SSL certificate:
```bash
# Check HTTPS access
curl -I https://your-domain.com

# Test SSL certificate
echo | openssl s_client -connect your-domain.com:443 -servername your-domain.com 2>/dev/null | openssl x509 -noout -dates
```

Visit in browser:
```
https://your-domain.com
```

Should show:
- ✅ Valid SSL certificate (green padlock)
- ✅ Open WebUI login page
- ✅ No certificate warnings

## Step 6: Set Up Auto-Renewal

Certbot automatically sets up renewal via systemd timer. Verify:

```bash
# Check renewal timer
sudo systemctl status certbot.timer

# Test renewal (dry run)
sudo certbot renew --dry-run
```

### Add nginx Reload Hook

Create post-renewal hook to reload nginx container:

```bash
# Create hook directory
sudo mkdir -p /etc/letsencrypt/renewal-hooks/deploy/

# Create reload script
sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh > /dev/null << 'EOF'
#!/bin/bash
# Reload nginx container after certificate renewal
docker exec openwebui-nginx nginx -s reload
EOF

# Make executable
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

Test the hook:
```bash
sudo /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

## Troubleshooting

### Certificate Generation Fails

**Error: "Connection refused" or "Challenge failed"**

Check:
```bash
# 1. Verify nginx is serving on port 80
curl -I http://your-domain.com/.well-known/acme-challenge/test

# 2. Check if port 80 is accessible externally
curl -I http://$(curl -s ifconfig.me)

# 3. Verify DNS
dig your-domain.com +short

# 4. Check firewall
sudo ufw status
# Allow ports if needed:
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

**Error: "Too many certificates already issued"**

Let's Encrypt has rate limits (5 certificates per week per domain). Wait or use:
```bash
# Use staging environment for testing
sudo certbot certonly --webroot \
    -w /opt/openwebui-nginx/webroot \
    -d your-domain.com \
    --staging \
    --force-renewal
```

### nginx Configuration Test Fails

**Error: "SSL certificate not found"**

Check paths in config:
```bash
# View config
cat /opt/openwebui-nginx/conf.d/your-domain.com.conf | grep ssl_certificate

# Check if files exist in container
docker exec openwebui-nginx ls -la /etc/letsencrypt/live/your-domain.com/
```

**Error: "options-ssl-nginx.conf not found"**

Run the SSL options creator:
```bash
cd /path/to/open-webui/mt/nginx-container
sudo ./create-ssl-options.sh
```

Or comment out the include directive in the nginx config:
```nginx
# include /etc/nginx/ssl/options-ssl-nginx.conf;
```

### Browser Shows Certificate Error

**"Certificate not trusted" or "Certificate name mismatch"**

Check certificate details:
```bash
# View certificate
docker exec openwebui-nginx cat /etc/letsencrypt/live/your-domain.com/cert.pem | openssl x509 -text -noout
```

Verify:
- Common Name (CN) matches your domain
- Alternative Names include your domain
- Not expired
- Issued by Let's Encrypt Authority X3/X4

**Mixed content warnings**

Ensure all resources load via HTTPS. Check browser console for details.

### Certificate Renewal Fails

Check renewal logs:
```bash
sudo cat /var/log/letsencrypt/letsencrypt.log
```

Test renewal manually:
```bash
sudo certbot renew --dry-run
```

Common issues:
- nginx not serving `.well-known/acme-challenge/` directory
- Port 80 blocked
- Domain DNS changed

## Quick Reference Commands

```bash
# View all certificates
sudo certbot certificates

# Force renew specific certificate
sudo certbot renew --force-renewal --cert-name your-domain.com

# Delete certificate
sudo certbot delete --cert-name your-domain.com

# Test nginx config
docker exec openwebui-nginx nginx -t

# Reload nginx
docker exec openwebui-nginx nginx -s reload

# View nginx logs
docker logs openwebui-nginx --tail 100

# Check certificate expiry
echo | openssl s_client -connect your-domain.com:443 2>/dev/null | openssl x509 -noout -dates
```

## Security Best Practices

1. **Keep Certificates Up to Date**
   - Certbot auto-renews 30 days before expiry
   - Monitor renewal timer: `sudo systemctl status certbot.timer`

2. **Use Strong SSL Configuration**
   - The provided templates use TLS 1.2+ only
   - Disable weak ciphers
   - Enable HSTS headers

3. **Protect Private Keys**
   ```bash
   # Verify permissions
   sudo ls -la /etc/letsencrypt/live/your-domain.com/privkey.pem
   # Should be: -rw-r--r-- 1 root root
   ```

4. **Monitor Certificate Health**
   - Use monitoring tools (UptimeRobot, StatusCake)
   - Set up alerts for expiration
   - Test HTTPS weekly: `curl -I https://your-domain.com`

## Need Help?

If you encounter issues not covered here:

1. Check nginx container logs: `docker logs openwebui-nginx`
2. Check certbot logs: `sudo cat /var/log/letsencrypt/letsencrypt.log`
3. Review nginx configuration: `cat /opt/openwebui-nginx/conf.d/your-domain.com.conf`
4. Test connectivity: `curl -v http://your-domain.com`
5. Verify DNS: `dig your-domain.com +trace`

For Let's Encrypt specific issues: https://community.letsencrypt.org/
