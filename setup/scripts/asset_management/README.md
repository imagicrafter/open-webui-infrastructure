# Asset Management System

Automated branding management for Open WebUI deployments. Downloads logos from URLs, generates all required image variants, and applies them to running containers without storing files on the host.

## Features

- **URL-based logo provisioning** - No local file storage required
- **Automatic image resizing** - Generates all required logo variants from a single source image
- **On-the-fly processing** - Downloads, processes, and applies in one operation
- **No container restart required** - Changes visible immediately (hard refresh browser)
- **Temporary storage only** - All files cleaned up after application

## Requirements

- **curl** - For downloading logos from URLs
- **ImageMagick** - For image processing and resizing
- **Docker** - For copying files to containers

### Install Dependencies

```bash
sudo apt-get update && sudo apt-get install -y curl imagemagick
```

## Logo URL Format

Logos should be accessible via HTTPS URL. The recommended format is:

```
https://8e7b926d-96e0-40e1-b4f0-45f653426723.quantabase.io/<domain>_logo.png
```

**Domain to filename conversion:**
- Replace dots (`.`) with underscores (`_`)
- Append `_logo.png`

**Examples:**
- Domain: `chat.example.com` → Filename: `chat_example_com_logo.png`
- Domain: `acme.quantabase.io` → Filename: `acme_quantabase_io_logo.png`

## Optimal Source Logo Specifications

### **Recommended Size & Format**

| Property | Recommendation | Notes |
|----------|----------------|-------|
| **Minimum Size** | 512x512 pixels | Smaller may lose quality when scaled |
| **Recommended Size** | 800x800 to 1024x1024 | Best balance of quality and processing speed |
| **Maximum Size** | 2048x2048 pixels | Larger = slower processing, diminishing returns |
| **Format** | PNG with transparent background | Maximum flexibility for all variants |
| **Alternative Format** | PNG with solid background | White/black circle or square |
| **Acceptable Format** | JPG | No transparency support |
| **Aspect Ratio** | Square (1:1) | e.g., 1000x1000 pixels |
| **Near-Square** | Within 10% difference | e.g., 1000x950 (will be centered) |
| **Color Depth** | 24-bit RGB or 32-bit RGBA | RGBA for transparency |
| **Compression** | PNG lossless compression | File size not critical |

### **Design Best Practices**

**✅ DO:**
- Use bold, simple designs that work at small sizes
- Use high contrast (black on white, white on black)
- Keep important elements centered
- Test visibility at 32x32 pixels
- Use solid colors or simple gradients
- Design with 2-3 colors maximum for clarity

**❌ DON'T:**
- Use fine serif fonts (they blur at small sizes like 32x32)
- Use thin lines (<3px at source resolution)
- Use complex gradients or subtle color variations
- Include small text or highly detailed illustrations
- Use very light colors on white backgrounds
- Use photos with fine details (they pixelate when scaled down)

### **Example Specifications**

**Simple Icon/Logo:**
```
Format: PNG with transparent background
Size: 1024x1024 pixels
Colors: 2-3 solid colors, high contrast
Design: Bold, simple shapes without fine details
```

**Photo-based Logo:**
```
Format: PNG with colored background circle
Size: 800x800 pixels
Colors: Full color photo with high contrast
Background: Solid color circle or square
```

**Quality Tip:** The system uses high-quality Lanczos filtering to generate all 11 required variants (16x16 to 512x512) from your source image. Starting with a high-quality source ensures the best results across all sizes.

## Generated Image Variants

From a single source logo, the system automatically generates:

| File | Size | Purpose |
|------|------|---------|
| `favicon.png` | 32x32 | Browser favicon (PNG) |
| `favicon-96x96.png` | 96x96 | High-res favicon |
| `favicon-dark.png` | 32x32 | Dark mode favicon |
| `favicon.ico` | 16x16, 32x32 | Browser favicon (ICO format) |
| `favicon.svg` | Vector | Browser favicon (SVG format) |
| `logo.png` | 512x512 | Main application logo |
| `apple-touch-icon.png` | 180x180 | iOS home screen icon |
| `web-app-manifest-192x192.png` | 192x192 | PWA manifest icon |
| `web-app-manifest-512x512.png` | 512x512 | PWA manifest icon (large) |
| `splash.png` | 512x512 | Loading screen logo |
| `splash-dark.png` | 512x512 | Dark mode loading screen |

