#!/bin/bash

# Dynamic Text Logo Generator for Open WebUI Deployments
# Generates custom logos from 1-2 letter text with font selection

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

check_dependencies() {
    local missing_deps=()

    # Check for ImageMagick (convert command)
    if ! command -v convert &> /dev/null; then
        missing_deps+=("imagemagick")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${RED}❌ Missing required dependencies:${NC}"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        echo
        echo "Install with:"
        echo "  sudo apt-get update && sudo apt-get install -y ${missing_deps[*]}"
        return 1
    fi

    return 0
}

generate_text_logo_variants() {
    local text="$1"
    local font="$2"
    local bg_style="$3"
    local bg_color="$4"
    local text_color="$5"
    local temp_dir="$6"

    echo -e "${BLUE}Generating text logo variants for: '$text'${NC}"
    echo -e "${BLUE}Font: $font${NC}"
    echo -e "${BLUE}Background: $bg_style${NC}"
    echo

    # Function to generate logo at specific size
    generate_at_size() {
        local size=$1
        local output_file=$2
        local pointsize=$3

        # Build ImageMagick command based on background style
        local base_cmd="convert -size ${size}x${size} xc:none"

        # Add background based on style
        case "$bg_style" in
            "circle")
                local radius=$((size / 2))
                base_cmd="$base_cmd -fill '$bg_color' -draw 'circle $radius,$radius $radius,5'"
                ;;
            "rounded-square")
                local corner_radius=$((size / 8))
                base_cmd="$base_cmd -fill '$bg_color' -draw 'roundRectangle 0,0 $size,$size $corner_radius,$corner_radius'"
                ;;
            "square")
                base_cmd="$base_cmd -fill '$bg_color' -draw 'rectangle 0,0 $size,$size'"
                ;;
            "none")
                # Transparent background, no fill needed
                ;;
        esac

        # Add text
        base_cmd="$base_cmd -fill '$text_color' -font '$font' -pointsize $pointsize -gravity center -annotate +0+0 '$text'"

        # Execute command
        if eval "$base_cmd '$output_file'" 2>/dev/null; then
            return 0
        else
            return 1
        fi
    }

    # Generate favicon.png (96x96) - for UI elements
    if generate_at_size 96 "$temp_dir/favicon.png" 56; then
        echo -e "${GREEN}✓${NC} favicon.png (96x96)"
    else
        echo -e "${RED}✗${NC} Failed to generate favicon.png"
        return 1
    fi

    # Generate favicon-96x96.png
    if generate_at_size 96 "$temp_dir/favicon-96x96.png" 56; then
        echo -e "${GREEN}✓${NC} favicon-96x96.png (96x96)"
    else
        echo -e "${RED}✗${NC} Failed to generate favicon-96x96.png"
        return 1
    fi

    # Generate favicon-dark.png (same as favicon for now)
    if generate_at_size 96 "$temp_dir/favicon-dark.png" 56; then
        echo -e "${GREEN}✓${NC} favicon-dark.png (96x96)"
    else
        echo -e "${RED}✗${NC} Failed to generate favicon-dark.png"
        return 1
    fi

    # Generate logo.png (512x512) - high quality for large displays
    if generate_at_size 512 "$temp_dir/logo.png" 300; then
        echo -e "${GREEN}✓${NC} logo.png (512x512)"
    else
        echo -e "${RED}✗${NC} Failed to generate logo.png"
        return 1
    fi

    # Generate apple-touch-icon.png (180x180)
    if generate_at_size 180 "$temp_dir/apple-touch-icon.png" 105; then
        echo -e "${GREEN}✓${NC} apple-touch-icon.png (180x180)"
    else
        echo -e "${RED}✗${NC} Failed to generate apple-touch-icon.png"
        return 1
    fi

    # Generate web-app-manifest-192x192.png
    if generate_at_size 192 "$temp_dir/web-app-manifest-192x192.png" 112; then
        echo -e "${GREEN}✓${NC} web-app-manifest-192x192.png (192x192)"
    else
        echo -e "${RED}✗${NC} Failed to generate web-app-manifest-192x192.png"
        return 1
    fi

    # Generate web-app-manifest-512x512.png
    if generate_at_size 512 "$temp_dir/web-app-manifest-512x512.png" 300; then
        echo -e "${GREEN}✓${NC} web-app-manifest-512x512.png (512x512)"
    else
        echo -e "${RED}✗${NC} Failed to generate web-app-manifest-512x512.png"
        return 1
    fi

    # Generate splash.png (512x512)
    if generate_at_size 512 "$temp_dir/splash.png" 300; then
        echo -e "${GREEN}✓${NC} splash.png (512x512)"
    else
        echo -e "${RED}✗${NC} Failed to generate splash.png"
        return 1
    fi

    # Generate splash-dark.png (same as splash for now)
    if generate_at_size 512 "$temp_dir/splash-dark.png" 300; then
        echo -e "${GREEN}✓${NC} splash-dark.png (512x512)"
    else
        echo -e "${RED}✗${NC} Failed to generate splash-dark.png"
        return 1
    fi

    # Generate favicon.ico (16x16 and 32x32 multi-resolution)
    if generate_at_size 32 "$temp_dir/favicon-32.png" 18 && \
       generate_at_size 16 "$temp_dir/favicon-16.png" 9 && \
       convert "$temp_dir/favicon-16.png" "$temp_dir/favicon-32.png" "$temp_dir/favicon.ico" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} favicon.ico (16x16, 32x32)"
        rm -f "$temp_dir/favicon-16.png" "$temp_dir/favicon-32.png"
    else
        echo -e "${RED}✗${NC} Failed to generate favicon.ico"
        return 1
    fi

    # Generate favicon.svg (SVG with text)
    cat > "$temp_dir/favicon.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">
  <defs>
    <style>
      text { font-family: '$font'; font-size: 56px; fill: $text_color; text-anchor: middle; dominant-baseline: central; }
    </style>
  </defs>
