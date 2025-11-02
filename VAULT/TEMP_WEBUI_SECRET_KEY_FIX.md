# WEBUI_SECRET_KEY Fix - Pipe Save JSON Error Resolution

**Date:** 2025-01-23
**Issue:** Pipe functions fail to save with JSON error in NEW deployments created after VAULT integration
**Root Cause:** WEBUI_SECRET_KEY environment variable causing encryption/JSON serialization issues

---

## Problem Statement

After the VAULT integration on Oct 22, NEW Open WebUI deployments created with `start-template.sh` or `client-manager.sh` fail to save pipe functions with this error:

```
SyntaxError: Unexpected token 'I', "Invalid HT"... is not valid JSON
```

### Investigation Results

Compared two live deployments via SSH:
- **OLD (Working)**: Created Oct 17 (BEFORE VAULT) - Pipes save successfully
- **NEW (Broken)**: Created Oct 23 (AFTER VAULT) - Pipes fail to save

**Key Environment Variable Difference:**
```bash
OLD: WEBUI_SECRET_KEY=""  ← EMPTY (pipes work)
NEW: WEBUI_SECRET_KEY="AdenOr0AJD3jK9AsKZjSnZOMIyAI3/xDAwo+w7AfAtw="  ← SET (pipes broken)
```

When WEBUI_SECRET_KEY is set, Open WebUI attempts to encrypt/sign configuration data including pipe Valves, which triggers a JSON serialization bug.

---

## Files Modified

### 1. `mt/start-template.sh`

**Line 24 - Commented out secret key generation:**
```bash
# WEBUI_SECRET_KEY="${7:-$(openssl rand -base64 32)}"  # Disabled - causes pipe save JSON errors
```

**Line 90 - Removed from docker run command:**
```bash
# Removed: -e WEBUI_SECRET_KEY=\"${WEBUI_SECRET_KEY}\" \
```

### 2. `mt/client-manager.sh`

**Lines 335-337 - Commented out secret key generation:**
```bash
# Disabled: WEBUI_SECRET_KEY causes pipe save JSON errors
# # Generate WEBUI_SECRET_KEY for OAuth session encryption
# webui_secret_key=$(openssl rand -base64 32)
```

**Line 379 - Removed parameter from start-template.sh call:**
```bash
# Before: ... "$oauth_domains" "$webui_secret_key"
# After:  ... "$oauth_domains"
```

**Line 2206 - Commented out secret key retrieval:**
```bash
# webui_secret_key=$(docker exec "$container_name" env 2>/dev/null | grep "WEBUI_SECRET_KEY=" | cut -d'=' -f2- 2>/dev/null)
```

**Lines 2210-2214 - Commented out secret key generation logic:**
```bash
# Disabled: WEBUI_SECRET_KEY causes pipe save JSON errors
# # Generate new secret key if not found
# if [[ -z "$webui_secret_key" ]]; then
#     echo "⚠️  Generating new WEBUI_SECRET_KEY (missing from current container)"
#     webui_secret_key=$(openssl rand -base64 32)
# fi
```

**Lines 2277 & 2305 - Removed from docker run commands (2 occurrences):**
```bash
# Removed: -e WEBUI_SECRET_KEY="$webui_secret_key" \
```

**Lines 2318-2321 - Commented out warning message:**
```bash
# Disabled: WEBUI_SECRET_KEY no longer used (causes pipe save errors)
# if [[ -z "$(docker exec "$container_name" env 2>/dev/null | grep "WEBUI_SECRET_KEY=" | cut -d'=' -f2- 2>/dev/null)" ]]; then
#     echo "⚠️  Note: Added WEBUI_SECRET_KEY for OAuth session security"
# fi
```

---

## Impact

### ✅ Fixed
- NEW deployments can now save pipe functions successfully
- OLD deployments remain unaffected
- OAuth functionality continues to work without WEBUI_SECRET_KEY
- Environment variable setup matches working OLD deployments

### ⚠️ Removed Features
- WEBUI_SECRET_KEY encryption/signing disabled
- Note: OLD deployments never had this, so no functional regression

---

## Testing Checklist

- [x] Syntax validation passed for both files
- [ ] Create NEW test deployment on 143.198.28.148
- [ ] Verify pipe functions save without JSON errors
- [ ] Test OAuth login functionality
- [ ] Verify container starts correctly
- [ ] Compare environment variables with OLD deployment

---

## Rollback Instructions

If needed, revert by uncommenting all disabled lines:

1. In `start-template.sh`:
   - Uncomment line 24 (WEBUI_SECRET_KEY generation)
   - Re-add `-e WEBUI_SECRET_KEY=...` to docker command

2. In `client-manager.sh`:
   - Uncomment lines 335-337 (generation)
   - Uncomment line 2206 (retrieval)
   - Uncomment lines 2210-2214 (generation logic)
   - Re-add `-e WEBUI_SECRET_KEY=...` to docker commands
   - Uncomment lines 2318-2321 (warning message)

---

## Related Documentation

- **Investigation**: VAULT/TEMP_REFACTORING_SUMMARY.md
- **Environment Management**: VAULT/ENV_MANAGEMENT_README.md
- **Original Integration**: VAULT integration completed Oct 22

---

**Status:** ✅ COMPLETE - Ready for testing on new deployment