**Total: 11 variants** automatically generated from one source image.

## Container File Locations

Logos are copied to multiple locations within the container:

```
/app/backend/open_webui/static/
├── favicon.png
├── favicon-96x96.png
├── favicon-dark.png
├── favicon.ico
├── favicon.svg
├── logo.png
├── apple-touch-icon.png
├── web-app-manifest-192x192.png
├── web-app-manifest-512x512.png
└── swagger-ui/
    └── favicon.png

/app/build/
├── favicon.png
└── logo.png

/app/build/static/
├── favicon.png
├── favicon-96x96.png
├── favicon-dark.png
├── favicon.ico
├── favicon.svg
├── logo.png
├── apple-touch-icon.png
├── web-app-manifest-192x192.png
├── web-app-manifest-512x512.png
├── splash.png
└── splash-dark.png
```

## Usage

### Via Client Manager (Recommended)

1. **Access deployment menu:**
   ```bash
   ./client-manager.sh
   # Select "4) Manage Client Deployment"
   # Choose your deployment
   # Select "11) Asset Management"
   ```

2. **Apply custom logo branding:**
   - Select option 1: "Apply logo branding from URL"
   - Enter logo URL or press Enter to use auto-suggested URL
   - Wait for download and processing
   - Container will automatically restart (~15 seconds)
   - Hard refresh browser to see changes (Ctrl+Shift+R)

3. **Apply default QuantaBase logo:**
   - Select option 2: "Use default QuantaBase logo"
   - Confirm application
   - Container will automatically restart (~15 seconds)
   - Hard refresh browser to see changes

4. **Update deployment name:**
   - Select option 3: "Update deployment name (WEBUI_NAME)"
   - Enter new name (e.g., "ACME Corp", "Client Portal")
   - Confirm container recreation
   - Container will be recreated with new name (all data preserved)
   - Hard refresh browser to see new name

### Direct Script Usage

```bash
# Apply branding from URL
./mt/setup/scripts/asset_management/apply-branding.sh CONTAINER_NAME LOGO_URL

# Example
./mt/setup/scripts/asset_management/apply-branding.sh \
  openwebui-acme \
  https://8e7b926d-96e0-40e1-b4f0-45f653426723.quantabase.io/acme_quantabase_io_logo.png
```

## How It Works

1. **Download:** Fetches logo from provided URL using `curl`
2. **Validate:** Verifies downloaded file is a valid image
3. **Generate:** Creates all required image variants using ImageMagick
4. **Apply:** Copies all variants to container using `docker cp`
5. **Cleanup:** Removes temporary files (automatic via trap)

## Workflow Diagram

```
┌─────────────────┐
│  Logo URL       │
│  (Object Store) │
└────────┬────────┘
         │
         │ curl download
         ▼
┌─────────────────┐
│  Temp Directory │
│  /tmp/XXXXX     │
└────────┬────────┘
         │
         │ ImageMagick convert
         ▼
┌─────────────────┐
│  9 Image        │
│  Variants       │
└────────┬────────┘
         │
         │ docker cp
         ▼
┌─────────────────┐
│  Container      │
│  /app/...       │
└────────┬────────┘
         │
         │ trap cleanup
         ▼
┌─────────────────┐
│  Temp Files     │
│  Deleted        │
└─────────────────┘
```

## Best Practices

### Logo File Requirements

- **Format:** PNG recommended (JPG also supported)
- **Size:** At least 512x512 pixels (higher resolution is better)
- **Background:** Transparent PNG for best results
- **Aspect Ratio:** Square (1:1) recommended

### Deployment Strategy

1. **Upload logo to object storage first**
   - Use naming convention: `<domain_with_underscores>_logo.png`
   - Verify URL is publicly accessible

2. **Test with one deployment**
   - Apply branding to a test container
   - Verify all logos appear correctly
   - Check both light and dark modes

3. **Roll out to production**
   - Apply to production containers
   - Document which URL was used

## Configuration of Cloudflare Worker Proxy to Supabase Storage

### Overview
Set up a Cloudflare Worker to proxy requests from a UUID subdomain to Supabase storage, allowing clean URLs like `8e7b926d-96e0-40e1-b4f0-45f653426723.quantabase.io/image01.png` to serve files from Supabase.

### Steps to Reproduce

