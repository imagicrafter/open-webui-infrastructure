# Client Deployment Test Plan

**Purpose**: Validate end-to-end client deployment with HTTPS and OAuth
**Environment**: Server with nginx installed (HOST mode recommended)
**Test Domain**: chat-test-01.quantabase.io (or your test domain)
**Expected Duration**: 15-20 minutes
**Prerequisites**:
- NEW_SERVER_BUILD_TEST.md completed
- NGINX_BUILD_TEST.md completed
- HOST nginx installed and running
- DNS access to configure test domain

---

## Test Objectives

- Verify complete client deployment workflow
- Test automated nginx config generation and installation
- Validate staging SSL certificate generation
- Confirm HTTPS access works correctly
- Test Google OAuth login (no redirect loops)
- **CRITICAL**: Validate function pipes work (core functionality test)
- Verify WEBUI_BASE_URL configured correctly

---

## Prerequisites

### 1. Server Setup

- Server provisioned via quick-setup.sh
- qbmgr user configured
- HOST nginx installed and running
- Ports 80 and 443 open in firewall

### 2. DNS Configuration

**Test Domain**: `chat-test-01.quantabase.io` (replace with your domain)

Configure DNS A record:

```bash
# Get server IP
curl -s ifconfig.me

# Create A record in your DNS provider
# chat-test-01.quantabase.io → YOUR_SERVER_IP
```

**Verification** (wait 1-5 minutes for propagation):
```bash
dig chat-test-01.quantabase.io +short
# Should return: YOUR_SERVER_IP
```

### 3. Google OAuth Setup

**Google Cloud Console**: https://console.cloud.google.com/apis/credentials?project=quantabase

Add to authorized URIs:
- **Authorized JavaScript Origins**:
  - `https://chat-test-01.quantabase.io`

- **Authorized Redirect URIs**:
  - `https://chat-test-01.quantabase.io/oauth/google/callback`

**Save changes** in Google Cloud Console

---

## Test Procedure

### Test 1: Create Client Deployment

**Objective**: Deploy a new Open WebUI client instance

```bash
# Launch client-manager
cd ~/open-webui/mt
./client-manager.sh

# Select: 2) Create New Deployment
```

#### Step 1.1: Enter Deployment Details

**Prompts and Responses**:

```
Client Name: chat-test-01
Port: 8091
Domain: chat-test-01.quantabase.io
```

**Expected Output**:
```
╔════════════════════════════════════════╗
║         Create New Deployment          ║
╚════════════════════════════════════════╝

Enter client name: chat-test-01
Enter port (default: 8080): 8091
Enter domain (or localhost): chat-test-01.quantabase.io

Creating deployment for chat-test-01...
- Port: 8091
- Domain: chat-test-01.quantabase.io
- Container: openwebui-chat-test-01

Pulling Docker image...
✅ Image pulled successfully

Creating container...
✅ Container created successfully

Starting container...
✅ Container started successfully

Deployment created successfully!

Container: openwebui-chat-test-01
Access: http://localhost:8091 (local)
        https://chat-test-01.quantabase.io (after nginx setup)

Press Enter to continue...
```

**Pass Criteria**:
- Container created without errors
- Container starts successfully
- Correct port assigned (8091)
- Domain configured correctly

#### Step 1.2: Verify Container Running

```bash
# Exit client-manager
docker ps --filter "name=openwebui-chat-test-01"

# Check container environment
docker exec openwebui-chat-test-01 env | grep -E "FQDN|WEBUI_BASE_URL|CLIENT_NAME"
```

**Expected Output**:
```bash
# docker ps
CONTAINER ID   IMAGE                              STATUS        PORTS
abc123...      ghcr.io/imagicrafter/open-webui... Up X seconds  0.0.0.0:8091->8080/tcp

# Environment variables
CLIENT_NAME=chat-test-01
FQDN=chat-test-01.quantabase.io
WEBUI_BASE_URL=https://chat-test-01.quantabase.io
```

**Pass Criteria**:
- Container running (status "Up")
- Port 8091 mapped correctly
- FQDN set to test domain
- **WEBUI_BASE_URL set to https://chat-test-01.quantabase.io** (critical for OAuth)

---

### Test 2: Generate nginx Configuration

**Objective**: Test automated nginx config generation and installation

```bash
# Launch client-manager
./client-manager.sh

# Select: 5) Manage nginx Installation
# Select: 4) Generate nginx Configuration for Client
```

#### Step 2.1: Select Client and Configure

**Prompts and Responses**:

