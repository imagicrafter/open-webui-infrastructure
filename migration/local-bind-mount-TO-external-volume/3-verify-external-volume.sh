#!/usr/bin/env bash
#
# 3-verify-external-volume.sh
# Verifies that Open WebUI migration to external volume was successful
#
# Usage: bash 3-verify-external-volume.sh
#

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
OPENWEBUI_BASE=${OPENWEBUI_BASE:-/opt/openwebui}
MOUNT_POINT=${MOUNT_POINT:-/mnt/openwebui-volume}
EXTERNAL_DATA_DIR="$MOUNT_POINT/openwebui"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNING=0

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Verify External Volume Migration                     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo

# Test helper functions
test_passed() {
    echo -e "${GREEN}✓${NC} PASS: $1"
    ((TESTS_PASSED++))
}

test_failed() {
    echo -e "${RED}✗${NC} FAIL: $1"
    ((TESTS_FAILED++))
}

test_warning() {
    echo -e "${YELLOW}⚠${NC} WARN: $1"
    ((TESTS_WARNING++))
}

# Test 1: Verify external volume is mounted
test_volume_mounted() {
    echo -e "${CYAN}[Test 1] External Volume Mount${NC}"

    if mountpoint -q "$MOUNT_POINT"; then
        test_passed "External volume is mounted at $MOUNT_POINT"

        # Show mount details
        local mount_info=$(df -h "$MOUNT_POINT" | tail -1)
        echo "         $mount_info"
    else
        test_failed "External volume is NOT mounted at $MOUNT_POINT"
    fi

    echo
}

# Test 2: Verify symlink exists and points correctly
test_symlink() {
    echo -e "${CYAN}[Test 2] Symlink Configuration${NC}"

    if [ -L "$OPENWEBUI_BASE" ]; then
        local link_target=$(readlink -f "$OPENWEBUI_BASE")

        if [ "$link_target" = "$EXTERNAL_DATA_DIR" ]; then
            test_passed "Symlink points to correct location"
            echo "         $OPENWEBUI_BASE → $EXTERNAL_DATA_DIR"
        else
            test_failed "Symlink points to wrong location: $link_target"
        fi
    else
        test_failed "No symlink found at $OPENWEBUI_BASE"
    fi

    echo
}

