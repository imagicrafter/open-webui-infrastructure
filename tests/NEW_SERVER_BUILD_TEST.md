# New Server Build Test Plan

**Purpose**: Validate complete server setup from scratch using quick-setup.sh
**Environment**: Fresh Digital Ocean droplet
**Expected Duration**: 15-20 minutes
**Prerequisites**: Digital Ocean account, SSH key generated locally

---

## Test Objectives

- Verify quick-setup.sh provisions server correctly
- Confirm qbmgr user has proper permissions
- Validate all required tools are installed
- Ensure client-manager launches automatically on login

---

## Prerequisites

### 1. Local SSH Key

Ensure you have an SSH key pair:

```bash
# Check for existing key
ls -la ~/.ssh/id_*.pub

# If none exists, generate one
ssh-keygen -t ed25519 -C "your_email@example.com"

# Display public key (for Digital Ocean)
cat ~/.ssh/id_ed25519.pub
```

**Expected Output**: Public key starting with `ssh-ed25519` or `ssh-rsa`

### 2. Digital Ocean Account

- Active Digital Ocean account with payment method
- Sufficient credits/balance for droplet creation

---

## Test Procedure

### Step 1: Create Digital Ocean Droplet

1. **Login to Digital Ocean** → Click "Create" → "Droplets"

2. **Choose Region**: Select region closest to you

3. **Choose Image**:
   - Select "Marketplace" tab
   - Search for "Docker on Ubuntu"
   - Select "Docker on Ubuntu 24.04"

4. **Choose Size**:
   - Droplet Type: Regular SSD
   - Select: 2GB RAM / 1 vCPU / 50GB SSD ($12/month)

5. **Add SSH Key**:
   - Click "New SSH Key"
   - Paste your public key from prerequisites
   - Give it a recognizable name

6. **Advanced Options**:
   - ✅ Enable Monitoring
   - ✅ Enable IPv6 (required for Supabase sync)

7. **Finalize**:
   - Hostname: `openwebui-test-build`
   - Click "Create Droplet"
   - **Note the IP address** once created

**Expected Result**: ✅ Droplet created and shows "Running" status

**Wait Time**: ~60 seconds for droplet to fully initialize

---

### Step 2: Run Quick Setup Script

1. **SSH to droplet as root**:

```bash
ssh root@YOUR_DROPLET_IP
```

**Expected Output**:
```
Welcome to Ubuntu 24.04.x LTS
...
root@openwebui-test-build:~#
```

2. **Run quick-setup.sh** (auto-copy SSH key mode):

```bash
curl -fsSL https://raw.githubusercontent.com/imagicrafter/open-webui/main/mt/setup/quick-setup.sh | bash -s -- "" "test"
```

**Expected Output**:
```
════════════════════════════════════════
   Open WebUI Quick Setup (Test Mode)
════════════════════════════════════════

✅ Running as root
✅ SSH key will be auto-copied from root
✅ Installing system packages...
✅ Configuring qbmgr user...
✅ Setting up Docker...
✅ Cloning Open WebUI repository...
✅ Configuring security settings...
✅ Setup completed successfully!

Next steps:
  1. exit (to logout from root)
  2. ssh qbmgr@YOUR_DROPLET_IP
```

**Pass Criteria**:
- No error messages during installation
- All steps show green checkmarks (✅)
- "Setup completed successfully!" appears

**Fail Criteria**:
- Red X marks (❌) appear
- Script exits with error
- Permission denied errors

---

### Step 3: Login as qbmgr User

1. **Exit root session**:

```bash
exit
```

2. **SSH as qbmgr**:

```bash
ssh qbmgr@YOUR_DROPLET_IP
```

**Expected Output**:
```
╔════════════════════════════════════════╗
║       Open WebUI Client Manager        ║
╚════════════════════════════════════════╝

1) View Deployment Status
2) Create New Deployment
3) Manage Client Deployment
4) Manage Sync Cluster
5) Manage nginx Installation
6) Security Advisor
7) Exit

Please select an option (1-7):
```

**Pass Criteria**:
- Client-manager menu displays automatically
- Menu shows all 7 options
- No error messages appear

**Fail Criteria**:
- Client-manager doesn't start
- Error messages appear
- Menu is missing options

---

### Step 4: Verify Installed Tools

From the client-manager menu, select option 7 to exit, then run verification commands:

```bash
# Exit client-manager
# (Select option 7)

# Verify Docker
docker --version
docker ps

# Verify Git
git --version

# Verify repository cloned
ls -la ~/open-webui/mt/

# Verify nginx availability (not installed yet)
nginx -v 2>&1 | grep -q "not found" && echo "nginx not installed (expected)" || echo "nginx found"

# Verify certbot availability
which certbot
```

**Expected Output**:

