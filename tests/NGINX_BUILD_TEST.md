# nginx Build Test Plan

**Purpose**: Validate both HOST and containerized nginx deployment modes
**Environment**: Server with qbmgr user and client-manager installed
**Expected Duration**: 10-15 minutes
**Prerequisites**: NEW_SERVER_BUILD_TEST.md completed successfully

---

## Test Objectives

- Verify HOST nginx installation (production-ready)
- Validate firewall configuration
- Test containerized nginx deployment (experimental)
- Verify config generation and installation automation
- Test staging SSL certificate generation
- Validate nginx management operations

---

## Prerequisites

- Server provisioned via quick-setup.sh
- Logged in as qbmgr user
- Client-manager accessible

---

## Test Procedure

### Test 1: HOST nginx Installation (Production Mode)

**Objective**: Verify production-ready nginx installation on host system

#### Step 1.1: Launch nginx Installation

```bash
# Launch client-manager
cd ~/open-webui/mt
./client-manager.sh

# Select: 5) Manage nginx Installation
# Select: 1) Install nginx on HOST (Production - Recommended)
```

**Expected Output**:
```
╔════════════════════════════════════════╗
║   Install nginx on HOST (Production)   ║
╚════════════════════════════════════════╝

This installs nginx as a systemd service on the host.
Recommended for production deployments.

Continue with installation? (y/N):
```

**Action**: Type `y` and press Enter

#### Step 1.2: Monitor Installation Progress

**Expected Output**:
```
📦 Installing nginx and certbot...
✅ nginx and certbot installed successfully

🔥 Configuring firewall...
✅ Firewall configured (Nginx Full profile)
   OR
✅ Firewall configured (direct ports 80, 443)

🚀 Starting nginx service...
✅ nginx service started

✅ nginx installed and running successfully!

📋 Next steps:
  1. Create client deployment (option 2 from main menu)
  2. Generate nginx config (option 4 from nginx menu)
  ...
```

**Pass Criteria**:
- All steps show green checkmarks (✅)
- No error messages
- Firewall configuration succeeds (either method)
- nginx service starts successfully

**Fail Criteria**:
- Red X marks (❌) appear
- Permission denied errors
- nginx fails to start

#### Step 1.3: Verify nginx Service Status

Exit client-manager and verify installation:

```bash
# Check nginx service
sudo systemctl status nginx

# Check nginx version
nginx -v

# Check certbot installed
certbot --version

# Check firewall rules
sudo ufw status | grep -E "80|443|Nginx"
```

**Expected Output**:
```bash
# nginx status
● nginx.service - A high performance web server
     Loaded: loaded
     Active: active (running)

# nginx version
nginx version: nginx/1.x.x (Ubuntu)

# certbot version
certbot 2.x.x

# Firewall rules
80/tcp                     ALLOW       Anywhere
443/tcp                    ALLOW       Anywhere
   OR
Nginx Full                 ALLOW       Anywhere
```

**Pass Criteria**:
- nginx service active and running
- nginx version displays correctly
- certbot installed
- Ports 80 and 443 allowed in firewall

---

### Test 2: Check nginx Status via Menu

**Objective**: Verify nginx status checking function

```bash
# From client-manager main menu
# Select: 5) Manage nginx Installation
# Select: 5) Check nginx Status
```

**Expected Output**:
```
═══════════════════════════════════════
nginx Status
═══════════════════════════════════════

HOST nginx (systemd service):
  Status: ● active (running)
  Version: nginx/1.x.x
  Listening: :80, :443

Container nginx (openwebui-nginx):
  Status: Not installed

Press Enter to continue...
```

**Pass Criteria**:
- HOST nginx shows "active (running)"
- nginx version displayed
- Ports 80 and 443 listed
- Container nginx shows "Not installed"

---

### Test 3: Containerized nginx Deployment (Experimental)

**Objective**: Test experimental containerized nginx installation

⚠️ **Note**: This test is for validation purposes. Production deployments should use HOST nginx.

#### Step 3.1: Deploy Container nginx

