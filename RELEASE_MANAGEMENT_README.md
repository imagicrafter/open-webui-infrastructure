# Open WebUI Release Management Guide

**Date:** 2025-01-23
**Purpose:** Define best practices for managing releases, Docker images, and deployments
**Target Audience:** Developers and DevOps managing Open WebUI deployments

---

## Table of Contents

1. [Overview](#overview)
2. [Branch Strategy](#branch-strategy)
3. [Docker Image Management](#docker-image-management)
4. [Release Workflow](#release-workflow)
5. [Testing Checklist](#testing-checklist)
6. [Updating Pinned Images](#updating-pinned-images)
7. [Rollback Procedures](#rollback-procedures)
8. [Common Scenarios](#common-scenarios)
9. [Best Practices](#best-practices)
10. [Troubleshooting](#troubleshooting)

---

## Overview

### The Problem This Solves

Previously, every commit to `main` triggered automatic Docker image builds. This caused:
- ❌ Unpredictable production deployments
- ❌ Untested changes going to production
- ❌ Difficult rollbacks when issues occurred
- ❌ The pipe save JSON error incident (Oct 2025)

### The Solution

**Two-Branch Strategy with Pinned Images:**
- `main` branch = Development and testing (no auto-builds)
- `release` branch = Production-ready code (triggers image builds)
- Deployment scripts use pinned image digests for stability
- Manual promotion process ensures thorough testing

---

## Branch Strategy

### Branch Roles

| Branch | Purpose | Auto-Build | Used For |
|--------|---------|------------|----------|
| **main** | Development & Testing | ❌ No | Day-to-day development, feature work, testing |
| **release** | Production | ✅ Yes | Stable, tested code ready for production deployment |
| **feat/*** | Feature Branches | ❌ No | Isolated feature development before merging to main |

### Branch Flow

```
┌─────────────┐
│ Development │
│   (main)    │
└──────┬──────┘
       │
       │ Daily commits, testing, iterations
       │
       ├─→ Feature branches (feat/*)
       │   └─→ Merge back to main after testing
       │
       ├─→ Test deployments verify changes
       │
       └─→ When stable...
           ↓
┌──────────────┐
│  Production  │
│  (release)   │  ← Merge from main
└──────┬───────┘
       │
       └─→ GitHub Actions builds Docker image
           └─→ Tagged as ghcr.io/imagicrafter/open-webui:release
```

---

## Docker Image Management

### Current Image Strategy

**Production deployments use PINNED DIGESTS:**
```bash
# Deployment scripts reference specific image digest
ghcr.io/imagicrafter/open-webui@sha256:bdf98b7bf21c32db09522d90f80715af668b2bd8c58cf9d02777940773ab7b27

# NOT using mutable tags like:
# ghcr.io/imagicrafter/open-webui:release  # ← Tag can change
```

### Why Pinned Digests?

| Approach | Behavior | Risk |
|----------|----------|------|
| **Tag (`:release`)** | Points to latest release build | Tag updates with every release merge |
| **Digest (`@sha256:...`)** | Always same image | Zero risk of unexpected updates |

**Our approach:** Pin to known-good digest, update manually after testing new images.

### Image Tagging

When you merge to `release` branch, GitHub Actions creates:
- **Tag:** `ghcr.io/imagicrafter/open-webui:release`
- **Digest:** `sha256:xxxxxxxxx...` (unique hash for this build)

**Example:**
```bash
# After release merge, GitHub Actions builds and tags:
ghcr.io/imagicrafter/open-webui:release
# Which has digest:
ghcr.io/imagicrafter/open-webui@sha256:abc123def456...

# Your deployment scripts use the digest:
ghcr.io/imagicrafter/open-webui@sha256:bdf98b7bf21c...  # Previous stable
```

---

## Release Workflow

### Step-by-Step Release Process

#### Phase 1: Development (main branch)

1. **Create feature branch (optional):**
   ```bash
   git checkout main
   git pull origin main
   git checkout -b feat/my-new-feature
   ```

2. **Develop and commit:**
   ```bash
   # Make changes
   git add .
   git commit -m "feat: Add new feature"
   git push origin feat/my-new-feature
   ```

3. **Merge to main:**
   ```bash
   git checkout main
   git merge feat/my-new-feature
   git push origin main
   ```

   **Result:** Code pushed to main, **NO Docker image built** ✅

#### Phase 2: Testing (main branch)

4. **Deploy to test server:**
   ```bash
   # SSH to test server
   ssh qbmgr@test-server-ip

   # Pull latest main
   cd ~/open-webui
   git pull origin main

   # Deploy test instance
   cd mt
   ./client-manager.sh
   # → Create test deployment
   ```

5. **Run testing checklist** (see [Testing Checklist](#testing-checklist) below)

6. **Iterate if needed:**
   - Fix issues on `main`
   - Redeploy to test
   - Repeat until stable

#### Phase 3: Release Promotion

7. **Merge to release branch:**
   ```bash
   git checkout release
   git pull origin release
   git merge main -m "Release: Promote tested changes from main"
   git push origin release
   ```

   **Result:** GitHub Actions automatically builds new Docker image ✅

8. **Wait for build completion:**
   - Go to: https://github.com/imagicrafter/open-webui/actions
   - Wait for "Build and Push Docker Image" to complete
   - Check for green checkmark ✅

9. **Get new image digest:**
   ```bash
   # Pull the newly built release image
   docker pull ghcr.io/imagicrafter/open-webui:release

   # Get its digest
   docker inspect ghcr.io/imagicrafter/open-webui:release --format='{{json .RepoDigests}}' | jq

   # Output example:
   # ["ghcr.io/imagicrafter/open-webui@sha256:abc123def456..."]
   ```

10. **Test new image on test server:**
    ```bash
    # On test server, manually test the new release image
    docker run -d \
      --name test-new-release \
      -p 8082:8080 \
      ghcr.io/imagicrafter/open-webui@sha256:abc123def456... \
      # ... other env vars

    # Test thoroughly!
    ```

11. **Update pinned digest in scripts:**
    ```bash
    # On your development machine
    git checkout main

    # Edit these files:
    # - mt/start-template.sh (line ~94)
    # - mt/client-manager.sh (lines ~2265, ~2289)

    # Replace old digest with new digest:
    # OLD: ghcr.io/imagicrafter/open-webui@sha256:bdf98b7bf21c...
    # NEW: ghcr.io/imagicrafter/open-webui@sha256:abc123def456...
    ```

12. **Commit digest update:**
    ```bash
    git add mt/start-template.sh mt/client-manager.sh
    git commit -m "chore: Update Docker image pin to release sha256:abc123def456"
    git push origin main

    # Also merge to release
    git checkout release
    git merge main
    git push origin release
    ```

#### Phase 4: Production Deployment

13. **Deploy to production servers:**
    ```bash
    # SSH to production server
    ssh qbmgr@production-server-ip

    # Pull updated scripts with new digest
    cd ~/open-webui
    git pull origin main

    # New deployments will use the new pinned image
    cd mt
    ./client-manager.sh
    # → Create production deployment
    ```

14. **Monitor production:**
    - Check logs: `docker logs <container-name>`
    - Test functionality
    - Monitor for errors

---

## Testing Checklist

### Pre-Release Testing (on test server)

Before promoting `main` to `release`, verify:

#### Core Functionality
- [ ] Google OAuth authentication works
- [ ] User can log in successfully
- [ ] Chat interface loads properly
- [ ] Messages send and receive

#### Pipe Functions
- [ ] Can save pipe functions (e.g., `do-function-pipe.py`)
- [ ] No JSON serialization errors
- [ ] Pipe functions execute correctly
- [ ] Follow-ups and titles generate properly

#### Admin Functions
- [ ] Admin panel accessible
- [ ] Settings can be modified
- [ ] User management works

#### Multi-Tenant Features
- [ ] Container isolation works
- [ ] Volume persistence correct
- [ ] Environment variables properly set
- [ ] Domain/OAuth configuration correct

#### Integration Tests
- [ ] nginx proxy works (if containerized)
- [ ] SSL certificates valid
- [ ] Database persistence after restart

#### Performance
- [ ] Response times acceptable
- [ ] Memory usage normal
- [ ] No memory leaks observed

### Post-Release Testing (on production)

After deploying new digest to production:

- [ ] All core functionality verified
- [ ] Existing user sessions maintained
- [ ] Data persistence verified
- [ ] Monitor logs for 24 hours
- [ ] User acceptance testing

---

## Updating Pinned Images

### When to Update

Update the pinned digest when:
1. ✅ New features successfully tested on test server
2. ✅ Bug fixes verified
3. ✅ Security updates applied
4. ✅ Upstream Open WebUI improvements merged

### How to Update

**1. Build new image (automatic on release merge):**
```bash
git checkout release
git merge main
git push origin release
# Wait for GitHub Actions to complete
```

**2. Get the new digest:**
```bash
docker pull ghcr.io/imagicrafter/open-webui:release

# Method 1: From RepoDigests
docker inspect ghcr.io/imagicrafter/open-webui:release \
  --format='{{json .RepoDigests}}' | jq

# Method 2: From manifest
docker manifest inspect ghcr.io/imagicrafter/open-webui:release | grep digest
```

**3. Test new image:**
```bash
# On test server
docker run -d --name test-new-image \
  -p 8099:8080 \
  ghcr.io/imagicrafter/open-webui@sha256:NEW_DIGEST_HERE

# Run full testing checklist
```

**4. Update deployment scripts:**

Edit `mt/start-template.sh` (line ~94):
```bash
# OLD:
ghcr.io/imagicrafter/open-webui@sha256:bdf98b7bf21c32db09522d90f80715af668b2bd8c58cf9d02777940773ab7b27

# NEW:
ghcr.io/imagicrafter/open-webui@sha256:NEW_DIGEST_HERE
```

Edit `mt/client-manager.sh` (search for all `sha256:` references):
```bash
# Find all occurrences:
grep -n "sha256:" mt/client-manager.sh

# Update each one to new digest
```

**5. Document the update:**

Update `mt/VAULT/DOCKER_IMAGE_PIN.md`:
```markdown
## Current Pinned Image

- **Repository Digest:** `sha256:NEW_DIGEST_HERE`
- **Updated:** 2025-XX-XX
- **Reason:** [Description of changes]
- **Tested:** [Test results summary]
```

**6. Commit and deploy:**
```bash
git add mt/start-template.sh mt/client-manager.sh mt/VAULT/DOCKER_IMAGE_PIN.md
git commit -m "chore: Update Docker image pin to sha256:NEW_DIGEST_HERE

- Tested on test server
- All checks passed
- Reason: [your reason]"

git push origin main

# Merge to release
git checkout release
git merge main
git push origin release
```

---

## Rollback Procedures

### Scenario 1: Rollback Code Changes (Before Image Build)

If issues found on `main` branch before merging to `release`:

```bash
# Option A: Revert specific commit
git checkout main
git revert <commit-hash>
git push origin main

# Option B: Reset to previous state
git checkout main
git reset --hard <previous-good-commit>
git push origin main --force  # Use with caution!
```

### Scenario 2: Rollback Docker Image

If new image has issues after deployment:

**Method 1: Update to previous digest (recommended):**
```bash
# Get previous working digest from git history
git log -p mt/start-template.sh | grep sha256

# Update scripts to previous digest
# Commit and push
# Redeploy affected containers
```

**Method 2: Rollback release branch:**
```bash
git checkout release
git revert <commit-hash>
git push origin release

# This triggers new build with reverted code
```

### Scenario 3: Emergency Production Rollback

If production is broken and needs immediate fix:

**Quick rollback to last known-good digest:**
```bash
# On production server
docker stop <container-name>
docker rm <container-name>

# Manually deploy with old digest
docker run -d --name <container-name> \
  # ... all environment variables ...
  ghcr.io/imagicrafter/open-webui@sha256:OLD_WORKING_DIGEST

# Verify functionality
# Then update scripts to match
```

**Document the rollback:**
```bash
# Create incident log
echo "Emergency rollback at $(date)" >> mt/VAULT/ROLLBACK_INCIDENTS.md
echo "Rolled back from: sha256:BAD_DIGEST" >> mt/VAULT/ROLLBACK_INCIDENTS.md
echo "Rolled back to: sha256:OLD_WORKING_DIGEST" >> mt/VAULT/ROLLBACK_INCIDENTS.md
```

---

## Common Scenarios

### Scenario: Quick Bug Fix to Production

**Problem:** Bug found in production, needs immediate fix

**Solution:**
```bash
# 1. Fix on main
git checkout main
# Make fix
git commit -m "fix: Critical bug in X"
git push origin main

# 2. Test on test server
ssh qbmgr@test-server
cd ~/open-webui && git pull origin main
# Test thoroughly!

# 3. If urgent, manually build and test image:
# Trigger manual build from GitHub Actions
# Test new image
# Update digest in scripts

# 4. OR if not urgent, follow normal release process
git checkout release
git merge main
git push origin release
# Wait for auto-build, then update digest
```

### Scenario: Testing New Feature Without Building Image

**Problem:** Want to test code changes without creating new production image

**Solution:**
```bash
# Test server automatically tests code from main branch
# without creating production images

# 1. Push to main
git push origin main

# 2. Test server pulls and tests
ssh qbmgr@test-server
cd ~/open-webui && git pull origin main

# 3. No image build triggered (main doesn't auto-build)
# 4. When ready, promote to release
```

### Scenario: Deploying New Server with quick-setup.sh

**Problem:** Need to deploy a new test or production server

**Solution:**

**Interactive Mode (Recommended):**
```bash
# Run quick-setup.sh and select server type when prompted
curl -fsSL https://raw.githubusercontent.com/imagicrafter/open-webui/main/mt/setup/quick-setup.sh | bash

# You'll be prompted:
# Select server type:
#   1) Test Server (uses 'main' branch - latest development code)
#   2) Production Server (uses 'release' branch - stable tested code)
# Enter choice [1 or 2]:
```

**Non-Interactive Mode (Automated):**
```bash
# Test server (main branch)
curl -fsSL https://raw.githubusercontent.com/imagicrafter/open-webui/main/mt/setup/quick-setup.sh | bash -s -- "YOUR_SSH_KEY" "test"

# Production server (release branch)
curl -fsSL https://raw.githubusercontent.com/imagicrafter/open-webui/main/mt/setup/quick-setup.sh | bash -s -- "YOUR_SSH_KEY" "production"
```

**What Happens:**
- **Test Server (main branch):**
  - Gets latest development code
  - Uses pinned digest from main scripts
  - Perfect for testing new features
  - Can be updated frequently: `git pull origin main`

- **Production Server (release branch):**
  - Gets stable, tested code
  - Uses pinned digest from release scripts
  - Production-ready deployments
  - Only updated when release branch is updated

**After Setup:**
```bash
# SSH as qbmgr (client-manager auto-starts)
ssh qbmgr@server-ip

# View server configuration
cat ~/WELCOME.txt
# Shows: Server Type and Git Branch

# Verify branch
cd ~/open-webui
git branch
# Should show: main (test) or release (production)
```

### Scenario: Syncing with Upstream Open WebUI

**Problem:** Need to merge updates from upstream open-webui/open-webui

**Solution:**
```bash
# 1. Add upstream remote (if not already added)
git remote add upstream https://github.com/open-webui/open-webui.git

# 2. Fetch upstream changes
git fetch upstream

# 3. Merge to main for testing
git checkout main
git merge upstream/main
# Resolve conflicts if any
git push origin main

# 4. Test thoroughly on test server
# Run full testing checklist

# 5. If stable, promote to release
git checkout release
git merge main
git push origin release

# 6. New image builds automatically
# Follow "Updating Pinned Images" process
```

### Scenario: Creating Tagged Release

**Problem:** Want to create versioned release (v1.0.0)

**Solution:**
```bash
# 1. Ensure release branch is stable
git checkout release
git pull origin release

# 2. Create and push tag
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0

# 3. GitHub Actions builds tagged image
# Creates: ghcr.io/imagicrafter/open-webui:v1.0.0

# 4. Optionally use versioned tags in deployment scripts
# Instead of digest, could use:
ghcr.io/imagicrafter/open-webui:v1.0.0
```

---

## Best Practices

### Development Workflow

1. **Always develop on `main` or feature branches**
   - Never commit directly to `release`
   - `release` only receives merges from `main`

2. **Test before promoting**
   - Every change tested on test server
   - Use testing checklist
   - Document test results

3. **Small, incremental changes**
   - Easier to test and rollback
   - Reduces risk of complex bugs
   - Faster iteration

4. **Meaningful commit messages**
   ```bash
   # Good:
   git commit -m "fix: Resolve pipe save JSON error by using correct digest"

   # Bad:
   git commit -m "fixed stuff"
   ```

### Image Management

1. **Always use pinned digests in production**
   - Never use `:release` or `:latest` tags in deployment scripts
   - Only update digest after thorough testing

2. **Document image updates**
   - Update `DOCKER_IMAGE_PIN.md` with each change
   - Include reason, test results, date

3. **Keep old digests in git history**
   - Don't force-push over digest updates
   - Git history is your rollback safety net

4. **Test images before deploying**
   - Pull new image to test server first
   - Run full testing checklist
   - Monitor for 24 hours on test server

### Release Cadence

**Recommended schedule:**
- **Daily:** Commits to `main` for development
- **Weekly:** Promote to `release` (if changes are stable)
- **As-needed:** Emergency fixes to `release`
- **Monthly:** Review and update base dependencies

### Security

1. **Review dependency updates**
   - Check Open WebUI upstream for security updates
   - Test thoroughly before promoting

2. **Audit environment variables**
   - Never commit secrets to git
   - Use vault or environment files for sensitive data

3. **Monitor GitHub Actions**
   - Review build logs
   - Check for suspicious changes
   - Enable branch protection on `release`

### Monitoring

1. **Track image build history**
   ```bash
   # List recent builds
   gh run list --workflow=docker.yml --limit 20

   # View specific build
   gh run view <run-id>
   ```

2. **Monitor production deployments**
   - Set up log aggregation
   - Monitor error rates
   - Track response times

3. **Document incidents**
   - Keep rollback log updated
   - Note what went wrong and why
   - Share learnings with team

---

## Troubleshooting

### Problem: GitHub Actions Not Building Image

**Symptoms:** Pushed to `release` branch, but no image build triggered

**Solutions:**
1. Check workflow file syntax:
   ```bash
   # Validate workflow
   cat .github/workflows/docker.yml
   ```

2. Check GitHub Actions page:
   - Go to repository → Actions tab
   - Look for failed or queued builds
   - Check error messages

3. Verify branch protection:
   - Settings → Branches
   - Ensure `release` allows pushes

4. Manually trigger build:
   - Actions → "Build and Push Docker Image"
   - Click "Run workflow"
   - Select `release` branch

### Problem: Digest Not Found When Pulling

**Symptoms:** `docker pull ghcr.io/imagicrafter/open-webui@sha256:xxx...` fails with "manifest unknown"

**Solutions:**
1. Verify digest exists:
   ```bash
   # List available digests
   docker manifest inspect ghcr.io/imagicrafter/open-webui:release
   ```

2. Check if using repository digest vs image ID:
   - **Repository Digest** (for pulling): Starts with `sha256:` from RepoDigests
   - **Image ID** (local only): Starts with `sha256:` from Image field
   - Only repository digest works for pulling!

3. Re-pull latest:
   ```bash
   docker pull ghcr.io/imagicrafter/open-webui:release
   docker inspect ghcr.io/imagicrafter/open-webui:release --format='{{json .RepoDigests}}'
   ```

### Problem: Changes Not Reflected in Test Deployment

**Symptoms:** Pulled latest main, but changes not visible

**Solutions:**
1. Verify git pull succeeded:
   ```bash
   git status
   git log -1  # Check latest commit
   ```

2. Check if using cached image:
   ```bash
   # Remove old container
   docker stop <container>
   docker rm <container>

   # Pull fresh image (if using tag)
   docker pull <image>

   # Redeploy
   ./client-manager.sh
   ```

3. Verify correct scripts:
   ```bash
   # Check which script version is being used
   head -n 20 mt/client-manager.sh
   ```

### Problem: Pipe Save Still Failing After Image Update

**Symptoms:** Updated digest, but pipe save errors persist

**Solutions:**
1. Verify container is using new digest:
   ```bash
   docker inspect <container> --format='{{.Config.Image}}'
   # Should show new digest
   ```

2. Check image was actually pulled:
   ```bash
   docker images | grep <digest-prefix>
   ```

3. Completely recreate container:
   ```bash
   docker stop <container>
   docker rm <container>
   docker system prune -a  # Remove cached images
   # Redeploy
   ```

4. Verify environment variables:
   ```bash
   docker exec <container> env | sort
   # Compare with working deployment
   ```

---

## Quick Reference

### Key Commands

```bash
# Development
git checkout main
git pull origin main
# ... make changes ...
git commit -m "feat: Description"
git push origin main

# Promote to release
git checkout release
git merge main
git push origin release

# Get new image digest
docker pull ghcr.io/imagicrafter/open-webui:release
docker inspect ghcr.io/imagicrafter/open-webui:release --format='{{json .RepoDigests}}' | jq

# Update pinned digest
vim mt/start-template.sh  # Update line ~94
vim mt/client-manager.sh  # Update lines ~2265, ~2289
git commit -m "chore: Update Docker image pin to sha256:xxx"

# Deploy
ssh qbmgr@server
cd ~/open-webui && git pull origin main
cd mt && ./client-manager.sh
```

### Key Files

| File | Purpose |
|------|---------|
| `mt/start-template.sh` | Template deployment script (update digest line ~94) |
| `mt/client-manager.sh` | Main deployment manager (update digests lines ~2265, ~2289) |
| `mt/VAULT/DOCKER_IMAGE_PIN.md` | Documents current pinned image |
| `.github/workflows/docker.yml` | GitHub Actions for image builds |
| `.github/workflows/docker-build.yaml` | Advanced multi-platform builds |

### Key URLs

- **GitHub Actions:** https://github.com/imagicrafter/open-webui/actions
- **Container Registry:** https://github.com/orgs/imagicrafter/packages
- **Upstream Open WebUI:** https://github.com/open-webui/open-webui

---

## Changelog

### 2025-01-23: Initial Release Management Strategy
- Disabled auto-build on `main` branch
- Enabled auto-build on `release` branch only
- Established two-branch workflow
- Documented release promotion process
- Added comprehensive testing checklist
- Defined rollback procedures

---

## Support

For questions or issues with the release process:
1. Check this guide's [Troubleshooting](#troubleshooting) section
2. Review git history for similar situations
3. Check GitHub Actions build logs
4. Refer to `mt/VAULT/DOCKER_IMAGE_PIN.md` for image history

**Remember:** When in doubt, test on test server first! 🧪