#### 1. Create Worker
- Go to **Workers & Pages** → **Create Worker**
- Deploy **"Hello World"** template
- Click **"Edit code"** and replace with:

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url);
    const supabaseUrl = `https://vpbvsrworjriccgszned.supabase.co/storage/v1/object/public/open-webui-assets${url.pathname}`;
    const response = await fetch(supabaseUrl);
    return new Response(response.body, {
      status: response.status,
      headers: response.headers,
    });
  },
};
```

- Click **"Save and Deploy"**

#### 2. Add DNS Record
- Go to your domain (e.g., quantabase.io) → **DNS** → **Records**
- Click **"Add record"**
- Configure:
  - **Type:** A
  - **Name:** `8e7b926d-96e0-40e1-b4f0-45f653426723` (your UUID)
  - **IPv4 address:** `192.0.2.1`
  - **Proxy status:** Proxied (orange cloud) ✓
  - **TTL:** Auto
- Click **Save**

#### 3. Add Worker Route
- Go to **Workers Routes** → **Add route**
- Configure:
  - **Route:** `8e7b926d-96e0-40e1-b4f0-45f653426723.quantabase.io/*`
  - **Service:** Select your Worker
  - **Environment:** Production
- Click **Save**

### Result
Files are now accessible via the clean UUID subdomain. Example:
- `https://8e7b926d-96e0-40e1-b4f0-45f653426723.quantabase.io/image01.png`

This will fetch and serve the file from:
- `https://vpbvsrworjriccgszned.supabase.co/storage/v1/object/public/open-webui-assets/image01.png`



## Troubleshooting

### "Failed to download logo from URL"

**Causes:**
- URL is incorrect or inaccessible
- Network connectivity issues
- File doesn't exist at URL

**Solutions:**
1. Verify URL in browser
2. Check network connectivity: `curl -I <URL>`
3. Ensure object storage is publicly accessible

### "Failed to generate logo variants"

**Causes:**
- ImageMagick not installed
- Downloaded file is not a valid image
- Insufficient disk space

**Solutions:**
1. Install ImageMagick: `sudo apt-get install imagemagick`
2. Verify file is valid: `file /tmp/downloaded_file.png`
3. Check disk space: `df -h /tmp`

### "Container is not running"

**Causes:**
- Container is stopped
- Container name is incorrect

**Solutions:**
1. Check container status: `docker ps -a | grep CONTAINER_NAME`
2. Start container: `docker start CONTAINER_NAME`
3. Verify container name matches exactly

### "Changes not visible in browser"

**Causes:**
- Browser cache holding old logos
- Hard refresh not performed

**Solutions:**
1. Hard refresh browser:
   - Chrome/Firefox: Ctrl+Shift+R (Cmd+Shift+R on Mac)
   - Safari: Cmd+Option+R
2. Clear browser cache completely
3. Try incognito/private mode

## Technical Details

### Temporary File Management

The script uses `mktemp -d` to create a temporary directory with a random name:
```bash
temp_dir=$(mktemp -d)  # Creates /tmp/tmp.XXXXXXXXXX
trap "rm -rf '$temp_dir'" EXIT  # Ensures cleanup even if script fails
```

### ImageMagick Commands

All image conversions use ImageMagick's `convert` command:
```bash
convert source.png -resize 32x32 favicon.png
convert source.png -resize 512x512 logo.png
```

### Docker Copy Operations

Files are copied using `docker cp`:
```bash
docker cp /tmp/tmpXXX/favicon.png container:/app/backend/open_webui/static/favicon.png
```

## Future Enhancements

Potential improvements for future versions:

- [ ] Support for SVG logo format
- [ ] Dark mode variant generation (automatic inversion)
- [ ] Favicon .ico generation for older browsers
- [ ] Logo preview before application
- [ ] Batch apply to multiple containers
- [ ] Rollback to previous branding
- [ ] Custom image sizes configuration

## Integration with QuantaBase Branding

This system is designed to work seamlessly with QuantaBase's current branding approach:

1. **Build-time branding** (existing): Logos baked into Docker image
2. **Runtime branding** (this system): Per-deployment logo customization

The runtime approach allows:
- Client-specific branding without custom Docker images
- Easy logo updates without rebuilding containers
- Rapid deployment of client-branded instances

## See Also

- [Client Manager Documentation](../../README.md) - Main multi-tenant system
- [Quick Setup Guide](../../setup/README.md) - Server provisioning
- [Database Migration](../../DB_MIGRATION/README.md) - SQLite to PostgreSQL migration