```
Available deployments:
1) chat-test-01 → chat-test-01.quantabase.io (port: 8091) [❌ Not configured]
2) Return to main menu

Select client for nginx config (1-2): 1
```

**Expected Output**:
```
Generating production nginx configuration...
(HTTPS with Let's Encrypt SSL)

Enter production domain [chat-test-01.quantabase.io]:
```

**Action**: Press Enter to accept default

**Expected Output**:
```
✅ nginx configuration generated successfully!
   Location: /tmp/chat-test-01.quantabase.io-nginx.conf

📋 Installing nginx configuration...

✅ Config copied to /etc/nginx/sites-available/chat-test-01.quantabase.io
✅ Site enabled
🔍 Testing nginx configuration...
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
✅ nginx configuration test passed

Reload nginx now? (y/N):
```

**Action**: Type `y` and press Enter

**Expected Output**:
```
✅ nginx reloaded successfully

Next steps:
1. Configure DNS (if not done already)
2. Generate SSL certificate
3. Access: https://chat-test-01.quantabase.io

Press Enter to continue...
```

**Pass Criteria**:
- Config file generated
- Config automatically copied to /etc/nginx/sites-available/
- Site automatically enabled
- nginx configuration test passes
- nginx reloads successfully
- **No manual copy/paste required** (automation working)

---

### Test 3: Generate Staging SSL Certificate

**Objective**: Test automated staging certificate generation

**Note**: Using staging certificate for testing to avoid Let's Encrypt rate limits

#### Step 3.1: Verify DNS Propagation

```bash
# Exit client-manager and verify DNS
dig chat-test-01.quantabase.io +short
```

**Expected Output**: Your server's IP address

**If DNS not ready**: Wait 1-5 minutes and retry

#### Step 3.2: Generate Certificate

```bash
# Return to client-manager
./client-manager.sh

# Select: 5) Manage nginx Installation
# Select: 4) Generate nginx Configuration for Client
# Select your client (chat-test-01)
```

**Expected Output**:
```
═══════════════════════════════════════
SSL Certificate Setup
═══════════════════════════════════════

⚠️  NOTE: DNS must be configured and propagated first!

Do you want to generate an SSL certificate now?
1) Production certificate (Let's Encrypt - rate limited)
2) Staging certificate (for testing - no rate limits)
3) Skip (generate later)

Choose option (1-3):
```

**Action**: Type `2` and press Enter

**Expected Output**:
```
Generating staging SSL certificate...
ℹ️  This creates a test certificate (not trusted by browsers)

Saving debug log to /var/log/letsencrypt/letsencrypt.log
Account registered.
Requesting a certificate for chat-test-01.quantabase.io

Successfully received certificate.
Certificate is saved at: /etc/letsencrypt/live/chat-test-01.quantabase.io/fullchain.pem
Key is saved at:         /etc/letsencrypt/live/chat-test-01.quantabase.io/privkey.pem

Deploying certificate to VirtualHost /etc/nginx/sites-enabled/chat-test-01.quantabase.io
Redirecting all traffic on port 80 to ssl in /etc/nginx/sites-enabled/chat-test-01.quantabase.io

✅ Staging SSL certificate installed!
⚠️  This is a TEST certificate - browsers will show warnings

For production certificate:
  1. Remove staging cert: sudo certbot delete --cert-name chat-test-01.quantabase.io
  2. Run option 4 again and choose production

Press Enter to continue...
```

**Pass Criteria**:
- Certificate generated successfully
- Certificate saved to /etc/letsencrypt/live/
- nginx automatically configured for HTTPS
- HTTP redirects to HTTPS configured
- No manual intervention required

---

### Test 4: Verify HTTPS Access

**Objective**: Confirm HTTPS access works correctly

```bash
# Exit client-manager
# Test HTTPS access
curl -k https://chat-test-01.quantabase.io 2>&1 | head -20
```

**Expected Output**:
```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8">
    <title>QuantaBase</title>
    ...
```

**Pass Criteria**:
- HTTPS responds (even with staging cert warning)
- HTML page loads
- No connection refused errors

#### Browser Test

**Action**: Open browser to `https://chat-test-01.quantabase.io`

**Expected Behavior**:
1. Browser shows SSL warning (expected for staging cert)
2. Click "Advanced" → "Proceed to site"
3. **Login page appears** (no redirect loops!)
4. See "Sign in with Google" button

**Pass Criteria**:
- ✅ HTTPS loads (with staging cert warning)
- ✅ Login page displays correctly
- ✅ **NO redirect loops** (critical - WEBUI_BASE_URL working)
- ✅ Google OAuth button visible

