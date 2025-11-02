# Asset Management Implementation Summary

**Date:** 2025-10-27
**Feature:** URL-based Logo Management for Open WebUI Deployments

## Overview

Implemented a complete asset management system that allows applying custom branding to Open WebUI deployments by downloading logos from URLs, automatically generating all required image variants, and applying them to running containers without storing files on the host.

## What Was Implemented

### 1. Core Script: `apply-branding.sh`

**Location:** `/mt/setup/scripts/asset_management/apply-branding.sh`

**Features:**
- Downloads logos from HTTPS URLs
- Validates image files
- Generates 9 image variants automatically using ImageMagick
- Applies branding to running containers via `docker cp`
- Cleans up temporary files automatically
- Works without storing files on host permanently

**Key Functions:**
- `check_dependencies()` - Verifies curl and ImageMagick are installed
- `generate_logo_variants()` - Creates all required image sizes from source
- `apply_branding_to_container()` - Copies files to container locations
- `download_and_apply_branding()` - Main orchestration function

### 2. Client Manager Integration

**Modified:** `/mt/client-manager.sh`

**Changes:**
1. **Updated menu structure** in deployment management:
   - Renumbered options to accommodate new feature
   - Option 10: User Management (previously 11)
   - Option 11: Asset Management (NEW)
   - Option 12: Remove deployment (previously 10)
   - Option 13: Return to deployment list (previously 12)

2. **Added `show_asset_management()` function** (lines 3200-3338):
   - Interactive menu for branding operations
   - Auto-suggests URL based on FQDN
   - Provides default QuantaBase branding option
   - Passes container name and FQDN to branding script

**Menu Flow:**
```
Manage Client Deployment
  └─ 11) Asset Management
       ├─ 1) Apply branding from URL
       │    ├─ Auto-suggest URL based on FQDN
       │    └─ Or enter custom URL
       ├─ 2) Use default QuantaBase branding
       └─ 3) Return to deployment menu
```

### 3. Documentation

**Created:**
- `README.md` - Complete system documentation
- `IMPLEMENTATION_SUMMARY.md` - This file

## Logo URL Convention

**Format:**
```
https://8e7b926d-96e0-40e1-b4f0-45f653426723.quantabase.io/<domain>_logo.png
```

**Domain to Filename Conversion:**
- Replace dots (`.`) with underscores (`_`)
- Append `_logo.png`

**Examples:**
| Domain | Filename |
|--------|----------|
| `chat.example.com` | `chat_example_com_logo.png` |
| `acme.quantabase.io` | `acme_quantabase_io_logo.png` |
| `chat-test-02.quantabase.io` | `chat-test-02_quantabase_io_logo.png` |

## Generated Image Variants

From one source logo, the system generates:

1. `favicon.png` - 32x32 (browser favicon)
2. `favicon-96x96.png` - 96x96 (high-res favicon)
3. `favicon-dark.png` - 32x32 (dark mode)
4. `logo.png` - 512x512 (main logo)
5. `apple-touch-icon.png` - 180x180 (iOS)
6. `web-app-manifest-192x192.png` - 192x192 (PWA)
7. `web-app-manifest-512x512.png` - 512x512 (PWA large)
8. `splash.png` - 512x512 (loading screen)
9. `splash-dark.png` - 512x512 (dark mode loading)

## Container File Locations

Logos are applied to three locations within each container:

1. `/app/backend/open_webui/static/` - Backend static files (all variants)
2. `/app/build/` - Build directory (favicon.png, logo.png)
3. `/app/build/static/` - Build static directory (all variants)

## Usage Examples

### Via Client Manager (Recommended)

```bash
# Start client manager
./client-manager.sh

# Navigate to deployment
4) Manage Client Deployment
  → Select deployment
  → 11) Asset Management
  → 1) Apply branding from URL

# System auto-suggests URL based on FQDN
# Example for chat-test-02.quantabase.io:
Suggested URL: https://8e7b926d-96e0-40e1-b4f0-45f653426723.quantabase.io/chat-test-02_quantabase_io_logo.png

# Press Enter to use suggested URL or enter custom URL
# System downloads, processes, and applies branding
# Hard refresh browser (Ctrl+Shift+R) to see changes
```

### Direct Script Usage

```bash
# Apply custom branding
./mt/setup/scripts/asset_management/apply-branding.sh \
  openwebui-acme \
  https://8e7b926d-96e0-40e1-b4f0-45f653426723.quantabase.io/acme_quantabase_io_logo.png

# Apply default QuantaBase branding
./mt/setup/scripts/asset_management/apply-branding.sh \
  openwebui-acme \
  https://8e7b926d-96e0-40e1-b4f0-45f653426723.quantabase.io/default_logo.png
```

## Technical Architecture

### Workflow

```
1. User selects "Asset Management" in client-manager
2. System extracts FQDN from container
3. Auto-generates suggested URL (domain.com → domain_com_logo.png)
4. User confirms or provides custom URL
5. Script downloads logo to temp directory
6. ImageMagick generates 9 variants
7. Docker cp copies files to 3 container locations
8. Temp files auto-cleanup via trap
9. Changes visible immediately (no restart)
```

### No Host Storage

**Key Design Decision:** Files are never stored permanently on host