```bash
# From client-manager main menu
# Select: 5) Manage nginx Installation
# Select: 2) Install nginx in Container (Experimental)
```

**Expected Output**:
```
╔════════════════════════════════════════╗
║   Install nginx in Container (TESTING) ║
╚════════════════════════════════════════╝

⚠️  WARNING: EXPERIMENTAL - For testing only!

This deployment mode has known issues:
  - Function pipe saves may fail
  - Still under validation and debugging

Use HOST nginx installation (option 1) for production.

Continue with containerized nginx? (y/N):
```

**Action**: Type `y` and press Enter

**Expected Output**:
```
Deploying containerized nginx...

Creating Docker network: openwebui-network
...
Pulling nginx image...
...
Starting nginx container...
✅ Containerized nginx deployment completed

⚠️  REMINDER: This is EXPERIMENTAL
   Known issue: Function pipe saves may fail
   For production, use HOST nginx (option 1)

Press Enter to continue...
```

**Pass Criteria**:
- Deployment completes without critical errors
- Container starts successfully
- Warnings about experimental status displayed

**Fail Criteria**:
- Deployment script fails
- Container fails to start
- Network creation errors

#### Step 3.2: Verify Container nginx Running

```bash
# Exit client-manager and check container
docker ps --filter "name=openwebui-nginx"

# Check container logs
docker logs openwebui-nginx | head -20
```

**Expected Output**:
```bash
# docker ps
CONTAINER ID   IMAGE         STATUS        PORTS                 NAMES
abc123def456   nginx:latest  Up X seconds  0.0.0.0:80->80/tcp... openwebui-nginx

# Container logs (no errors)
...nginx/1.x.x
...Configuration test is successful
```

**Pass Criteria**:
- Container running and status "Up"
- Ports mapped correctly (80, 443)
- No error messages in logs

---

### Test 4: Manage Containerized nginx (Submenu)

**Objective**: Test containerized nginx management features

```bash
# From client-manager main menu
# Select: 5) Manage nginx Installation
# Select: 3) Manage nginx Container ✓
```

**Expected Output**:
```
╔════════════════════════════════════════╗
║      Manage nginx Container            ║
╚════════════════════════════════════════╝

Status: Up X seconds
Ports:  0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
Network: openwebui-network

1) View nginx Logs
2) Test nginx Configuration
3) Reload nginx
4) Restart nginx Container
5) Stop nginx Container
6) Back to nginx Menu

Select action (1-6):
```

#### Test 4.1: Test nginx Configuration

**Action**: Select option `2`

**Expected Output**:
```
Testing nginx configuration...

nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful

Press Enter to continue...
```

**Pass Criteria**: Configuration test successful

#### Test 4.2: Reload nginx

**Action**: Return to submenu, select option `3`

**Expected Output**:
```
Reloading nginx...
✅ nginx reloaded

Press Enter to continue...
```

**Pass Criteria**: Reload completes without errors

---

### Test 5: Uninstall nginx

**Objective**: Verify nginx uninstallation removes both modes correctly

⚠️ **Note**: This will remove both HOST and container nginx

```bash
# From client-manager main menu
# Select: 5) Manage nginx Installation
# Select: 6) Uninstall nginx
```

**Expected Output**:
```
═══════════════════════════════════════
Uninstall nginx
═══════════════════════════════════════

Current installations detected:
  ✓ HOST nginx (systemd service)
  ✓ Container nginx (openwebui-nginx)

⚠️  WARNING: This will remove ALL nginx installations!
   This will make all client sites inaccessible.

Continue with uninstall? (y/N):
```

**Action**: Type `y` and press Enter

**Expected Output**:
```
Stopping services...
✅ nginx services stopped

Removing packages...
✅ nginx packages removed

Removing container...
✅ nginx container removed

Cleaning up configuration files...
✅ Configuration files cleaned

nginx uninstalled successfully

Press Enter to continue...
```

**Pass Criteria**:
- Both HOST and container nginx removed
- No errors during uninstallation
- Services stopped cleanly

#### Verify Uninstallation