**Fail Criteria**:
- ❌ Browser keeps redirecting endlessly
- ❌ Page never loads
- ❌ 502 Bad Gateway errors

---

### Test 5: Test Google OAuth Login

**Objective**: Verify OAuth authentication works without redirect loops

⚠️ **Prerequisites**:
- Google OAuth URIs configured (see Prerequisites section)
- User has @martins.net email (or configured OAuth domain)

#### Step 5.1: Initiate OAuth Login

**Action**: Click "Sign in with Google" button

**Expected Behavior**:
1. Redirects to Google login page
2. Shows Google account selection
3. After selecting account, redirects back to https://chat-test-01.quantabase.io
4. **Loads directly to chat interface** (no flashing/looping)

**Pass Criteria**:
- ✅ Redirect to Google works
- ✅ Returns to site after authentication
- ✅ **NO redirect loops** (stays on chat page)
- ✅ User logged in successfully
- ✅ Chat interface displays

**Fail Criteria**:
- ❌ Endless redirects between Google and site
- ❌ Page flashes and reloads repeatedly
- ❌ "OAuth error" messages
- ❌ 401/403 errors

#### Debugging OAuth Issues

If redirect loops occur:

```bash
# Check WEBUI_BASE_URL is set
docker exec openwebui-chat-test-01 env | grep WEBUI_BASE_URL
# Expected: WEBUI_BASE_URL=https://chat-test-01.quantabase.io

# Check OAuth redirect URI
docker exec openwebui-chat-test-01 env | grep GOOGLE_REDIRECT_URI
# Expected: GOOGLE_REDIRECT_URI=https://chat-test-01.quantabase.io/oauth/google/callback

# Check nginx proxy headers
sudo cat /etc/nginx/sites-available/chat-test-01.quantabase.io | grep -A5 "location /"
```

---

### Test 6: Test Function Pipes (CRITICAL)

**Objective**: Verify function pipe saves work correctly (validates nginx is not breaking core functionality)

⚠️ **This is the PRIMARY test** for validating nginx deployment mode

#### Step 6.1: Create Function with Pipe

**Action**: In the Open WebUI interface:

1. Navigate to **Workspace** → **Functions**
2. Click **"+"** to create new function
3. Enter function name: `test_pipe_function`
4. Add test code (any simple function)
5. Click **Save** (pipe icon)

**Expected Behavior**:
- Save button processes
- Shows "Function saved successfully" message
- Function appears in function list

**Pass Criteria**:
- ✅ Function saves without errors
- ✅ Success message displays
- ✅ Function persists (appears in list)
- ✅ Can edit and re-save function

**Fail Criteria**:
- ❌ Save fails with network error
- ❌ 502 Bad Gateway on save
- ❌ Function doesn't persist
- ❌ `/api/v1/utils/code/format` endpoint fails

#### Why This Test is Critical

**Context from ROOT_CAUSE_NGINX_CONTAINERIZATION.md**:
- Containerized nginx breaks `/api/v1/utils/code/format` endpoint
- This prevents function pipe saves from working
- HOST nginx with port mapping works correctly
- This test validates the fix is working

**If this test fails**:
- nginx deployment is NOT production-ready
- Revert to containerized nginx troubleshooting
- Check nginx proxy configuration

---

### Test 7: Verify Deployment Status

**Objective**: Confirm deployment shows as configured in client-manager

```bash
./client-manager.sh

# Select: 1) View Deployment Status
```

**Expected Output**:
```
╔════════════════════════════════════════╗
║        Deployment Status               ║
╚════════════════════════════════════════╝

Client Deployments:
┌──────────────┬─────────┬──────────────────────────────────┬──────────┬────────┐
│ Name         │ Status  │ Domain                           │ Port     │ nginx  │
├──────────────┼─────────┼──────────────────────────────────┼──────────┼────────┤
│ chat-test-01 │ Running │ chat-test-01.quantabase.io       │ 8091     │ ✅ SSL │
└──────────────┴─────────┴──────────────────────────────────┴──────────┴────────┘

Press Enter to continue...
```

**Pass Criteria**:
- Client shows status "Running"
- Domain listed correctly
- Port shown as 8091
- nginx status shows "✅ SSL" or "✅ Configured"

---

## Test Summary

### Test Results Table