EOF

    # Add background based on style
    case "$bg_style" in
        "circle")
            echo "  <circle cx=\"48\" cy=\"48\" r=\"48\" fill=\"$bg_color\"/>" >> "$temp_dir/favicon.svg"
            ;;
        "rounded-square")
            echo "  <rect x=\"0\" y=\"0\" width=\"96\" height=\"96\" rx=\"12\" fill=\"$bg_color\"/>" >> "$temp_dir/favicon.svg"
            ;;
        "square")
            echo "  <rect x=\"0\" y=\"0\" width=\"96\" height=\"96\" fill=\"$bg_color\"/>" >> "$temp_dir/favicon.svg"
            ;;
    esac

    # Add text
    echo "  <text x=\"48\" y=\"48\">$text</text>" >> "$temp_dir/favicon.svg"
    echo "</svg>" >> "$temp_dir/favicon.svg"

    echo -e "${GREEN}✓${NC} favicon.svg (SVG)"

    return 0
}

apply_branding_to_container() {
    local container_name="$1"
    local temp_dir="$2"

    echo
    echo -e "${BLUE}Applying branding to container: $container_name${NC}"
    echo

    # Check if container exists and is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo -e "${RED}❌ Container '$container_name' is not running${NC}"
        return 1
    fi

    # Extract client_id from container name
    local client_id="${container_name#openwebui-}"
    local client_dir="/opt/openwebui/${client_id}"

    # Check if using Phase 1 bind mounts
    local has_bind_mount=false
    if docker inspect "$container_name" --format '{{range .Mounts}}{{if eq .Destination "/app/backend/open_webui/static"}}true{{end}}{{end}}' | grep -q "true"; then
        has_bind_mount=true
    fi

    if [ "$has_bind_mount" = true ]; then
        # Phase 1 approach: Save to branding directory, then use injection script
        echo -e "${BLUE}ℹ${NC}  Container uses Phase 1 bind mounts"
        echo -e "${BLUE}ℹ${NC}  Saving to branding directory: ${client_dir}/branding/"
        echo

        # Create branding directory if it doesn't exist
        mkdir -p "${client_dir}/branding"

        # Ensure proper ownership (fix permission issues if directory was created by root)
        if [ ! -w "${client_dir}/branding" ]; then
            echo -e "${YELLOW}⚠${NC}  Branding directory not writable by $(whoami)"
            echo -e "${BLUE}ℹ${NC}  Attempting to fix ownership..."

            # Try to fix with sudo (will fail silently if no passwordless sudo)
            if sudo -n chown -R $(whoami):$(whoami) "${client_dir}/branding" 2>/dev/null; then
                echo -e "${GREEN}✓${NC} Permissions fixed"
            else
                # If sudo fails, provide clear instructions
                echo -e "${RED}❌ Cannot fix permissions automatically${NC}"
                echo -e "${BLUE}ℹ${NC}  Please run this command manually:"
                echo -e "${BLUE}     sudo chown -R qbmgr:qbmgr ${client_dir}/branding${NC}"
                echo -e "${YELLOW}⚠${NC}  Or run the asset management menu with sudo"
                return 1
            fi
        fi

        local files_to_copy=(
            "favicon.png"
            "favicon-96x96.png"
            "favicon-dark.png"
            "favicon.ico"
            "favicon.svg"
            "logo.png"
            "apple-touch-icon.png"
            "web-app-manifest-192x192.png"
            "web-app-manifest-512x512.png"
            "splash.png"
            "splash-dark.png"
        )

        local success_count=0
        local total_count=0

        for file in "${files_to_copy[@]}"; do
            if [ -f "$temp_dir/$file" ]; then
                ((total_count++))
                # Attempt copy with error capture
                local copy_error=$(cp "$temp_dir/$file" "${client_dir}/branding/$file" 2>&1)
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✓${NC} ${client_dir}/branding/$file"
                    ((success_count++))
                else
                    echo -e "${YELLOW}⚠${NC} Failed to copy $file to branding directory"
                    echo -e "${RED}   Error: $copy_error${NC}"
                    # Try with sudo if permission denied
                    if echo "$copy_error" | grep -qi "permission denied"; then
                        echo -e "${BLUE}   Retrying with sudo...${NC}"
                        if sudo cp "$temp_dir/$file" "${client_dir}/branding/$file" 2>/dev/null; then
                            echo -e "${GREEN}✓${NC} ${client_dir}/branding/$file (with sudo)"
                            ((success_count++))
                        fi
                    fi
                fi
            fi
        done

        echo
        echo -e "${GREEN}✅ Branding saved: $success_count/$total_count files${NC}"

        # Verify files were actually saved
        echo -e "${BLUE}ℹ${NC}  Verifying branding directory:"
        ls -lah "${client_dir}/branding/" | grep -E '\.(png|svg|ico)$' || echo -e "${RED}   No branding files found!${NC}"
        echo

        # Use injection script to apply after container is healthy
        local inject_script="$SCRIPT_DIR/../../lib/inject-branding-post-startup.sh"
        if [ -f "$inject_script" ]; then
            echo -e "${BLUE}Running post-startup injection...${NC}"
            echo
            if bash "$inject_script" "$container_name" "$client_id" "${client_dir}/branding"; then
                echo
                echo -e "${GREEN}✅ Branding applied successfully!${NC}"
                echo -e "${BLUE}ℹ${NC}  Branding persists until next container restart"
                echo -e "${BLUE}ℹ${NC}  Hard refresh browser (Ctrl+Shift+R) to see changes"
            else
                echo
                echo -e "${YELLOW}⚠${NC} Injection script failed"
                echo -e "${BLUE}ℹ${NC}  Run manually:"
                echo -e "${BLUE}    $inject_script $container_name $client_id ${client_dir}/branding${NC}"
            fi
        else
            echo -e "${YELLOW}⚠${NC} Injection script not found: $inject_script"
            echo -e "${BLUE}ℹ${NC}  Branding saved but not applied to running container"
            echo -e "${BLUE}ℹ${NC}  Restart container to apply: docker restart $container_name"
        fi

    else
        # Legacy approach: docker cp directly to container
        echo -e "${YELLOW}⚠${NC}  Container uses legacy volume mounts"
        echo -e "${YELLOW}⚠${NC}  Branding will be lost on container recreation"
        echo

        local files_to_copy=(
            "favicon.png"
            "favicon-96x96.png"
            "favicon-dark.png"
            "favicon.ico"
            "favicon.svg"
            "logo.png"
            "apple-touch-icon.png"
            "web-app-manifest-192x192.png"
            "web-app-manifest-512x512.png"
            "splash.png"
            "splash-dark.png"
        )

        local backend_static="/app/backend/open_webui/static"
        local build_dir="/app/build"
        local build_static="/app/build/static"
        local success_count=0
        local total_count=0

        # Copy to backend static directory
        echo -e "${YELLOW}Copying to backend static directory...${NC}"
        for file in "${files_to_copy[@]}"; do
            if [ -f "$temp_dir/$file" ]; then
                ((total_count++))
                if docker cp "$temp_dir/$file" "$container_name:$backend_static/$file" 2>/dev/null; then
                    echo -e "${GREEN}✓${NC} $backend_static/$file"
                    ((success_count++))
                else
                    echo -e "${YELLOW}⚠${NC} Failed to copy $file to backend static"
                fi
            fi
        done

        # Copy to build directory
        echo
        echo -e "${YELLOW}Copying to build directory...${NC}"
        for file in favicon.png logo.png; do
            if [ -f "$temp_dir/$file" ]; then
                ((total_count++))
                if docker cp "$temp_dir/$file" "$container_name:$build_dir/$file" 2>/dev/null; then
                    echo -e "${GREEN}✓${NC} $build_dir/$file"
                    ((success_count++))
                else
                    echo -e "${YELLOW}⚠${NC} Failed to copy $file to build"
                fi
            fi
        done

        # Copy to build/static directory
        echo
        echo -e "${YELLOW}Copying to build/static directory...${NC}"
        for file in "${files_to_copy[@]}"; do
            if [ -f "$temp_dir/$file" ]; then
                ((total_count++))
                if docker cp "$temp_dir/$file" "$container_name:$build_static/$file" 2>/dev/null; then
                    echo -e "${GREEN}✓${NC} $build_static/$file"
                    ((success_count++))
                else
                    echo -e "${YELLOW}⚠${NC} Failed to copy $file to build/static"
                fi
            fi
        done

        # Copy favicon to swagger-ui
        if [ -f "$temp_dir/favicon.png" ]; then
            ((total_count++))
            if docker cp "$temp_dir/favicon.png" "$container_name:$backend_static/swagger-ui/favicon.png" 2>/dev/null; then
                echo -e "${GREEN}✓${NC} $backend_static/swagger-ui/favicon.png"
                ((success_count++))
            else
                echo -e "${YELLOW}⚠${NC} Failed to copy to swagger-ui"
            fi
        fi

        echo
        echo -e "${GREEN}✅ Branding applied: $success_count/$total_count files${NC}"
        echo

        # Restart container
        echo -e "${BLUE}Restarting container...${NC}"
        if docker restart "$container_name" >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Container restarted"
            echo
            echo -e "${BLUE}ℹ${NC}  Hard refresh browser (Ctrl+Shift+R) to see changes"
        else
            echo -e "${YELLOW}⚠${NC} Failed to restart container"
        fi
    fi

    echo

    return 0
}