```bash
# Check HOST nginx removed
nginx -v 2>&1 | grep -q "not found" && echo "✅ HOST nginx removed" || echo "❌ Still installed"

# Check container removed
docker ps -a --filter "name=openwebui-nginx" --format "{{.Names}}" | grep -q "openwebui-nginx" && echo "❌ Container still exists" || echo "✅ Container removed"

# Check service stopped
sudo systemctl is-active nginx 2>&1 | grep -q "inactive\|failed\|not-found" && echo "✅ Service stopped" || echo "❌ Still running"
```

**Pass Criteria**:
- All checks show ✅ (removed/stopped)
- nginx command not found
- Container removed
- Service not running

---

## Reinstallation Test

**Objective**: Verify nginx can be cleanly reinstalled after uninstallation

Repeat **Test 1** (HOST nginx Installation) to verify reinstallation works.

**Pass Criteria**:
- Reinstallation succeeds without errors
- nginx runs normally after reinstall
- All previous test steps pass again

---

## Test Summary

### Test Results Table

| Test | Description | Result | Notes |
|------|-------------|--------|-------|
| 1    | HOST nginx installation | ☐ PASS ☐ FAIL | |
| 2    | Check nginx status | ☐ PASS ☐ FAIL | |
| 3    | Containerized nginx deployment | ☐ PASS ☐ FAIL | Experimental |
| 4    | Manage container submenu | ☐ PASS ☐ FAIL | |
| 5    | Uninstall nginx | ☐ PASS ☐ FAIL | |
| 6    | Reinstallation | ☐ PASS ☐ FAIL | |

### Pass Criteria Checklist

- [ ] HOST nginx installs successfully
- [ ] Firewall configured correctly (ports 80/443 allowed)
- [ ] certbot installed
- [ ] nginx service active and running
- [ ] nginx status check displays correct information
- [ ] Containerized nginx deploys successfully
- [ ] Container nginx management submenu works
- [ ] Test/reload operations work
- [ ] Uninstall removes both nginx modes
- [ ] Reinstallation works after uninstall

### Overall Test Result

**PASS**: All tests ✅ (containerized nginx warnings are expected)
**FAIL**: Any critical test ❌

---

## Troubleshooting

### Issue: Firewall configuration fails

**Symptom**:
```
❌ Failed to configure firewall
```

**Solution**:
```bash
# Check UFW status
sudo ufw status

# Manually add rules
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

### Issue: nginx service fails to start

**Symptom**:
```
● nginx.service - A high performance web server
     Active: failed
```

**Solution**:
```bash
# Check nginx logs
sudo journalctl -u nginx -n 50

# Test nginx configuration
sudo nginx -t

# Check port conflicts
sudo lsof -i :80
sudo lsof -i :443
```

### Issue: Container nginx fails to deploy

**Symptom**:
```
❌ Deployment failed
```

**Solution**:
```bash
# Check Docker running
docker ps

# Check for port conflicts
docker ps -a | grep "0.0.0.0:80\|0.0.0.0:443"

# Check Docker network
docker network ls | grep openwebui-network

# Review deployment script logs
```

### Issue: Permission denied during operations

**Solution**:
```bash
# Verify qbmgr has sudo access
sudo whoami  # Should return "root" without password prompt

# Check sudoers configuration
sudo cat /etc/sudoers.d/qbmgr
```

---

## Cleanup

After completing all tests:

```bash
# Leave nginx installed (HOST mode) for next test plan
# CLIENT_DEPLOYMENT_TEST.md requires nginx to be installed
```

**Do NOT uninstall nginx** if proceeding to CLIENT_DEPLOYMENT_TEST.md

---

## Test Metadata

- **Test ID**: NGINX_BUILD_TEST
- **Version**: 1.0
- **Last Updated**: 2025-10-25
- **Maintainer**: Open WebUI MT Team
- **Prerequisites**: NEW_SERVER_BUILD_TEST.md
- **Next Test**: CLIENT_DEPLOYMENT_TEST.md
- **Related Documentation**:
  - mt/README.md (nginx Configuration & HTTPS Setup section)
  - mt/nginx/DEV_PLAN_FOR_NGINX_GET_WELL.md