| Test | Description | Result | Critical |
|------|-------------|--------|----------|
| 1    | Create client deployment | ☐ PASS ☐ FAIL | Yes |
| 2    | Generate nginx config (automated) | ☐ PASS ☐ FAIL | Yes |
| 3    | Generate staging SSL cert | ☐ PASS ☐ FAIL | Yes |
| 4    | Verify HTTPS access | ☐ PASS ☐ FAIL | Yes |
| 5    | Test OAuth login (no loops) | ☐ PASS ☐ FAIL | **CRITICAL** |
| 6    | Test function pipes | ☐ PASS ☐ FAIL | **CRITICAL** |
| 7    | Verify deployment status | ☐ PASS ☐ FAIL | No |

### Pass Criteria Checklist

- [ ] Client container created and running
- [ ] WEBUI_BASE_URL set correctly to https:// domain
- [ ] nginx config generated automatically
- [ ] nginx config installed without manual steps
- [ ] nginx configuration test passes
- [ ] Staging SSL certificate generated
- [ ] HTTPS site loads correctly
- [ ] **NO OAuth redirect loops** (critical)
- [ ] **Function pipes save successfully** (critical)
- [ ] Google OAuth login works
- [ ] Deployment status shows correct info

### Overall Test Result

**PASS**: All tests ✅ (especially Tests 5 and 6)
**FAIL**: Any critical test ❌

---

## Validation Success Indicators

### 🎯 Primary Success Indicators

1. **WEBUI_BASE_URL Fix Working**: No OAuth redirect loops
2. **nginx Deployment Validated**: Function pipes save correctly
3. **Automation Working**: No manual config file copying required

### ⚠️ If Tests Fail

**OAuth Redirect Loops (Test 5 fails)**:
- WEBUI_BASE_URL not set or incorrect
- Check container env: `docker exec openwebui-chat-test-01 env | grep WEBUI_BASE_URL`
- Should be `https://` not `http://`

**Function Pipes Fail (Test 6 fails)**:
- nginx proxy configuration issue
- Check nginx config for `/api/v1/utils/code/format` endpoint
- May need to switch nginx deployment mode

---

## Troubleshooting

### Issue: DNS not resolving

**Symptom**: `dig chat-test-01.quantabase.io` returns no results

**Solution**:
```bash
# Wait for DNS propagation (can take 1-5 minutes)
# Check nameservers
dig chat-test-01.quantabase.io +trace

# Verify A record configured in DNS provider
```

### Issue: SSL certificate generation fails

**Symptom**:
```
Failed to obtain certificate
Challenge failed
```

**Solution**:
```bash
# Verify DNS resolves
dig chat-test-01.quantabase.io +short

# Check nginx is listening on port 80
sudo netstat -tlnp | grep :80

# Test manual certbot
sudo certbot --nginx -d chat-test-01.quantabase.io --staging --dry-run
```

### Issue: OAuth redirect loops

**Symptom**: Browser keeps redirecting between site and Google

**Solution**:
```bash
# Verify WEBUI_BASE_URL is HTTPS
docker exec openwebui-chat-test-01 env | grep WEBUI_BASE_URL
# Must be: https://chat-test-01.quantabase.io

# If wrong, recreate container with correct BASE_URL
docker stop openwebui-chat-test-01
docker rm openwebui-chat-test-01

# Recreate via client-manager (will auto-set WEBUI_BASE_URL)
```

### Issue: Function pipes don't save

**Symptom**: Save fails, 502 errors, or network timeout

**Solution**:
```bash
# Check nginx is HOST mode (not containerized)
systemctl status nginx
# Should show: active (running)

# Check nginx error logs
sudo tail -50 /var/log/nginx/error.log

# Test endpoint directly
curl -X POST http://localhost:8091/api/v1/utils/code/format
```

---

## Cleanup

After test completion:

```bash
# Option 1: Keep deployment for further testing
# (No cleanup needed)

# Option 2: Remove test deployment
./client-manager.sh
# Select: 3) Manage Client Deployment
# Select: chat-test-01
# Select: Remove deployment

# Option 3: Remove SSL certificate
sudo certbot delete --cert-name chat-test-01.quantabase.io
```

---

## Test Metadata

- **Test ID**: CLIENT_DEPLOYMENT_TEST
- **Version**: 1.0
- **Last Updated**: 2025-10-25
- **Maintainer**: Open WebUI MT Team
- **Prerequisites**:
  - NEW_SERVER_BUILD_TEST.md
  - NGINX_BUILD_TEST.md
- **Related Documentation**:
  - mt/README.md (Production Deployment section)
  - mt/nginx/DEV_PLAN_FOR_NGINX_GET_WELL.md (Root cause documentation)
- **Critical Validations**:
  - WEBUI_BASE_URL fix (prevents OAuth loops)
  - HOST nginx functionality (pipe saves work)