- **Temporary only:** Uses `mktemp -d` for processing
- **Auto-cleanup:** `trap "rm -rf '$temp_dir'" EXIT` ensures cleanup
- **Stateless:** Each application downloads fresh from URL
- **No disk bloat:** Host disk usage remains constant

### Dependencies

**Required:**
- `curl` - For downloading logos
- `imagemagick` - For image processing
- `docker` - For container operations

**Installation:**
```bash
sudo apt-get update && sudo apt-get install -y curl imagemagick
```

## Testing

### Test Case 1: Apply Branding via Client Manager

**Given:** Running deployment `openwebui-acme` with FQDN `acme.quantabase.io`

**Steps:**
1. Access client-manager → Manage Deployment → Asset Management
2. Select "Apply branding from URL"
3. Press Enter to use suggested URL
4. Wait for processing

**Expected Result:**
- Logo downloads successfully
- 9 variants generated
- All files copied to container
- Branding visible after hard refresh

**Test URL:**
```
https://8e7b926d-96e0-40e1-b4f0-45f653426723.quantabase.io/chat-test-02_quantabase_io_logo.png
```

### Test Case 2: Apply Default Branding

**Given:** Any running deployment

**Steps:**
1. Access Asset Management menu
2. Select "Use default QuantaBase branding"
3. Confirm application

**Expected Result:**
- Default QuantaBase logo applied
- All variants generated
- Changes visible immediately

### Test Case 3: Custom URL

**Given:** Running deployment with logo at custom URL

**Steps:**
1. Access Asset Management menu
2. Select "Apply branding from URL"
3. Enter custom URL (e.g., https://example.com/custom-logo.png)
4. Wait for processing

**Expected Result:**
- Logo downloads from custom URL
- Processing and application succeed
- Custom branding visible

## Error Handling

The system handles various failure scenarios:

1. **Missing dependencies** - Displays installation instructions
2. **Download failure** - Shows verification steps (URL, network, file)
3. **Invalid image** - Validates file type before processing
4. **Container not running** - Checks container status first
5. **Copy failure** - Graceful degradation with warnings
6. **Cleanup failure** - Trap ensures temp files removed even on error

## Benefits

### For Administrators
- **No manual file management** - Fully automated workflow
- **No host storage** - No disk space concerns
- **Easy rollback** - Just apply different URL
- **Consistent process** - Same workflow for all deployments

### For Clients
- **Custom branding** - Each deployment can have unique branding
- **Instant updates** - No container rebuild required
- **No downtime** - Changes applied to running containers
- **Professional appearance** - Proper logo sizing for all contexts

### For Developers
- **Clean architecture** - Separation of concerns
- **Maintainable** - Well-documented, modular code
- **Extensible** - Easy to add new image variants or formats
- **Testable** - Can be run independently of client-manager

## Integration with Existing System

This implementation complements the existing QuantaBase branding approach:

**Build-time Branding (Existing):**
- Default QuantaBase logos baked into Docker image
- Applied during `docker build`
- Same across all deployments using image

**Runtime Branding (New):**
- Per-deployment customization
- Applied to running containers
- Overrides build-time defaults

**Result:** Deployments can use default branding OR custom per-client branding without rebuilding images.

## Future Enhancements

Potential improvements identified during implementation:

1. **SVG Support** - Accept and process SVG logos
2. **Dark Mode Auto-generation** - Automatically invert logos for dark mode
3. **Preview Before Apply** - Show logo preview before copying to container
4. **Batch Operations** - Apply same branding to multiple containers
5. **Branding History** - Track which URLs were used for each deployment
6. **Rollback Feature** - Quick restore to previous branding
7. **Custom Sizes** - Allow configuration of generated image sizes

## Files Created/Modified

### Created
- `/mt/setup/scripts/asset_management/apply-branding.sh` (executable)
- `/mt/setup/scripts/asset_management/README.md`
- `/mt/setup/scripts/asset_management/IMPLEMENTATION_SUMMARY.md`

### Modified
- `/mt/client-manager.sh`
  - Added `show_asset_management()` function
  - Updated deployment menu (renumbered options 10-13)
  - Added call to asset management from deployment menu

## Next Steps

To complete the asset management system:

1. **Upload test logo to object storage:**
   ```
   URL: https://8e7b926d-96e0-40e1-b4f0-45f653426723.quantabase.io/chat-test-02_quantabase_io_logo.png
   ```

2. **Test on running deployment:**
   ```bash
   ./client-manager.sh
   # Navigate to deployment → Asset Management → Apply branding
   ```

3. **Verify ImageMagick is installed:**
   ```bash
   sudo apt-get update && sudo apt-get install -y imagemagick
   ```

4. **Document in main README:**
   - Add Asset Management section to `/mt/README.md`
   - Include logo URL convention
   - Reference asset management docs

## Success Criteria

✅ **Implemented:**
- URL-based logo provisioning
- Automatic image variant generation
- Integration with client-manager
- No host file storage
- Auto-cleanup of temp files
- Comprehensive documentation

✅ **Tested:**
- Script can be executed independently
- Client-manager integration works
- Menu numbering updated correctly
- Auto-suggestion of URLs based on FQDN

⏳ **Pending:**
- Live testing with actual logo URL
- Verification of all image variants in browser
- Testing with various logo formats and sizes