generate_and_apply_text_logo() {
    local container_name="$1"
    local text="$2"
    local font="$3"
    local bg_style="$4"
    local bg_color="$5"
    local text_color="$6"

    # Check dependencies first
    if ! check_dependencies; then
        return 1
    fi

    # Create temporary directory
    local temp_dir=$(mktemp -d)
    trap "rm -rf '$temp_dir'" EXIT

    echo
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      Dynamic Text Logo Generator       ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo
    echo "Container: $container_name"
    echo "Text: $text"
    echo "Font: $font"
    echo "Background: $bg_style"
    echo "Background Color: $bg_color"
    echo "Text Color: $text_color"
    echo

    # Generate all logo variants
    if ! generate_text_logo_variants "$text" "$font" "$bg_style" "$bg_color" "$text_color" "$temp_dir"; then
        echo -e "${RED}❌ Failed to generate logo variants${NC}"
        return 1
    fi

    echo

    # Apply branding to container
    if ! apply_branding_to_container "$container_name" "$temp_dir"; then
        return 1
    fi

    # Cleanup happens automatically via trap
    return 0
}

# If script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -ne 6 ]; then
        echo "Usage: $0 CONTAINER_NAME TEXT FONT BG_STYLE BG_COLOR TEXT_COLOR"
        echo
        echo "Example:"
        echo "  $0 openwebui-acme 'AC' 'Helvetica-Bold' 'circle' '#FFFFFF' '#000000'"
        echo
        echo "Background styles: circle, rounded-square, square, none"
        exit 1
    fi

    generate_and_apply_text_logo "$1" "$2" "$3" "$4" "$5" "$6"
fi