```bash
# Docker version
Docker version 24.0.x, build xxxxx

# Docker ps (empty is ok)
CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES

# Git version
git version 2.x.x

# Repository files
drwxr-xr-x ... client-manager.sh
drwxr-xr-x ... start-template.sh
drwxr-xr-x ... DB_MIGRATION
...

# nginx check
nginx not installed (expected)

# certbot check
(no output = not installed, which is expected)
```

**Pass Criteria**:
- Docker installed and running
- Git installed
- Repository cloned to ~/open-webui
- Client-manager.sh exists and is executable

---

### Step 5: Verify qbmgr Permissions

Test sudo access (should NOT prompt for password):

```bash
# Test passwordless sudo
sudo whoami

# Test docker group membership
docker ps

# Test file permissions
ls -la ~/.ssh/authorized_keys
```

**Expected Output**:

```bash
# sudo whoami
root

# docker ps
CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES
(empty or shows containers)

# authorized_keys permissions
-rw------- 1 qbmgr qbmgr ... /home/qbmgr/.ssh/authorized_keys
```

**Pass Criteria**:
- `sudo whoami` returns "root" without password prompt
- `docker ps` works without "permission denied"
- authorized_keys has 600 permissions

**Fail Criteria**:
- Sudo prompts for password
- Docker commands require sudo
- SSH key file has wrong permissions

---

### Step 6: Verify Security Configuration

Check that security hardening was applied:

```bash
# Check root SSH login disabled
sudo grep "^PermitRootLogin" /etc/ssh/sshd_config

# Check firewall enabled
sudo ufw status

# Check fail2ban installed
systemctl status fail2ban
```

**Expected Output**:

```bash
# PermitRootLogin
PermitRootLogin no

# UFW status
Status: active
To                         Action      From
--                         ------      ----
22/tcp                     ALLOW       Anywhere
22/tcp (v6)                ALLOW       Anywhere (v6)

# fail2ban status
● fail2ban.service - Fail2Ban Service
     Loaded: loaded
     Active: active (running)
```

**Pass Criteria**:
- Root SSH login disabled
- UFW firewall active
- fail2ban service running

---

### Step 7: Test Client-Manager Re-launch

```bash
# Navigate to repository
cd ~/open-webui/mt

# Launch client-manager
./client-manager.sh
```

**Expected Output**:
```
╔════════════════════════════════════════╗
║       Open WebUI Client Manager        ║
╚════════════════════════════════════════╝

1) View Deployment Status
2) Create New Deployment
3) Manage Client Deployment
4) Manage Sync Cluster
5) Manage nginx Installation
6) Security Advisor
7) Exit

Please select an option (1-7):
```

**Pass Criteria**:
- Client-manager launches successfully
- Menu displays correctly
- All options accessible

---

## Test Summary

### Pass Criteria Checklist

- [ ] Droplet created successfully
- [ ] Quick-setup script completed without errors
- [ ] qbmgr user can SSH with key-based auth
- [ ] Client-manager auto-starts on qbmgr login
- [ ] Docker installed and accessible without sudo
- [ ] Git installed and repository cloned
- [ ] qbmgr has passwordless sudo access
- [ ] Firewall (UFW) enabled and configured
- [ ] fail2ban service running
- [ ] Root SSH login disabled
- [ ] Client-manager can be manually launched

### Overall Test Result

**PASS**: All checklist items ✅
**FAIL**: Any checklist item ❌

---

## Troubleshooting

### Issue: quick-setup.sh fails with permission errors

**Solution**:
```bash
# Ensure you're running as root
whoami  # Should output: root

# Re-run setup
curl -fsSL https://raw.githubusercontent.com/imagicrafter/open-webui/main/mt/setup/quick-setup.sh | bash -s -- "" "test"
```

### Issue: Can't SSH as qbmgr

**Solution**:
```bash
# As root, check SSH key was copied
sudo cat /home/qbmgr/.ssh/authorized_keys

# Fix permissions if needed
sudo chmod 700 /home/qbmgr/.ssh
sudo chmod 600 /home/qbmgr/.ssh/authorized_keys
sudo chown -R qbmgr:qbmgr /home/qbmgr/.ssh
```

### Issue: Docker permission denied

**Solution**:
```bash
# Logout and login again to activate docker group
exit
ssh qbmgr@YOUR_DROPLET_IP

# Or manually activate group
newgrp docker
```

### Issue: Client-manager doesn't auto-start

**Solution**:
```bash
# Check .bash_profile exists
cat ~/.bash_profile

# Manually start client-manager
cd ~/open-webui/mt
./client-manager.sh
```

---

## Cleanup

After test completion:

```bash
# Exit SSH session
exit

# Optional: Destroy droplet to avoid charges
# (via Digital Ocean web interface)
```

---

## Test Metadata

- **Test ID**: NEW_SERVER_BUILD_TEST
- **Version**: 1.0
- **Last Updated**: 2025-10-25
- **Maintainer**: Open WebUI MT Team
- **Related Documentation**: mt/setup/README.md