# Test 3: Verify data directories exist
test_data_directories() {
    echo -e "${CYAN}[Test 3] Data Directory Structure${NC}"

    if [ ! -d "$EXTERNAL_DATA_DIR" ]; then
        test_failed "External data directory does not exist: $EXTERNAL_DATA_DIR"
        echo
        return
    fi

    # Count client directories
    local client_dirs=($(find "$EXTERNAL_DATA_DIR" -maxdepth 1 -type d -name "*" ! -name "openwebui" | sort))
    local client_count=$((${#client_dirs[@]}))

    if [ $client_count -gt 0 ]; then
        test_passed "Found $client_count client data director(ies)"

        # Check each client directory structure
        for client_dir in "${client_dirs[@]}"; do
            local client_name=$(basename "$client_dir")
            local has_data=false
            local has_branding=false
            local has_static=false

            [ -d "$client_dir/data" ] && has_data=true
            [ -d "$client_dir/branding" ] && has_branding=true
            [ -d "$client_dir/static" ] && has_static=true

            echo "         • $client_name"
            echo "           - data:     $([ "$has_data" = true ] && echo "✓" || echo "✗")"
            echo "           - branding: $([ "$has_branding" = true ] && echo "✓" || echo "✗")"
            echo "           - static:   $([ "$has_static" = true ] && echo "✓" || echo "✗")"
        done
    else
        test_warning "No client directories found (this might be okay for fresh installs)"
    fi

    echo
}

# Test 4: Verify containers are running
test_containers_running() {
    echo -e "${CYAN}[Test 4] Container Status${NC}"

    local containers=($(docker ps -a --filter "name=^openwebui-" --format "{{.Names}}" | sort))

    if [ ${#containers[@]} -eq 0 ]; then
        test_warning "No Open WebUI containers found"
        echo
        return
    fi

    local running_count=0
    local healthy_count=0

    for container in "${containers[@]}"; do
        local status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
        local health=$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")

        if [ "$status" = "running" ]; then
            ((running_count++))

            if [ "$health" = "healthy" ] || [ "$health" = "none" ]; then
                ((healthy_count++))
                echo "         ✓ $container ($status, $health)"
            else
                echo "         ⚠ $container ($status, $health)"
            fi
        else
            echo "         ✗ $container ($status)"
        fi
    done

    if [ $running_count -eq ${#containers[@]} ]; then
        test_passed "All containers are running ($running_count/${#containers[@]})"
    elif [ $running_count -gt 0 ]; then
        test_warning "Some containers are not running ($running_count/${#containers[@]})"
    else
        test_failed "No containers are running (0/${#containers[@]})"
    fi

    if [ $healthy_count -ne ${#containers[@]} ]; then
        test_warning "Not all containers are healthy ($healthy_count/${#containers[@]})"
    fi

    echo
}

# Test 5: Verify container mounts point to external volume
test_container_mounts() {
    echo -e "${CYAN}[Test 5] Container Mount Points${NC}"

    local containers=($(docker ps --filter "name=^openwebui-" --format "{{.Names}}" | sort))

    if [ ${#containers[@]} -eq 0 ]; then
        test_warning "No running containers to check mounts"
        echo
        return
    fi

    local mount_pass=true

    for container in "${containers[@]}"; do
        # Check if container has bind mounts pointing through symlink
        local mounts=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}} {{end}}{{end}}' "$container")

        if echo "$mounts" | grep -q "$OPENWEBUI_BASE"; then
            echo "         ✓ $container uses $OPENWEBUI_BASE"
        else
            echo "         ✗ $container does NOT use $OPENWEBUI_BASE"
            mount_pass=false
        fi
    done

    if [ "$mount_pass" = true ]; then
        test_passed "All containers mount through symlink"
    else
        test_failed "Some containers have incorrect mount points"
    fi

    echo
}

# Test 6: Verify branding files exist
test_branding_files() {
    echo -e "${CYAN}[Test 6] Branding Files${NC}"

    if [ ! -d "$EXTERNAL_DATA_DIR" ]; then
        test_warning "Cannot check branding - external directory not found"
        echo
        return
    fi

    local client_dirs=($(find "$EXTERNAL_DATA_DIR" -maxdepth 1 -type d -name "*" ! -name "openwebui" | sort))
    local branding_found=0

    for client_dir in "${client_dirs[@]}"; do
        local client_name=$(basename "$client_dir")
        local branding_dir="$client_dir/branding"

        if [ -d "$branding_dir" ]; then
            local logo_count=$(find "$branding_dir" -name "*.png" -o -name "*.svg" -o -name "*.ico" | wc -l)

            if [ $logo_count -gt 0 ]; then
                echo "         ✓ $client_name has $logo_count branding file(s)"
                ((branding_found++))
            fi
        fi
    done

    if [ $branding_found -gt 0 ]; then
        test_passed "Found branding files for $branding_found client(s)"
    else
        test_warning "No branding files found (this might be okay)"
    fi

    echo
}

# Test 7: Verify fstab entry
test_fstab_entry() {
    echo -e "${CYAN}[Test 7] Persistent Mount Configuration${NC}"

    if grep -q "$MOUNT_POINT" /etc/fstab; then
        test_passed "External volume is configured in /etc/fstab for persistent mounting"

        local fstab_line=$(grep "$MOUNT_POINT" /etc/fstab | head -1)
        echo "         $fstab_line"
    else
        test_failed "No /etc/fstab entry found for $MOUNT_POINT"
        test_warning "Volume will NOT auto-mount after reboot!"
    fi

    echo
}

# Test 8: Verify disk space
test_disk_space() {
    echo -e "${CYAN}[Test 8] Disk Space${NC}"

    local usage=$(df "$EXTERNAL_DATA_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')

    if [ "$usage" -lt 80 ]; then
        test_passed "Disk usage is acceptable ($usage%)"
    elif [ "$usage" -lt 90 ]; then
        test_warning "Disk usage is high ($usage%)"
    else
        test_failed "Disk usage is critical ($usage%)"
    fi

    df -h "$EXTERNAL_DATA_DIR" | tail -1

    echo
}

# Test 9: Test write access
test_write_access() {
    echo -e "${CYAN}[Test 9] Write Access${NC}"

    local test_file="$EXTERNAL_DATA_DIR/.write-test-$(date +%s)"

    if touch "$test_file" 2>/dev/null; then
        rm -f "$test_file"
        test_passed "Write access confirmed to external volume"
    else
        test_failed "Cannot write to external volume"
    fi

    echo
}

# Display final summary
display_summary() {
    local total_tests=$((TESTS_PASSED + TESTS_FAILED + TESTS_WARNING))

    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Test Summary${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Passed:   $TESTS_PASSED${NC}"
    echo -e "${RED}Failed:   $TESTS_FAILED${NC}"
    echo -e "${YELLOW}Warnings: $TESTS_WARNING${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────${NC}"
    echo -e "Total:    $total_tests"
    echo

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ✓ Migration Verification PASSED                      ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
        echo
        echo -e "${CYAN}Next Steps:${NC}"
        echo "  1. Test your Open WebUI deployments in a browser"
        echo "  2. Verify branding appears correctly"
        echo "  3. Test creating/editing content"
        echo "  4. If everything works, you can remove the backup:"
        echo "     rm -rf ${OPENWEBUI_BASE}.backup-*"
        echo

        return 0
    else
        echo -e "${RED}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  ✗ Migration Verification FAILED                      ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════════════╝${NC}"
        echo
        echo -e "${CYAN}Recommended Actions:${NC}"
        echo "  1. Review failed tests above"
        echo "  2. Check container logs: docker logs <container-name>"
        echo "  3. If critical issues, rollback with: bash 9-rollback-to-local.sh"
        echo

        return 1
    fi
}

# Main execution
main() {
    echo -e "${CYAN}Running verification tests...${NC}"
    echo

    # Run all tests
    test_volume_mounted
    test_symlink
    test_data_directories
    test_containers_running
    test_container_mounts
    test_branding_files
    test_fstab_entry
    test_disk_space
    test_write_access

    # Display summary
    display_summary
}

# Run main function
main "$@"
