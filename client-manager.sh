#!/bin/bash

# Multi-Client Management Script

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

show_help() {
    echo "Multi-Client Open WebUI Management"
    echo "=================================="
    echo
    echo "Start Clients:"
    echo "  ./start-acme-corp.sh       - Start ACME Corp instance (port 8081)"
    echo "  ./start-beta-client.sh     - Start Beta Client instance (port 8082)"
    echo "  ./start-template.sh NAME PORT DOMAIN - Start custom client"
    echo
    echo "Manage All Clients:"
    echo "  ./client-manager.sh list   - List all Open WebUI containers"
    echo "  ./client-manager.sh stop   - Stop all Open WebUI containers"
    echo "  ./client-manager.sh start  - Start all Open WebUI containers"
    echo "  ./client-manager.sh logs CLIENT_NAME - Show logs for specific client"
    echo
    echo "Individual Client Commands:"
    echo "  docker stop openwebui-CLIENT_NAME"
    echo "  docker start openwebui-CLIENT_NAME"
    echo "  docker logs -f openwebui-CLIENT_NAME"
    echo
}

check_root_ssh_status() {
    # Check if PermitRootLogin is set to secure settings in sshd_config
    local permit_root=$(sudo grep -E "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')

    # Secure settings: no, prohibit-password, without-password
    if [[ "$permit_root" == "no" ]] || [[ "$permit_root" == "No" ]] || \
       [[ "$permit_root" == "prohibit-password" ]] || [[ "$permit_root" == "without-password" ]]; then
        echo "secured"
    else
        echo "vulnerable"
    fi
}

check_firewall_status() {
    # Check if UFW firewall is configured according to setup/README recommendations
    # Required: UFW enabled, ports 22, 80, 443 allowed

    # Check if UFW is installed
    if ! command -v ufw &> /dev/null; then
        echo "not_installed"
        return
    fi

    # Check if UFW is enabled
    local ufw_status=$(sudo ufw status 2>/dev/null | head -1)
    if [[ ! "$ufw_status" =~ "Status: active" ]]; then
        echo "not_configured"
        return
    fi

    # Check if required ports are allowed
    local ufw_rules=$(sudo ufw status numbered 2>/dev/null)
    local port_22_allowed=false
    local port_80_allowed=false
    local port_443_allowed=false

    if echo "$ufw_rules" | grep -q "22/tcp.*ALLOW"; then
        port_22_allowed=true
    fi

    if echo "$ufw_rules" | grep -q "80/tcp.*ALLOW"; then
        port_80_allowed=true
    fi

    if echo "$ufw_rules" | grep -q "443/tcp.*ALLOW"; then
        port_443_allowed=true
    fi

    # All required ports must be allowed
    if [[ "$port_22_allowed" == true ]] && [[ "$port_80_allowed" == true ]] && [[ "$port_443_allowed" == true ]]; then
        echo "configured"
    else
        echo "not_configured"
    fi
}

check_fail2ban_status() {
    # Check if fail2ban is installed and active
    if ! command -v fail2ban-client &> /dev/null; then
        echo "not_installed"
        return
    fi

    # Check if fail2ban service is active
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        echo "active"
    else
        echo "inactive"
    fi
}

check_ssh_password_auth() {
    # Check if SSH password authentication is disabled
    local password_auth=$(sudo grep -E "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')

    if [[ "$password_auth" == "no" ]] || [[ "$password_auth" == "No" ]]; then
        echo "disabled"
    else
        echo "enabled"
    fi
}

check_auto_updates() {
    # Check if unattended-upgrades is installed and configured
    if ! command -v unattended-upgrade &> /dev/null; then
        echo "not_installed"
        return
    fi

    # Check if unattended-upgrades is enabled
    if systemctl is-enabled --quiet unattended-upgrades 2>/dev/null || \
       systemctl is-enabled --quiet apt-daily-upgrade.timer 2>/dev/null; then
        echo "configured"
    else
        echo "not_configured"
    fi
}

count_security_issues() {
    # Count the number of security configurations that need attention
    local issues=0

    local root_ssh=$(check_root_ssh_status)
    [[ "$root_ssh" != "secured" ]] && ((issues++))

    local firewall=$(check_firewall_status)
    [[ "$firewall" != "configured" ]] && ((issues++))

    local fail2ban=$(check_fail2ban_status)
    [[ "$fail2ban" != "active" ]] && ((issues++))

    local ssh_password=$(check_ssh_password_auth)
    [[ "$ssh_password" != "disabled" ]] && ((issues++))

    local auto_updates=$(check_auto_updates)
    [[ "$auto_updates" != "configured" ]] && ((issues++))

    echo $issues
}

check_and_start_branding_monitor() {
    # Check if branding monitor service is running, start it if not
    # This is critical for automatic branding injection after container restarts

    if ! systemctl is-active --quiet branding-monitor 2>/dev/null; then
        echo "⚠️  Branding monitor service is not running"
        echo "    This service automatically restores custom branding after container restarts"
        echo ""
        echo -n "Start branding monitor service now? (Y/n): "
        read start_service

        if [[ ! "$start_service" =~ ^[Nn]$ ]]; then
            echo ""
            echo "Starting branding monitor service..."

            # Check if service exists
            if systemctl list-unit-files | grep -q "branding-monitor.service"; then
                sudo systemctl start branding-monitor

                # Wait a moment and check if it started successfully
                sleep 1

                if systemctl is-active --quiet branding-monitor; then
                    echo "✅ Branding monitor service started successfully"
                    return 0
                else
                    echo "❌ Failed to start branding monitor service"
                    echo "    Check logs: sudo journalctl -u branding-monitor -n 20"
                    echo ""
                    echo -n "Continue anyway? (y/N): "
                    read continue_anyway
                    [[ "$continue_anyway" =~ ^[Yy]$ ]] && return 0 || return 1
                fi
            else
                echo "❌ Branding monitor service is not installed"
                echo "    Run: sudo bash mt/setup/services/install-branding-monitor.sh"
                echo ""
                echo -n "Continue anyway? (y/N): "
                read continue_anyway
                [[ "$continue_anyway" =~ ^[Yy]$ ]] && return 0 || return 1
            fi
        else
            echo "⚠️  Branding may not persist after container restart without the monitor service"
            echo ""
            echo -n "Continue anyway? (y/N): "
            read continue_anyway
            [[ "$continue_anyway" =~ ^[Yy]$ ]] && return 0 || return 1
        fi
    fi

    return 0
}

show_main_menu() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║       Open WebUI Client Manager        ║"
    echo "╚════════════════════════════════════════╝"
    echo

    # Check security status for menu item
    local security_issues=$(count_security_issues)
    local security_option
    if [[ "$security_issues" -gt 0 ]]; then
        security_option="6) ❌ Security Advisement ($security_issues issues)"
    else
        security_option="6) Security Advisor"
    fi

    echo "1) View Deployment Status"
    echo "2) Create New Deployment"
    echo "3) Manage Client Deployment"
    echo "4) Manage Sync Cluster"
    echo "5) Manage nginx Installation"
    echo "$security_option"
    echo "7) Exit"
    echo
    echo -n "Please select an option (1-7): "
}

# Detect container type (sync-node vs client)
detect_container_type() {
    local client_name="$1"

    # Check if this is a sync node
    if [[ "$client_name" == "sync-node-a" ]] || [[ "$client_name" == "sync-node-b" ]]; then
        echo "sync-node"
    else
        echo "client"
    fi
}

get_next_available_port() {
    local start_port=8081
    local max_port=8099

    for ((port=$start_port; port<=$max_port; port++)); do
        # Check if port is used by Docker containers
        if ! docker ps --format "{{.Ports}}" | grep -q ":${port}->"; then
            # Check if port is in use by any process (without sudo)
            if ! lsof -i :$port >/dev/null 2>&1; then
                # Double-check with netstat as backup
                if ! netstat -ln 2>/dev/null | grep -q ":${port} "; then
                    echo $port
                    return 0
                fi
            fi
        fi
    done

    echo "No available ports in range 8081-8099"
    return 1
}

create_new_deployment() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║         Create New Deployment          ║"
    echo "╚════════════════════════════════════════╝"
    echo

    # Get client name
    echo -n "Enter client name (lowercase, no spaces): "
    read client_name

    if [[ ! "$client_name" =~ ^[a-z0-9-]+$ ]]; then
        echo "❌ Invalid client name. Use only lowercase letters, numbers, and hyphens."
        echo "Press Enter to continue..."
        read
        return 1
    fi

    # Detect if nginx is containerized
    nginx_containerized=false
    if docker ps --filter "name=openwebui-nginx" --format "{{.Names}}" | grep -q "^openwebui-nginx$"; then
        nginx_containerized=true
        echo "✓ Detected containerized nginx - deployment will use openwebui-network"
        port="N/A"  # Port not needed for containerized nginx
    else
        echo "ℹ️  Using host nginx mode"
        # Get next available port
        echo "Finding next available port..."
        port=$(get_next_available_port)
        if [ $? -ne 0 ]; then
            echo "❌ $port"
            echo "Press Enter to continue..."
            read
            return 1
        fi
        echo "✅ Port $port is available"
    fi

    # Determine what auto-detect would use (for display in prompt)
    if [ -f "/etc/hostname" ] && grep -q "droplet\|server\|prod\|ubuntu\|digital" /etc/hostname 2>/dev/null; then
        # Production environment
        default_domain="${client_name}.quantabase.io"
    # Check for other production indicators
    elif [ -d "/etc/nginx/sites-available" ] && [ -f "/etc/nginx/sites-available/quantabase" ]; then
        # Has nginx and quantabase config = production server
        default_domain="${client_name}.quantabase.io"
    # Check for cloud provider metadata
    elif curl -s --max-time 2 http://169.254.169.254/metadata/v1/ >/dev/null 2>&1; then
        # Digital Ocean metadata service available = cloud server
        default_domain="${client_name}.quantabase.io"
    else
        # Development environment
        if [ "$nginx_containerized" = true ]; then
            default_domain="localhost"
        else
            default_domain="localhost:${port}"
        fi
    fi

    # Get domain (optional - auto-detect if empty)
    echo
    echo "Enter FULL domain (FQDN) including subdomain"
    echo "  Examples: chat.imagicrafter.com, support.acme-corp.com"
    echo "  Note: The subdomain '${client_name}' should be part of the FQDN"
    echo -n "FQDN (press Enter for '${default_domain}'): "
    read domain

    # Resolve domain for display
    if [[ -z "$domain" ]]; then
        # Use the default we calculated above
        resolved_domain="$default_domain"
        domain="auto-detect"

        # Set redirect URI and environment based on domain type
        if [[ "$resolved_domain" == localhost* ]] || [[ "$resolved_domain" == 127.0.0.1* ]]; then
            if [ "$nginx_containerized" = true ]; then
                redirect_uri="http://localhost/oauth/google/callback"
            else
                redirect_uri="http://127.0.0.1:${port}/oauth/google/callback"
            fi
            environment="development"
        else
            redirect_uri="https://${resolved_domain}/oauth/google/callback"
            environment="production"
        fi
    else
        resolved_domain="$domain"

        # Validate that FQDN starts with the client_name subdomain (unless localhost)
        if [[ ! "$domain" =~ ^localhost ]] && [[ ! "$domain" =~ ^127\.0\.0\.1 ]]; then
            if [[ ! "$domain" =~ ^${client_name}\. ]]; then
                echo ""
                echo "⚠️  WARNING: FQDN does not start with subdomain '${client_name}.'"
                echo "   Entered: ${domain}"
                echo "   Expected: ${client_name}.example.com"
                echo ""
                echo "This may cause issues if you deploy multiple subdomains for the same domain."
                echo "Example collision: Both 'chat' and 'support' subdomains entering 'example.com'"
                echo "                   would create the same container name 'openwebui-example-com'"
                echo ""
                read -p "Continue anyway? (y/N): " continue_anyway
                if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
                    echo "Cancelled. Please re-enter the FQDN."
                    return 1
                fi
            fi
        fi

        if [[ "$domain" == localhost* ]] || [[ "$domain" == 127.0.0.1* ]]; then
            redirect_uri="http://${domain}/oauth/google/callback"
            environment="development"
        else
            redirect_uri="https://${domain}/oauth/google/callback"
            environment="production"
        fi
    fi

    # Get OAuth allowed domains
    echo
    echo -n "Enter OAuth allowed domains (press Enter for 'martins.net'): "
    read oauth_domains

    if [[ -z "$oauth_domains" ]]; then
        oauth_domains="martins.net"
    fi

    # Generate WEBUI_SECRET_KEY for OAuth session encryption
    webui_secret_key=$(openssl rand -base64 32)

    # Sanitize domain for container naming (replace dots and colons with dashes)
    sanitized_fqdn=$(echo "$resolved_domain" | sed 's/\./-/g' | sed 's/:/-/g')
    container_name="openwebui-${sanitized_fqdn}"
    volume_name="${container_name}-data"

    # Check if container already exists
    if docker ps -a --filter "name=${container_name}" --format "{{.Names}}" | grep -q "^${container_name}$"; then
        echo "❌ Container '${container_name}' already exists!"
        echo "   (FQDN: ${resolved_domain})"
        echo "Press Enter to continue..."
        read
        return 1
    fi

    # Show configuration summary
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║         Deployment Summary             ║"
    echo "╚════════════════════════════════════════╝"
    echo "Client Name:     $client_name"
    echo "FQDN:            $resolved_domain"
    echo "Container:       $container_name"
    if [ "$nginx_containerized" = true ]; then
        echo "Network Mode:    openwebui-network (no port mapping)"
    else
        echo "Port:            $port"
    fi
    echo "Environment:     $environment"
    echo "Redirect URI:    $redirect_uri"
    echo "OAuth Domains:   $oauth_domains"
    echo "Volume:          $volume_name"
    echo
    echo -n "Create this deployment? (y/N): "
    read confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo
        echo "Creating deployment..."

        # Create the deployment using the template script
        # Pass: CLIENT_NAME PORT DOMAIN CONTAINER_NAME FQDN OAUTH_DOMAINS WEBUI_SECRET_KEY
        "${SCRIPT_DIR}/start-template.sh" "$client_name" "$port" "$resolved_domain" "$container_name" "$resolved_domain" "$oauth_domains" "$webui_secret_key"

        if [ $? -eq 0 ]; then
            echo "✅ Deployment created successfully!"
            echo
            if [ "$nginx_containerized" = true ]; then
                echo "Next steps:"
                echo "1. Configure nginx for domain: $resolved_domain (use option 5)"
                echo "2. Update Google OAuth redirect URI: $redirect_uri"
                echo "3. Configure DNS for: $resolved_domain"
                echo
                echo "After nginx configuration, access at: https://$resolved_domain"
            else
                echo "Next steps:"
                echo "1. Add nginx configuration for domain: $resolved_domain"
                echo "2. Update Google OAuth redirect URI: $redirect_uri"
                echo "3. Configure DNS for: $resolved_domain"
                echo
                echo "Access at: http://localhost:$port"
            fi
        else
            echo "❌ Failed to create deployment"
        fi
    else
        echo "Deployment cancelled."
    fi

    echo
    echo "Press Enter to continue..."
    read
}

# Manage or deploy nginx container

# Sync-node management menu
manage_sync_node() {
    local client_name="$1"
    local container_name="openwebui-${client_name}"

    # Determine API port based on node (a=9443, b=9444)
    local api_port
    if [[ "$client_name" == "sync-node-a" ]]; then
        api_port=9443
    else
        api_port=9444
    fi

    while true; do
        clear
        echo "╔════════════════════════════════════════╗"
        # Calculate padding for client name to align properly
        local title="   Managing Sync Node: $client_name"
        local padding=$((38 - ${#title}))
        printf "║%s%*s║\n" "$title" $padding ""
        echo "╚════════════════════════════════════════╝"
        echo

        # Show status
        local status=$(docker ps -a --filter "name=$container_name" --format "{{.Status}}")
        local ports=$(docker ps -a --filter "name=$container_name" --format "{{.Ports}}")

        echo "Status:   $status"
        echo "Ports:    $ports"
        echo "API Port: $api_port"
        echo

        echo "1) View Cluster Status"
        echo "2) View Health Check"
        echo "3) View Container Logs (last 50 lines)"
        echo "4) View Live Logs (follow mode)"
        echo "5) Restart Sync Node"
        echo "6) Stop Sync Node"
        echo "7) Return to Deployment List"
        echo
        echo -n "Select action (1-7): "
        read action

        case "$action" in
            1)
                # View Cluster Status
                clear
                echo "╔════════════════════════════════════════╗"
                echo "║          Cluster Status                ║"
                echo "╚════════════════════════════════════════╝"
                echo
                echo "Fetching cluster status from http://localhost:${api_port}/api/v1/cluster/status..."
                echo

                if curl -s -f "http://localhost:${api_port}/api/v1/cluster/status" > /tmp/cluster_status.json 2>/dev/null; then
                    # Pretty print the JSON
                    if command -v jq &> /dev/null; then
                        cat /tmp/cluster_status.json | jq '.'
                    else
                        cat /tmp/cluster_status.json
                        echo
                        echo "(Install 'jq' for formatted output)"
                    fi
                    rm -f /tmp/cluster_status.json
                else
                    echo "❌ Failed to fetch cluster status"
                    echo "Possible reasons:"
                    echo "  - Sync node is not running"
                    echo "  - API port $api_port is not accessible"
                    echo "  - Network connectivity issues"
                fi
                echo
                echo "Press Enter to continue..."
                read
                ;;
            2)
                # View Health Check
                clear
                echo "╔════════════════════════════════════════╗"
                echo "║           Health Check                 ║"
                echo "╚════════════════════════════════════════╝"
                echo
                echo "Fetching health status from http://localhost:${api_port}/health..."
                echo

                if curl -s -f "http://localhost:${api_port}/health" > /tmp/health_check.json 2>/dev/null; then
                    # Pretty print the JSON
                    if command -v jq &> /dev/null; then
                        cat /tmp/health_check.json | jq '.'
                    else
                        cat /tmp/health_check.json
                        echo
                        echo "(Install 'jq' for formatted output)"
                    fi
                    rm -f /tmp/health_check.json
                else
                    echo "❌ Failed to fetch health status"
                    echo "Possible reasons:"
                    echo "  - Sync node is not running"
                    echo "  - API port $api_port is not accessible"
                fi
                echo
                echo "Press Enter to continue..."
                read
                ;;
            3)
                # View Container Logs (last 50 lines)
                clear
                echo "╔════════════════════════════════════════╗"
                echo "║      Container Logs (last 50 lines)    ║"
                echo "╚════════════════════════════════════════╝"
                echo
                docker logs --tail 50 "$container_name"
                echo
                echo "Press Enter to continue..."
                read
                ;;
            4)
                # View Live Logs
                echo
                echo "Starting live log stream for $container_name..."
                echo "(Press Ctrl+C to exit)"
                echo
                sleep 2
                docker logs -f "$container_name"
                ;;
            5)
                # Restart Sync Node
                clear
                echo "╔════════════════════════════════════════╗"
                echo "║         Restart Sync Node              ║"
                echo "╚════════════════════════════════════════╝"
                echo
                echo "⚠️  WARNING: Restarting sync node will temporarily affect sync operations"
                echo
                echo "This sync node will:"
                echo "  - Stop processing sync jobs"
                echo "  - Lose leader status (if it's the current leader)"
                echo "  - Rejoin the cluster and participate in leader election after restart"
                echo
                echo "The other sync node will continue serving requests during the restart."
                echo
                echo -n "Continue with restart? (y/N): "
                read confirm

                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    echo
                    echo "Restarting $container_name..."
                    docker restart "$container_name"
                    echo "✅ Sync node restarted successfully"
                    echo
                    echo "Waiting 5 seconds for startup..."
                    sleep 5

                    # Check health after restart
                    if curl -s -f "http://localhost:${api_port}/health" > /dev/null 2>&1; then
                        echo "✅ Health check passed - sync node is responding"
                    else
                        echo "⚠️  Health check failed - sync node may still be starting up"
                    fi
                else
                    echo "Restart cancelled."
                fi
                echo
                echo "Press Enter to continue..."
                read
                ;;
            6)
                # Stop Sync Node
                clear
                echo "╔════════════════════════════════════════╗"
                echo "║          Stop Sync Node                ║"
                echo "╚════════════════════════════════════════╝"
                echo
                echo "⚠️  CRITICAL WARNING: Stopping this sync node will affect sync operations"
                echo
                echo "Impact:"
                echo "  - This sync node will stop processing sync jobs"
                echo "  - If this is the current leader, leadership will transfer to the other node"
                echo "  - Only one sync node will remain active"
                echo "  - Reduced high availability until both nodes are running"
                echo
                echo "Only stop this node if:"
                echo "  - You need to perform maintenance"
                echo "  - You are troubleshooting an issue"
                echo "  - The other sync node is confirmed healthy and running"
                echo
                echo -n "Type 'STOP' to confirm: "
                read confirm

                if [[ "$confirm" == "STOP" ]]; then
                    echo
                    echo "Stopping $container_name..."
                    docker stop "$container_name"
                    echo "✅ Sync node stopped"
                    echo
                    echo "To restart later, use option 5 (Restart Sync Node) or:"
                    echo "  docker start $container_name"
                else
                    echo "Stop cancelled."
                fi
                echo
                echo "Press Enter to continue..."
                read
                ;;
            7)
                # Return to Deployment List
                return
                ;;
            *)
                echo "Invalid selection. Press Enter to continue..."
                read
                ;;
        esac
    done
}

# Sync Management submenu for client deployments
sync_management_menu() {
    local container_name="$1"

    # Extract client_name from container environment
    local client_name=$(docker exec "$container_name" env 2>/dev/null | grep "^CLIENT_NAME=" | cut -d'=' -f2- 2>/dev/null || echo "")
    if [[ -z "$client_name" ]]; then
        client_name="${container_name#openwebui-}"
    fi

    while true; do
        clear
        echo "╔════════════════════════════════════════╗"
        local title="   Sync Management: $client_name"
        local padding=$((38 - ${#title}))
        printf "║%s%*s║\n" "$title" $padding ""
        echo "╚════════════════════════════════════════╝"
        echo

        echo "1) Register Client for Sync"
        echo "2) Start/Resume Sync"
        echo "3) Pause Sync"
        echo "4) Manual Sync (Full)"
        echo "5) Manual Sync (Incremental)"
        echo "6) View Sync Status"
        echo "7) Deregister Client"
        echo "8) Help (View Scripts Reference)"
        echo "9) Return to Client Menu"
        echo
        echo -n "Select action (1-9): "
        read action

        case "$action" in
            1)
                # Register Client for Sync
                clear
                echo "╔════════════════════════════════════════╗"
                echo "║        Register Client for Sync        ║"
                echo "╚════════════════════════════════════════╝"
                echo
                echo "This will register '$client_name' with the sync system."
                echo
                echo "What will happen:"
                echo "  - Create Supabase schema for this client"
                echo "  - Initialize Open WebUI tables in Supabase"
                echo "  - Enable automatic syncing"
                echo
                echo -n "Continue? (y/N): "
                read confirm

                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    echo
                    "${SCRIPT_DIR}/SYNC/scripts/register-sync-client-to-supabase.sh" "$client_name" "$container_name"
                else
                    echo "Registration cancelled."
                fi
                echo
                echo "Press Enter to continue..."
                read
                ;;
            2)
                # Start/Resume Sync
                clear
                echo "╔════════════════════════════════════════╗"
                echo "║          Start/Resume Sync             ║"
                echo "╚════════════════════════════════════════╝"
                echo

                # Get current sync interval if client is registered
                cd "${SCRIPT_DIR}/SYNC"
                source .credentials

                current_interval=$(docker exec -i -e ADMIN_URL="$ADMIN_URL" -e CLIENT_NAME="$client_name" openwebui-sync-node-a python3 << 'EOF'
import asyncpg, asyncio, os, sys

async def get_interval():
    try:
        conn = await asyncpg.connect(os.getenv('ADMIN_URL'))
        client_name = os.getenv('CLIENT_NAME')
        row = await conn.fetchrow('''
            SELECT sync_interval
            FROM sync_metadata.client_deployments
            WHERE client_name = $1
        ''', client_name)
        await conn.close()
        if row and row['sync_interval']:
            print(row['sync_interval'])
        else:
            print("300")
    except:
        print("300")

asyncio.run(get_interval())
EOF
)

                # Map current interval to menu option
                case $current_interval in
                    60) default_option=1 ;;
                    300) default_option=2 ;;
                    3600) default_option=3 ;;
                    14400) default_option=4 ;;
                    86400) default_option=5 ;;
                    *) default_option=2 ;;
                esac

                echo "Select sync interval for '$client_name':"
                echo
                echo "1) 1 minute (60 seconds)$([ $default_option -eq 1 ] && echo ' [Current]')"
                echo "2) 5 minutes (300 seconds)$([ $default_option -eq 2 ] && echo ' [Current]')"
                echo "3) 1 hour (3600 seconds)$([ $default_option -eq 3 ] && echo ' [Current]')"
                echo "4) 4 hours (14400 seconds)$([ $default_option -eq 4 ] && echo ' [Current]')"
                echo "5) 24 hours (86400 seconds)$([ $default_option -eq 5 ] && echo ' [Current]')"
                echo
                echo "Current interval: $current_interval seconds"
                echo
                echo -n "Enter choice [1-5] (default: $default_option): "
                read interval_choice

                # Use default if no input
                interval_choice=${interval_choice:-$default_option}

                # Map choice to interval value
                case $interval_choice in
                    1) sync_interval=60 ;;
                    2) sync_interval=300 ;;
                    3) sync_interval=3600 ;;
                    4) sync_interval=14400 ;;
                    5) sync_interval=86400 ;;
                    *)
                        echo
                        echo "Invalid choice. Operation cancelled."
                        echo
                        echo "Press Enter to continue..."
                        read
                        continue
                        ;;
                esac

                echo
                echo "Selected interval: $sync_interval seconds"
                echo
                echo -n "Continue? (y/N): "
                read confirm

                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    echo
                    "${SCRIPT_DIR}/SYNC/scripts/start-sync.sh" "$client_name" "$sync_interval"
                else
                    echo "Operation cancelled."
                fi
                echo
                echo "Press Enter to continue..."
                read
                ;;
            3)
                # Pause Sync
                clear
                echo "╔════════════════════════════════════════╗"
                echo "║            Pause Sync                  ║"
                echo "╚════════════════════════════════════════╝"
                echo
                echo "This will temporarily stop automatic syncing for '$client_name'."
                echo "Data and registration will be preserved."
                echo
                echo -n "Continue? (y/N): "
                read confirm

                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    echo
                    "${SCRIPT_DIR}/SYNC/scripts/pause-sync.sh" "$client_name"
                else
                    echo "Operation cancelled."
                fi
                echo
                echo "Press Enter to continue..."
                read
                ;;
            4)
                # Manual Sync (Full)
                clear
                echo "╔════════════════════════════════════════╗"
                echo "║        Manual Full Sync                ║"
                echo "╚════════════════════════════════════════╝"
                echo
                echo "This will perform a complete sync of all data from SQLite to Supabase."
                echo
                echo -n "Continue? (y/N): "
                read confirm

                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    echo
                    cd "${SCRIPT_DIR}/SYNC"
                    source .credentials
                    export DATABASE_URL="$SYNC_URL"
                    ./scripts/sync-client-to-supabase.sh "$client_name" "manual-console" --full
                else
                    echo "Operation cancelled."
                fi
                echo
                echo "Press Enter to continue..."
                read
                ;;
            5)
                # Manual Sync (Incremental)
                clear
                echo "╔════════════════════════════════════════╗"
                echo "║      Manual Incremental Sync           ║"
                echo "╚════════════════════════════════════════╝"
                echo
                echo "This will sync only recent changes from SQLite to Supabase."
                echo
                echo -n "Continue? (y/N): "
                read confirm

                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    echo
                    cd "${SCRIPT_DIR}/SYNC"
                    source .credentials
                    export DATABASE_URL="$SYNC_URL"
                    ./scripts/sync-client-to-supabase.sh "$client_name" "manual-console"
                else
                    echo "Operation cancelled."
                fi
                echo
                echo "Press Enter to continue..."
                read
                ;;
            6)
                # View Sync Status
                clear
                echo "╔════════════════════════════════════════╗"
                echo "║           Sync Status                  ║"
                echo "╚════════════════════════════════════════╝"
                echo

                # Load credentials to get ADMIN_URL
                cd "${SCRIPT_DIR}/SYNC"
                source .credentials

                docker exec -i -e ADMIN_URL="$ADMIN_URL" -e CLIENT_NAME="$client_name" openwebui-sync-node-a python3 << 'EOF'
import asyncpg, asyncio, os, sys

async def check_status():
    try:
        conn = await asyncpg.connect(os.getenv('ADMIN_URL'))
        client_name = os.getenv('CLIENT_NAME')

        # Get deployment info
        deployment = await conn.fetchrow('''
            SELECT deployment_id, sync_enabled, status, sync_interval, last_sync_at, last_sync_status
            FROM sync_metadata.client_deployments
            WHERE client_name = $1
        ''', client_name)

        if not deployment:
            print(f"❌ Client '{client_name}' not found in sync system")
            print(f"   Use option 1 to register this client for sync")
            await conn.close()
            return

        # Get last completed sync job info
        last_job = await conn.fetchrow('''
            SELECT tables_synced, tables_total, duration_seconds, time_since_last_completed
            FROM sync_metadata.v_last_completed_sync_jobs
            WHERE deployment_id = $1
        ''', deployment['deployment_id'])

        print(f"Client: {client_name}")
        print(f"  Sync Enabled: {deployment['sync_enabled']}")
        print(f"  Status: {deployment['status']}")
        print(f"  Interval: {deployment['sync_interval']}s")
        print(f"  Last Sync: {deployment['last_sync_at']}")
        print(f"  Last Status: {deployment['last_sync_status']}")

        if last_job:
            # Calculate percentage
            if last_job['tables_total'] and last_job['tables_total'] > 0:
                tables_pct = (last_job['tables_synced'] / last_job['tables_total']) * 100
            else:
                tables_pct = 0.0

            print(f"  Tables Synced: {last_job['tables_synced']}/{last_job['tables_total']} ({tables_pct:.1f}%)")
            if last_job['duration_seconds']:
                print(f"  Duration: {last_job['duration_seconds']:.1f}s")
            print(f"  Time Since Sync: {last_job['time_since_last_completed']}")

        await conn.close()
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

asyncio.run(check_status())
EOF
                echo
                echo "Press Enter to continue..."
                read
                ;;
            7)
                # Deregister Client
                clear
                echo "╔════════════════════════════════════════╗"
                echo "║         Deregister Client              ║"
                echo "╚════════════════════════════════════════╝"
                echo
                echo "⚠️  WARNING: This will remove '$client_name' from the sync system"
                echo
                echo "Choose removal option:"
                echo "  1) Keep Supabase data (remove from sync only)"
                echo "  2) DELETE all Supabase data (cannot be undone)"
                echo "  3) Cancel"
                echo
                echo -n "Select option (1-3): "
                read deregister_option

                case "$deregister_option" in
                    1)
                        echo
                        echo "Deregistering client (keeping data)..."
                        "${SCRIPT_DIR}/SYNC/scripts/deregister-client.sh" "$client_name"
                        ;;
                    2)
                        echo
                        echo "⚠️  CRITICAL WARNING: This will DELETE ALL DATA for '$client_name' in Supabase!"
                        echo -n "Type 'DELETE' to confirm: "
                        read confirm
                        if [[ "$confirm" == "DELETE" ]]; then
                            "${SCRIPT_DIR}/SYNC/scripts/deregister-client.sh" "$client_name" --drop-schema
                        else
                            echo "Deletion cancelled."
                        fi
                        ;;
                    3)
                        echo "Deregistration cancelled."
                        ;;
                    *)
                        echo "Invalid selection."
                        ;;
                esac
                echo
                echo "Press Enter to continue..."
                read
                ;;
            8)
                # Help - Display SCRIPTS_REFERENCE.md
                clear
                if [ -f "${SCRIPT_DIR}/SYNC/SCRIPTS_REFERENCE.md" ]; then
                    less "${SCRIPT_DIR}/SYNC/SCRIPTS_REFERENCE.md"
                else
                    echo "❌ Scripts reference file not found:"
                    echo "   ${SCRIPT_DIR}/SYNC/SCRIPTS_REFERENCE.md"
                    echo
                    echo "Press Enter to continue..."
                    read
                fi
                ;;
            9)
                # Return to Client Menu
                return
                ;;
            *)
                echo "Invalid selection. Press Enter to continue..."
                read
                ;;
        esac
    done
}

# Deploy sync cluster wrapper function
deploy_sync_cluster() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        Deploy Sync Cluster             ║"
    echo "╚════════════════════════════════════════╝"
    echo

    # Check if cluster already exists
    node_a_exists=$(docker ps -a --filter "name=openwebui-sync-node-a" --format "{{.Names}}" | grep -q "openwebui-sync-node-a" && echo "yes" || echo "no")
    node_b_exists=$(docker ps -a --filter "name=openwebui-sync-node-b" --format "{{.Names}}" | grep -q "openwebui-sync-node-b" && echo "yes" || echo "no")

    if [[ "$node_a_exists" == "yes" ]] || [[ "$node_b_exists" == "yes" ]]; then
        echo "⚠️  WARNING: Sync cluster already exists"
        echo
        echo "Current cluster status:"
        if [[ "$node_a_exists" == "yes" ]]; then
            node_a_status=$(docker ps -a --filter "name=openwebui-sync-node-a" --format "{{.Status}}")
            echo "  Node A: $node_a_status"
        fi
        if [[ "$node_b_exists" == "yes" ]]; then
            node_b_status=$(docker ps -a --filter "name=openwebui-sync-node-b" --format "{{.Status}}")
            echo "  Node B: $node_b_status"
        fi
        echo
        echo "Re-running deployment will:"
        echo "  - Recreate sync node containers"
        echo "  - Update to latest Docker image"
        echo "  - Preserve cluster registration in Supabase"
        echo "  - Preserve all configuration"
        echo
        echo -n "Continue with deployment? (y/N): "
        read confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Deployment cancelled."
            echo
            echo "Press Enter to continue..."
            read
            return
        fi
    else
        echo "This will deploy a high-availability sync cluster with 2 nodes."
        echo
        echo "Requirements:"
        echo "  ✓ Docker installed and running"
        echo "  ✓ Supabase project configured"
        echo "  ✓ Credentials file at mt/SYNC/.credentials"
        echo "  ✓ IPv6 enabled (recommended for HA)"
        echo
        echo "What will be created:"
        echo "  - sync-node-a (primary node, port 9443)"
        echo "  - sync-node-b (secondary node, port 9444)"
        echo "  - Cluster registration in Supabase"
        echo "  - Leader election system"
        echo
        echo -n "Continue with deployment? (y/N): "
        read confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Deployment cancelled."
            echo
            echo "Press Enter to continue..."
            read
            return
        fi
    fi

    echo
    echo "Starting deployment..."
    echo

    # Check if deployment script exists
    if [ ! -f "${SCRIPT_DIR}/SYNC/scripts/deploy-sync-cluster.sh" ]; then
        echo "❌ ERROR: Deployment script not found"
        echo "   Expected: ${SCRIPT_DIR}/SYNC/scripts/deploy-sync-cluster.sh"
        echo
        echo "Press Enter to continue..."
        read
        return
    fi

    # Execute deployment script
    cd "${SCRIPT_DIR}/SYNC"
    ./scripts/deploy-sync-cluster.sh

    deployment_status=$?

    echo
    if [ $deployment_status -eq 0 ]; then
        echo "╔════════════════════════════════════════╗"
        echo "║   Deployment Completed Successfully    ║"
        echo "╚════════════════════════════════════════╝"
        echo
        echo "Next steps:"
        echo "  1. Verify cluster health (option 2 from cluster menu)"
        echo "  2. Register clients for sync (option 3 → Manage Client → Sync Management)"
        echo "  3. Monitor sync operations via cluster status"
        echo
        echo "Cluster endpoints:"
        echo "  - Node A: http://localhost:9443"
        echo "  - Node B: http://localhost:9444"
    else
        echo "╔════════════════════════════════════════╗"
        echo "║      Deployment Failed                 ║"
        echo "╚════════════════════════════════════════╝"
        echo
        echo "Check the output above for error details."
        echo "Common issues:"
        echo "  - Missing credentials file"
        echo "  - Docker not running"
        echo "  - Port conflicts (9443, 9444)"
        echo "  - Supabase connection issues"
    fi

    echo
    echo "Press Enter to continue..."
    read
}

# Deregister sync cluster wrapper function
deregister_sync_cluster() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║      Deregister Sync Cluster           ║"
    echo "╚════════════════════════════════════════╝"
    echo

    # Check if cluster exists
    node_a_exists=$(docker ps -a --filter "name=openwebui-sync-node-a" --format "{{.Names}}" | grep -q "openwebui-sync-node-a" && echo "yes" || echo "no")
    node_b_exists=$(docker ps -a --filter "name=openwebui-sync-node-b" --format "{{.Names}}" | grep -q "openwebui-sync-node-b" && echo "yes" || echo "no")

    if [[ "$node_a_exists" == "no" ]] && [[ "$node_b_exists" == "no" ]]; then
        echo "ℹ️  No sync cluster is currently deployed"
        echo
        echo "Note: This command deregisters cluster metadata from Supabase."
        echo "If you have cluster metadata in Supabase but no local containers,"
        echo "you can still run the deregistration to clean up the database."
        echo
        echo -n "Continue with deregistration anyway? (y/N): "
        read confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Deregistration cancelled."
            echo
            echo "Press Enter to continue..."
            read
            return
        fi
    fi

    echo "⚠️  CRITICAL WARNING: Cluster Deregistration"
    echo
    echo "This will permanently remove cluster metadata from Supabase:"
    echo "  ❌ All host records for this cluster"
    echo "  ❌ Leader election records (CASCADE)"
    echo "  ❌ Client deployment records (CASCADE)"
    echo "  ❌ Cache invalidation events (CASCADE)"
    echo "  ❌ Sync job history (CASCADE)"
    echo
    echo "IMPORTANT: This operation will be BLOCKED if any clients"
    echo "have sync enabled. You must disable or migrate them first."
    echo
    echo "Local Docker containers (sync-node-a, sync-node-b) will NOT"
    echo "be automatically removed. You can remove them manually if needed."
    echo
    echo "This is typically done BEFORE destroying a host/server."
    echo

    # Check if deregister script exists
    if [ ! -f "${SCRIPT_DIR}/SYNC/scripts/deregister-cluster.sh" ]; then
        echo "❌ ERROR: Deregistration script not found"
        echo "   Expected: ${SCRIPT_DIR}/SYNC/scripts/deregister-cluster.sh"
        echo
        echo "Press Enter to continue..."
        read
        return
    fi

    echo -n "Type 'DEREGISTER' to confirm cluster deregistration: "
    read confirmation

    if [[ "$confirmation" != "DEREGISTER" ]]; then
        echo
        echo "Deregistration cancelled (confirmation did not match)."
        echo
        echo "Press Enter to continue..."
        read
        return
    fi

    echo
    echo "Starting deregistration..."
    echo

    # Execute deregistration script
    cd "${SCRIPT_DIR}/SYNC"
    ./scripts/deregister-cluster.sh

    deregister_status=$?

    echo
    if [ $deregister_status -eq 0 ]; then
        echo "╔════════════════════════════════════════╗"
        echo "║  Deregistration Completed Successfully ║"
        echo "╚════════════════════════════════════════╝"
        echo
        echo "Cluster metadata has been removed from Supabase."
        echo
        echo "Next steps:"
        echo "  1. If destroying host: Safe to proceed with host destruction"
        echo "  2. If redeploying: Run option 1 (Deploy Sync Cluster) to create new cluster"
        echo "  3. Local containers: Remove manually if no longer needed:"
        echo "     docker rm -f openwebui-sync-node-a openwebui-sync-node-b"
    else
        echo "╔════════════════════════════════════════╗"
        echo "║      Deregistration Failed             ║"
        echo "╚════════════════════════════════════════╝"
        echo
        echo "Check the output above for details."
        echo
        echo "Common reasons for failure:"
        echo "  ❌ Sync-enabled clients still registered"
        echo "     → Use client sync management to disable sync first"
        echo "  ❌ Missing credentials file"
        echo "  ❌ Cannot connect to Supabase"
        echo "  ❌ Cluster not found in database"
    fi

    echo
    echo "Press Enter to continue..."
    read
}

# View cluster health function
view_cluster_health() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║         Cluster Health Check           ║"
    echo "╚════════════════════════════════════════╝"
    echo

    # Check if nodes exist
    node_a_exists=$(docker ps -a --filter "name=openwebui-sync-node-a" --format "{{.Names}}" | grep -q "openwebui-sync-node-a" && echo "yes" || echo "no")
    node_b_exists=$(docker ps -a --filter "name=openwebui-sync-node-b" --format "{{.Names}}" | grep -q "openwebui-sync-node-b" && echo "yes" || echo "no")

    if [[ "$node_a_exists" == "no" ]] && [[ "$node_b_exists" == "no" ]]; then
        echo "❌ No sync cluster deployed"
        echo
        echo "Deploy a cluster first using option 1 (Deploy Sync Cluster)"
        echo
        echo "Press Enter to continue..."
        read
        return
    fi

    # Check Node A
    echo "═══════════════════════════════════════════════════════════════════"
    echo "Sync Node A Status:"
    echo "═══════════════════════════════════════════════════════════════════"
    echo

    if [[ "$node_a_exists" == "yes" ]]; then
        node_a_status=$(docker ps -a --filter "name=openwebui-sync-node-a" --format "{{.Status}}")
        node_a_running=$(docker ps --filter "name=openwebui-sync-node-a" --format "{{.Names}}" | grep -q "openwebui-sync-node-a" && echo "yes" || echo "no")

        echo "Container Status: $node_a_status"

        if [[ "$node_a_running" == "yes" ]]; then
            echo "Health Endpoint: http://localhost:9443/health"
            echo

            if curl -s -f "http://localhost:9443/health" > /tmp/node_a_health.json 2>/dev/null; then
                echo "Health Check: ✅ Responding"
                if command -v jq &> /dev/null; then
                    cat /tmp/node_a_health.json | jq '.'
                else
                    cat /tmp/node_a_health.json
                    echo
                    echo "(Install 'jq' for formatted JSON output)"
                fi
                rm -f /tmp/node_a_health.json
            else
                echo "Health Check: ❌ Not responding"
                echo "  Node may still be starting up or has issues"
            fi
        else
            echo "Health Check: ⚠️  Container not running"
        fi
    else
        echo "❌ Node A not deployed"
    fi

    echo
    echo "═══════════════════════════════════════════════════════════════════"
    echo "Sync Node B Status:"
    echo "═══════════════════════════════════════════════════════════════════"
    echo

    if [[ "$node_b_exists" == "yes" ]]; then
        node_b_status=$(docker ps -a --filter "name=openwebui-sync-node-b" --format "{{.Status}}")
        node_b_running=$(docker ps --filter "name=openwebui-sync-node-b" --format "{{.Names}}" | grep -q "openwebui-sync-node-b" && echo "yes" || echo "no")

        echo "Container Status: $node_b_status"

        if [[ "$node_b_running" == "yes" ]]; then
            echo "Health Endpoint: http://localhost:9444/health"
            echo

            if curl -s -f "http://localhost:9444/health" > /tmp/node_b_health.json 2>/dev/null; then
                echo "Health Check: ✅ Responding"
                if command -v jq &> /dev/null; then
                    cat /tmp/node_b_health.json | jq '.'
                else
                    cat /tmp/node_b_health.json
                    echo
                    echo "(Install 'jq' for formatted JSON output)"
                fi
                rm -f /tmp/node_b_health.json
            else
                echo "Health Check: ❌ Not responding"
                echo "  Node may still be starting up or has issues"
            fi
        else
            echo "Health Check: ⚠️  Container not running"
        fi
    else
        echo "❌ Node B not deployed"
    fi

    # Try to get cluster status from one of the running nodes
    echo
    echo "═══════════════════════════════════════════════════════════════════"
    echo "Cluster Status (Leader Election):"
    echo "═══════════════════════════════════════════════════════════════════"
    echo

    cluster_status_retrieved="no"

    # Try node A first
    if [[ "$node_a_exists" == "yes" ]] && [[ "$node_a_running" == "yes" ]]; then
        if curl -s -f "http://localhost:9443/api/v1/cluster/status" > /tmp/cluster_status.json 2>/dev/null; then
            cluster_status_retrieved="yes"
            if command -v jq &> /dev/null; then
                cat /tmp/cluster_status.json | jq '.'
            else
                cat /tmp/cluster_status.json
                echo
                echo "(Install 'jq' for formatted JSON output)"
            fi
            rm -f /tmp/cluster_status.json
        fi
    fi

    # Try node B if node A didn't work
    if [[ "$cluster_status_retrieved" == "no" ]] && [[ "$node_b_exists" == "yes" ]] && [[ "$node_b_running" == "yes" ]]; then
        if curl -s -f "http://localhost:9444/api/v1/cluster/status" > /tmp/cluster_status.json 2>/dev/null; then
            cluster_status_retrieved="yes"
            if command -v jq &> /dev/null; then
                cat /tmp/cluster_status.json | jq '.'
            else
                cat /tmp/cluster_status.json
                echo
                echo "(Install 'jq' for formatted JSON output)"
            fi
            rm -f /tmp/cluster_status.json
        fi
    fi

    if [[ "$cluster_status_retrieved" == "no" ]]; then
        echo "❌ Could not retrieve cluster status"
        echo "  Ensure at least one node is running and responding"
    fi

    echo
    echo "═══════════════════════════════════════════════════════════════════"
    echo
    echo "Press Enter to continue..."
    read
}

# Update sync nodes function
update_sync_nodes() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║       Update Sync Nodes (Both)         ║"
    echo "╚════════════════════════════════════════╝"
    echo

    # Check if nodes exist
    node_a_exists=$(docker ps -a --filter "name=openwebui-sync-node-a" --format "{{.Names}}" | grep -q "openwebui-sync-node-a" && echo "yes" || echo "no")
    node_b_exists=$(docker ps -a --filter "name=openwebui-sync-node-b" --format "{{.Names}}" | grep -q "openwebui-sync-node-b" && echo "yes" || echo "no")

    if [[ "$node_a_exists" == "no" ]] && [[ "$node_b_exists" == "no" ]]; then
        echo "❌ No sync cluster deployed"
        echo
        echo "Deploy a cluster first using option 1 (Deploy Sync Cluster)"
        echo
        echo "Press Enter to continue..."
        read
        return
    fi

    echo "⚠️  CRITICAL: This will update BOTH sync nodes simultaneously"
    echo
    echo "What will happen:"
    echo "  1. Both sync nodes will be stopped (2-5 minute downtime)"
    echo "  2. Latest Docker image will be pulled"
    echo "  3. Both nodes will be recreated with latest code"
    echo "  4. All configuration and cluster registration preserved"
    echo "  5. Leader election will occur after restart"
    echo

    # Check if credentials file exists
    if [ ! -f "${SCRIPT_DIR}/SYNC/.credentials" ]; then
        echo "❌ ERROR: Credentials file not found"
        echo "   Expected: ${SCRIPT_DIR}/SYNC/.credentials"
        echo "   This file is required for the update process"
        echo
        echo "Press Enter to continue..."
        read
        return
    fi

    # Check for sync-enabled clients using docker exec
    echo "═══════════════════════════════════════════════════════════════════"
    echo "Checking for clients with sync enabled..."
    echo "═══════════════════════════════════════════════════════════════════"
    echo

    # Try to query Supabase for sync-enabled clients
    if [[ "$node_a_exists" == "yes" ]] || [[ "$node_b_exists" == "yes" ]]; then
        # Source credentials to get ADMIN_URL
        cd "${SCRIPT_DIR}/SYNC"
        if [ -f .credentials ]; then
            source .credentials
        else
            echo "⚠️  WARNING: Credentials file not found"
            echo "   Cannot check for sync-enabled clients"
            echo
            ADMIN_URL=""
        fi

        # Check if we have ADMIN_URL
        if [ -z "$ADMIN_URL" ]; then
            echo "⚠️  WARNING: ADMIN_URL not found in credentials"
            echo "   Cannot check for sync-enabled clients"
            echo "   The update can proceed, but please manually verify no syncs are running"
            echo
        else
            # Query for sync-enabled clients (pass ADMIN_URL to container)
            sync_enabled_clients=$(docker exec -i -e ADMIN_URL="$ADMIN_URL" openwebui-sync-node-a python3 2>&1 << 'EOF'
import asyncpg, asyncio, os, sys

async def check_clients():
    try:
        admin_url = os.getenv('ADMIN_URL')
        if not admin_url:
            print("ERROR:ADMIN_URL not set")
            sys.exit(1)

        conn = await asyncpg.connect(admin_url)
        rows = await conn.fetch('''
            SELECT client_name, container_name, status, last_sync_at, last_sync_status
            FROM sync_metadata.client_deployments
            WHERE sync_enabled = true
            ORDER BY client_name
        ''')

        if rows:
            print("SYNC_ENABLED_FOUND")
            for row in rows:
                last_sync = row['last_sync_at'] if row['last_sync_at'] else "Never"
                last_status = row['last_sync_status'] if row['last_sync_status'] else "N/A"
                print(f"  • {row['client_name']} (container: {row['container_name']})")
                print(f"    Status: {row['status']} | Last sync: {last_sync} | Last status: {last_status}")
        else:
            print("NO_SYNC_ENABLED")

        await conn.close()
    except Exception as e:
        print(f"ERROR:{e}")
        sys.exit(1)

asyncio.run(check_clients())
EOF
)

        check_result=$?

        if [[ $check_result -ne 0 ]]; then
            echo "⚠️  WARNING: Could not query Supabase for sync-enabled clients"
            echo "   The update can proceed, but please manually verify no syncs are running"
            echo
        elif echo "$sync_enabled_clients" | grep -q "SYNC_ENABLED_FOUND"; then
            echo "❌ CANNOT UPDATE: Clients with sync enabled detected"
            echo
            echo "$sync_enabled_clients" | grep -v "SYNC_ENABLED_FOUND"
            echo
            echo "═══════════════════════════════════════════════════════════════════"
            echo "REQUIRED ACTIONS before updating:"
            echo "═══════════════════════════════════════════════════════════════════"
            echo
            echo "You must PAUSE sync for all clients listed above:"
            echo
            echo "For each client:"
            echo "  1. Return to main menu (press 8, then 7)"
            echo "  2. Select: 3) Manage Client Deployment"
            echo "  3. Select the client from the list"
            echo "  4. Select: 8) Sync Management"
            echo "  5. Select: 3) Pause Sync"
            echo "  6. Confirm the pause"
            echo
            echo "After all clients are paused, return here to update the cluster."
            echo
            echo "Press Enter to continue..."
            read
            return
        else
            echo "✅ No clients with sync enabled found"
            echo
        fi
        fi
    else
        echo "⚠️  WARNING: Cannot check for sync-enabled clients (no nodes running)"
        echo "   Proceeding with update assuming no active syncs"
        echo
    fi

    echo "═══════════════════════════════════════════════════════════════════"
    echo "Update Impact:"
    echo "═══════════════════════════════════════════════════════════════════"
    echo
    echo "Expected Downtime: 2-5 minutes"
    echo
    echo "During update:"
    echo "  ❌ No sync operations will occur"
    echo "  ❌ No leader will be available"
    echo "  ❌ Health endpoints will not respond"
    echo
    echo "After update:"
    echo "  ✅ Nodes will restart automatically"
    echo "  ✅ Leader election will occur (~30 seconds)"
    echo "  ✅ Sync operations will resume for paused clients (if re-enabled)"
    echo
    echo "⚠️  IMPORTANT: This is typically done during maintenance windows"
    echo
    echo -n "Type 'UPDATE' to confirm cluster update: "
    read confirmation

    if [[ "$confirmation" != "UPDATE" ]]; then
        echo
        echo "Update cancelled (confirmation did not match)."
        echo
        echo "Press Enter to continue..."
        read
        return
    fi

    echo
    echo "Starting cluster update..."
    echo

    # Check if deployment script exists
    if [ ! -f "${SCRIPT_DIR}/SYNC/scripts/deploy-sync-cluster.sh" ]; then
        echo "❌ ERROR: Deployment script not found"
        echo "   Expected: ${SCRIPT_DIR}/SYNC/scripts/deploy-sync-cluster.sh"
        echo
        echo "Press Enter to continue..."
        read
        return
    fi

    # Execute deployment script (which handles updates)
    cd "${SCRIPT_DIR}/SYNC"
    ./scripts/deploy-sync-cluster.sh

    update_status=$?

    echo
    if [ $update_status -eq 0 ]; then
        echo "╔════════════════════════════════════════╗"
        echo "║   Update Completed Successfully        ║"
        echo "╚════════════════════════════════════════╝"
        echo
        echo "Verifying cluster health..."
        sleep 5

        # Check health of both nodes
        node_a_healthy="no"
        node_b_healthy="no"

        if curl -s -f "http://localhost:9443/health" > /dev/null 2>&1; then
            node_a_healthy="yes"
            echo "  ✅ Node A: Healthy and responding"
        else
            echo "  ⚠️  Node A: Not responding (may still be starting)"
        fi

        if curl -s -f "http://localhost:9444/health" > /dev/null 2>&1; then
            node_b_healthy="yes"
            echo "  ✅ Node B: Healthy and responding"
        else
            echo "  ⚠️  Node B: Not responding (may still be starting)"
        fi

        echo
        echo "Next steps:"
        echo "  1. Verify cluster health (option 2 from cluster menu)"
        echo "  2. Check leader election status"
        if echo "$sync_enabled_clients" | grep -q "SYNC_ENABLED_FOUND"; then
            echo "  3. Re-enable sync for clients that were paused:"
            echo "     - Main menu → 3) Manage Client Deployment → [client] → 8) Sync Management → 2) Start/Resume Sync"
        fi
        echo
    else
        echo "╔════════════════════════════════════════╗"
        echo "║         Update Failed                  ║"
        echo "╚════════════════════════════════════════╝"
        echo
        echo "Check the output above for error details."
        echo
        echo "Common issues:"
        echo "  ❌ Missing credentials file"
        echo "  ❌ Docker not running"
        echo "  ❌ Port conflicts (9443, 9444)"
        echo "  ❌ Supabase connection issues"
        echo "  ❌ Image pull failures"
        echo
        echo "The cluster may be in an inconsistent state."
        echo "Check container status with: docker ps -a | grep sync-node"
    fi

    echo
    echo "Press Enter to continue..."
    read
}

# Sync Cluster management menu
manage_sync_cluster_menu() {
    while true; do
        clear
        echo "╔════════════════════════════════════════╗"
        echo "║       Manage Sync Cluster Menu         ║"
        echo "╚════════════════════════════════════════╝"
        echo

        # Check if sync nodes exist
        node_a_exists=$(docker ps -a --filter "name=openwebui-sync-node-a" --format "{{.Names}}" | grep -q "openwebui-sync-node-a" && echo "yes" || echo "no")
        node_b_exists=$(docker ps -a --filter "name=openwebui-sync-node-b" --format "{{.Names}}" | grep -q "openwebui-sync-node-b" && echo "yes" || echo "no")

        if [[ "$node_a_exists" == "yes" ]] || [[ "$node_b_exists" == "yes" ]]; then
            echo "Cluster Status:"
            if [[ "$node_a_exists" == "yes" ]]; then
                node_a_status=$(docker ps -a --filter "name=openwebui-sync-node-a" --format "{{.Status}}")
                echo "  Node A: $node_a_status"
            else
                echo "  Node A: Not deployed"
            fi
            if [[ "$node_b_exists" == "yes" ]]; then
                node_b_status=$(docker ps -a --filter "name=openwebui-sync-node-b" --format "{{.Status}}")
                echo "  Node B: $node_b_status"
            else
                echo "  Node B: Not deployed"
            fi
        else
            echo "⚠️  No sync cluster deployed"
        fi
        echo

        echo "1) Deploy Sync Cluster"
        echo "2) View Cluster Health"
        echo "3) Manage Sync Node A"
        echo "4) Manage Sync Node B"
        echo "5) Deregister Cluster"
        echo "6) Update Sync Nodes (Both)"
        echo "7) Help (Documentation)"
        echo "8) Return to Main Menu"
        echo
        echo -n "Select option (1-8): "
        read choice

        case "$choice" in
            1)
                deploy_sync_cluster
                ;;
            2)
                view_cluster_health
                ;;
            3)
                if [[ "$node_a_exists" == "yes" ]]; then
                    manage_sync_node "sync-node-a"
                else
                    echo
                    echo "❌ Sync Node A is not deployed"
                    echo "   Use option 1 to deploy the sync cluster first"
                    echo
                    echo "Press Enter to continue..."
                    read
                fi
                ;;
            4)
                if [[ "$node_b_exists" == "yes" ]]; then
                    manage_sync_node "sync-node-b"
                else
                    echo
                    echo "❌ Sync Node B is not deployed"
                    echo "   Use option 1 to deploy the sync cluster first"
                    echo
                    echo "Press Enter to continue..."
                    read
                fi
                ;;
            5)
                deregister_sync_cluster
                ;;
            6)
                update_sync_nodes
                ;;
            7)
                clear
                echo "╔════════════════════════════════════════╗"
                echo "║         Sync Cluster Help              ║"
                echo "╚════════════════════════════════════════╝"
                echo
                echo "Available documentation:"
                echo
                if [ -f "${SCRIPT_DIR}/SYNC/README.md" ]; then
                    echo "1) View SYNC/README.md (press 1)"
                fi
                if [ -f "${SCRIPT_DIR}/SYNC/TECHNICAL_REFERENCE.md" ]; then
                    echo "2) View SYNC/TECHNICAL_REFERENCE.md (press 2)"
                fi
                if [ -f "${SCRIPT_DIR}/SYNC/CLUSTER_LIFECYCLE_FAQ.md" ]; then
                    echo "3) View SYNC/CLUSTER_LIFECYCLE_FAQ.md (press 3)"
                fi
                echo "0) Return to cluster menu"
                echo
                echo -n "Select documentation (0-3): "
                read doc_choice

                case "$doc_choice" in
                    1)
                        if [ -f "${SCRIPT_DIR}/SYNC/README.md" ]; then
                            less "${SCRIPT_DIR}/SYNC/README.md"
                        fi
                        ;;
                    2)
                        if [ -f "${SCRIPT_DIR}/SYNC/TECHNICAL_REFERENCE.md" ]; then
                            less "${SCRIPT_DIR}/SYNC/TECHNICAL_REFERENCE.md"
                        fi
                        ;;
                    3)
                        if [ -f "${SCRIPT_DIR}/SYNC/CLUSTER_LIFECYCLE_FAQ.md" ]; then
                            less "${SCRIPT_DIR}/SYNC/CLUSTER_LIFECYCLE_FAQ.md"
                        fi
                        ;;
                    0)
                        # Return to cluster menu
                        ;;
                    *)
                        echo "Invalid selection"
                        sleep 1
                        ;;
                esac
                ;;
            8)
                return
                ;;
            *)
                echo "Invalid selection. Press Enter to continue..."
                read
                ;;
        esac
    done
}

manage_deployment_menu() {
    while true; do
        clear
        echo "╔════════════════════════════════════════╗"
        echo "║        Manage Deployment Menu          ║"
        echo "╚════════════════════════════════════════╝"
        echo

        # List available clients (exclude sync-nodes and nginx, keep full container names)
        echo "Available client deployments:"
        all_containers=($(docker ps -a --filter "name=openwebui-" --format "{{.Names}}"))

        # Filter out sync-nodes and nginx
        clients=()
        for container in "${all_containers[@]}"; do
            if [[ "$container" != "openwebui-sync-node-a" ]] && \
               [[ "$container" != "openwebui-sync-node-b" ]] && \
               [[ "$container" != "openwebui-nginx" ]]; then
                clients+=("$container")
            fi
        done

        if [ ${#clients[@]} -eq 0 ]; then
            echo "No client deployments found."
            echo
            echo "ℹ️  Note: Sync nodes are managed via option 4 (Manage Sync Cluster)"
            echo
            echo "Press Enter to return to main menu..."
            read
            return
        fi

        for i in "${!clients[@]}"; do
            container_name="${clients[$i]}"
            status=$(docker ps -a --filter "name=${container_name}" --format "{{.Status}}")

            # Try to get client_name and FQDN from container environment
            client_name=$(docker exec "${container_name}" env 2>/dev/null | grep "^CLIENT_NAME=" | cut -d'=' -f2- 2>/dev/null || echo "")
            fqdn=$(docker exec "${container_name}" env 2>/dev/null | grep "^FQDN=" | cut -d'=' -f2- 2>/dev/null || echo "")

            # Fallback to extracting from GOOGLE_REDIRECT_URI
            if [[ -z "$fqdn" ]]; then
                redirect_uri=$(docker exec "${container_name}" env 2>/dev/null | grep "GOOGLE_REDIRECT_URI=" | cut -d'=' -f2- 2>/dev/null || echo "")
                if [[ -n "$redirect_uri" ]]; then
                    fqdn=$(echo "$redirect_uri" | sed -E 's|https?://||' | sed 's|/oauth/google/callback||')
                fi
            fi

            # Display format: CLIENT_NAME (FQDN) [status]
            if [[ -n "$client_name" ]] && [[ -n "$fqdn" ]]; then
                echo "$((i+1))) $client_name → $fqdn ($status)"
            elif [[ -n "$fqdn" ]]; then
                echo "$((i+1))) $fqdn ($status)"
            else
                # Ultimate fallback: show container name
                display_name="${container_name#openwebui-}"
                echo "$((i+1))) $display_name ($status)"
            fi
        done

        echo "$((${#clients[@]}+1))) Return to main menu"
        echo
        echo -n "Select deployment to manage (1-$((${#clients[@]}+1))): "
        read selection

        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -gt 0 ] && [ "$selection" -le ${#clients[@]} ]; then
            manage_single_deployment "${clients[$((selection-1))]}"
        elif [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -eq $((${#clients[@]}+1)) ]; then
            return
        else
            echo "Invalid selection. Press Enter to continue..."
            read
        fi
    done
}

manage_single_deployment() {
    local container_name="$1"

    # Extract client_name from container environment
    local client_name=$(docker exec "$container_name" env 2>/dev/null | grep "^CLIENT_NAME=" | cut -d'=' -f2- 2>/dev/null || echo "")

    # Fallback: extract from container name (strip openwebui- prefix)
    if [[ -z "$client_name" ]]; then
        client_name="${container_name#openwebui-}"
    fi

    # Detect container type and route to appropriate menu
    if [[ "$container_name" == *"sync-node"* ]]; then
        # Route to sync-node management menu (expects short name like "sync-node-a")
        local sync_node_name="${container_name#openwebui-}"
        manage_sync_node "$sync_node_name"
        return
    fi

    # Continue with client deployment menu for non-sync-node containers
    # Color codes for output
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local YELLOW='\033[1;33m'
    local NC='\033[0m'

    while true; do
        clear

        # Extract FQDN for display
        local fqdn=$(docker exec "$container_name" env 2>/dev/null | grep "^FQDN=" | cut -d'=' -f2- 2>/dev/null || echo "")
        if [[ -z "$fqdn" ]]; then
            # Fallback to extracting from GOOGLE_REDIRECT_URI
            local redirect_uri=$(docker exec "$container_name" env 2>/dev/null | grep "GOOGLE_REDIRECT_URI=" | cut -d'=' -f2- 2>/dev/null || echo "")
            if [[ -n "$redirect_uri" ]]; then
                fqdn=$(echo "$redirect_uri" | sed -E 's|https?://||' | sed 's|/oauth/google/callback||')
            fi
        fi

        echo "╔════════════════════════════════════════╗"
        # Display client name and FQDN in title
        if [[ -n "$fqdn" ]]; then
            local title="   Managing: $client_name ($fqdn)"
        else
            local title="   Managing: $client_name"
        fi
        # Truncate title if too long
        if [ ${#title} -gt 36 ]; then
            title="${title:0:33}..."
        fi
        local padding=$((38 - ${#title}))
        printf "║%s%*s║\n" "$title" $padding ""
        echo "╚════════════════════════════════════════╝"
        echo

        # Show status
        local status=$(docker ps -a --filter "name=$container_name" --format "{{.Status}}")
        local ports=$(docker ps -a --filter "name=$container_name" --format "{{.Ports}}")

        echo "Status: $status"
        echo "Ports:  $ports"
        if [[ -n "$fqdn" ]]; then
            echo "Domain: $fqdn"
        fi

        # Detect and display database configuration
        local database_url=$(docker exec "$container_name" env 2>/dev/null | grep "DATABASE_URL=" | cut -d'=' -f2- 2>/dev/null || echo "")

        if [[ -n "$database_url" ]]; then
            # PostgreSQL detected
            local db_host=$(echo "$database_url" | sed 's|postgresql://[^@]*@||' | cut -d':' -f1)
            local db_port=$(echo "$database_url" | sed 's|.*:||' | cut -d'/' -f1)
            local db_name=$(echo "$database_url" | sed 's|.*/||')
            echo "Database: PostgreSQL"
            echo "  Host: $db_host:$db_port"
            echo "  Name: $db_name"
        else
            # SQLite (default)
            echo "Database: SQLite (default)"
        fi

        echo

        echo "1) Start deployment"
        echo "2) Stop deployment"
        echo "3) Restart deployment"
        echo "4) View logs"
        echo "5) Show Cloudflare DNS configuration"
        echo "6) Update OAuth allowed domains"
        echo "7) Change domain/client (preserve data)"
        echo "8) Sync Management"

        # Show database option based on current database type
        if [[ -n "$database_url" ]]; then
            echo "9) View database configuration (includes rollback)"
        else
            echo "9) Migrate to Supabase/PostgreSQL"
        fi

        echo "10) User Management"
        echo "11) Asset Management"
        echo "12) Remove deployment (DANGER)"
        echo "13) Return to deployment list"
        echo
        echo -n "Select action (1-13): "
        read action

        case "$action" in
            1)
                echo "Starting $container_name..."
                docker start "$container_name"
                echo "Press Enter to continue..."
                read
                ;;
            2)
                echo "Stopping $container_name..."
                docker stop "$container_name"
                echo "Press Enter to continue..."
                read
                ;;
            3)
                echo "Restarting $container_name..."
                docker restart "$container_name"
                echo "Press Enter to continue..."
                read
                ;;
            4)
                echo "Showing logs for $container_name (Ctrl+C to exit)..."
                echo "Press Enter to continue..."
                read
                docker logs -f "$container_name"
                ;;
            5)
                # Show Cloudflare configuration
                # Get domain from container environment
                redirect_uri=$(docker exec "$container_name" env 2>/dev/null | grep "GOOGLE_REDIRECT_URI=" | cut -d'=' -f2- 2>/dev/null || echo "")
                if [[ -n "$redirect_uri" ]]; then
                    domain=$(echo "$redirect_uri" | sed -E 's|https?://||' | sed 's|/oauth/google/callback||')
                    subdomain=$(echo "$domain" | cut -d'.' -f1)
                    base_domain=$(echo "$domain" | cut -d'.' -f2-)
                    server_ip=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")

                    echo
                    echo "╔════════════════════════════════════════╗"
                    echo "║      Cloudflare DNS Configuration      ║"
                    echo "╚════════════════════════════════════════╝"
                    echo
                    echo "Domain: $domain"
                    echo "Server IP: $server_ip"
                    echo
                    echo "1. Go to Cloudflare Dashboard"
                    echo "   → Select domain: $base_domain"
                    echo "   → Go to DNS → Records"
                    echo
                    echo "2. Create DNS Record:"
                    echo "   Type: A"
                    echo "   Name: $subdomain"
                    echo "   IPv4 address: $server_ip"
                    echo "   Proxy status: Proxied (orange cloud) ✓"
                    echo
                    echo "3. SSL/TLS Configuration:"
                    echo "   → Go to SSL/TLS → Overview"
                    echo "   → Set encryption mode: Full (strict)"
                    echo
                    echo "4. Wait for DNS propagation (1-5 minutes)"
                    echo "   Test with: nslookup $domain"
                    echo
                else
                    echo "❌ Could not determine domain for this deployment"
                fi
                echo "Press Enter to continue..."
                read
                ;;
            6)
                # Update OAuth allowed domains
                echo
                echo "╔════════════════════════════════════════╗"
                echo "║       Update OAuth Allowed Domains     ║"
                echo "╚════════════════════════════════════════╝"
                echo

                # Get current domains from container
                current_domains=$(docker exec "$container_name" env 2>/dev/null | grep "OAUTH_ALLOWED_DOMAINS=" | cut -d'=' -f2- 2>/dev/null || echo "")
                if [[ -n "$current_domains" ]]; then
                    echo "Current allowed domains: $current_domains"
                else
                    echo "Current allowed domains: Not set"
                fi
                echo

                echo "Enter new allowed domains (comma-separated, e.g., martins.net,example.com):"
                echo -n "New domains: "
                read new_domains

                if [[ -z "$new_domains" ]]; then
                    echo "❌ No domains provided. Operation cancelled."
                    echo "Press Enter to continue..."
                    read
                    continue
                fi

                echo
                echo "⚠️  This will recreate the container with new domain settings."
                echo "All data will be preserved (volumes are maintained)."
                echo "New allowed domains: $new_domains"
                echo
                echo -n "Continue? (y/N): "
                read confirm

                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    echo
                    echo "Updating allowed domains..."

                    # Detect if container is using containerized nginx (on openwebui-network)
                    container_network=$(docker inspect "$container_name" --format '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' 2>/dev/null)
                    network_name=$(docker network inspect "$container_network" --format '{{.Name}}' 2>/dev/null)

                    is_containerized=false
                    if [[ "$network_name" == "openwebui-network" ]]; then
                        is_containerized=true
                        echo "✓ Detected containerized nginx deployment"
                    fi

                    # Get current container configuration BEFORE stopping
                    redirect_uri=$(docker exec "$container_name" env 2>/dev/null | grep "GOOGLE_REDIRECT_URI=" | cut -d'=' -f2- 2>/dev/null || echo "")
                    webui_name=$(docker exec "$container_name" env 2>/dev/null | grep "WEBUI_NAME=" | cut -d'=' -f2- 2>/dev/null || echo "QuantaBase - $client_name")
                    webui_secret_key=$(docker exec "$container_name" env 2>/dev/null | grep "WEBUI_SECRET_KEY=" | cut -d'=' -f2- 2>/dev/null)
                    fqdn=$(docker exec "$container_name" env 2>/dev/null | grep "FQDN=" | cut -d'=' -f2- 2>/dev/null || echo "")

                    # Generate new secret key if not found
                    if [[ -z "$webui_secret_key" ]]; then
                        echo "⚠️  Generating new WEBUI_SECRET_KEY (missing from current container)"
                        webui_secret_key=$(openssl rand -base64 32)
                    fi

                    if [[ -z "$redirect_uri" ]]; then
                        echo "❌ Could not retrieve container configuration. Please recreate manually."
                        echo "Press Enter to continue..."
                        read
                        continue
                    fi

                    # Get port only for host nginx deployments
                    port=""
                    if [[ "$is_containerized" == false ]]; then
                        port=$(docker ps -a --filter "name=$container_name" --format "{{.Ports}}" | grep -o '0.0.0.0:[0-9]*' | cut -d: -f2)

                        if [[ -z "$port" ]]; then
                            echo "❌ Could not retrieve port configuration. Please recreate manually."
                            echo "Press Enter to continue..."
                            read
                            continue
                        fi

                        echo "Current configuration:"
                        echo "  Port: $port"
                        echo "  Redirect URI: $redirect_uri"
                        echo "  WebUI Name: $webui_name"
                        echo
                    else
                        echo "Current configuration:"
                        echo "  Network: openwebui-network"
                        echo "  Redirect URI: $redirect_uri"
                        echo "  WebUI Name: $webui_name"
                        echo
                    fi

                    # Stop and remove old container (preserve volume)
                    echo "Stopping container..."
                    docker stop "$container_name" 2>/dev/null
                    echo "Removing old container..."
                    docker rm "$container_name" 2>/dev/null

                    # Recreate container with new domains
                    echo "Creating new container with updated domains..."

                    # Extract CLIENT_ID from container name for Phase 1 bind mounts
                    local client_id="${container_name#openwebui-}"
                    local client_dir="/opt/openwebui/${client_id}"
                    volume_name="${container_name}-data"

                    # Build docker run command based on deployment type
                    if [[ "$is_containerized" == true ]]; then
                        # Containerized nginx - use network, no port mapping
                        # Extract WEBUI_URL from redirect_uri (remove /oauth/google/callback)
                        local webui_url="${redirect_uri%/oauth/google/callback}"

                        docker run -d \
                            --name "$container_name" \
                            --network openwebui-network \
                            -e GOOGLE_CLIENT_ID=1063776054060-2fa0vn14b7ahi1tmfk49cuio44goosc1.apps.googleusercontent.com \
                            -e GOOGLE_CLIENT_SECRET=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 \
                            -e GOOGLE_REDIRECT_URI="$redirect_uri" \
                            -e ENABLE_OAUTH_SIGNUP=true \
                            -e OAUTH_ALLOWED_DOMAINS="$new_domains" \
                            -e OPENID_PROVIDER_URL=https://accounts.google.com/.well-known/openid-configuration \
                            -e WEBUI_NAME="$webui_name" \
                            -e WEBUI_SECRET_KEY="$webui_secret_key" \
                            -e WEBUI_URL="$webui_url" \
                            -e WEBUI_BASE_URL="$webui_url" \
                            -e ENABLE_VERSION_UPDATE_CHECK=false \
                            -e USER_PERMISSIONS_CHAT_CONTROLS=false \
                            -e FQDN="$fqdn" \
                            -e CLIENT_NAME="$client_name" \
                            -v "${client_dir}/data:/app/backend/data" \
                            -v "${client_dir}/static:/app/backend/open_webui/static" \
                            --restart unless-stopped \
                            ghcr.io/imagicrafter/open-webui@sha256:bdf98b7bf21c32db09522d90f80715af668b2bd8c58cf9d02777940773ab7b27
                    else
                        # Host nginx - use port mapping
                        # Extract WEBUI_URL from redirect_uri (remove /oauth/google/callback)
                        local webui_url="${redirect_uri%/oauth/google/callback}"

                        docker run -d \
                            --name "$container_name" \
                            -p "${port}:8080" \
                            -e GOOGLE_CLIENT_ID=1063776054060-2fa0vn14b7ahi1tmfk49cuio44goosc1.apps.googleusercontent.com \
                            -e GOOGLE_CLIENT_SECRET=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 \
                            -e GOOGLE_REDIRECT_URI="$redirect_uri" \
                            -e ENABLE_OAUTH_SIGNUP=true \
                            -e OAUTH_ALLOWED_DOMAINS="$new_domains" \
                            -e OPENID_PROVIDER_URL=https://accounts.google.com/.well-known/openid-configuration \
                            -e WEBUI_NAME="$webui_name" \
                            -e WEBUI_SECRET_KEY="$webui_secret_key" \
                            -e WEBUI_URL="$webui_url" \
                            -e WEBUI_BASE_URL="$webui_url" \
                            -e ENABLE_VERSION_UPDATE_CHECK=false \
                            -e USER_PERMISSIONS_CHAT_CONTROLS=false \
                            -e FQDN="$fqdn" \
                            -e CLIENT_NAME="$client_name" \
                            -v "${client_dir}/data:/app/backend/data" \
                            -v "${client_dir}/static:/app/backend/open_webui/static" \
                            --restart unless-stopped \
                            ghcr.io/imagicrafter/open-webui@sha256:bdf98b7bf21c32db09522d90f80715af668b2bd8c58cf9d02777940773ab7b27
                    fi

                    if [ $? -eq 0 ]; then
                        echo "✅ Container recreated successfully with new allowed domains!"
                        echo "New allowed domains: $new_domains"
                        if [[ -z "$(docker exec "$container_name" env 2>/dev/null | grep "WEBUI_SECRET_KEY=" | cut -d'=' -f2- 2>/dev/null)" ]]; then
                            echo "⚠️  Note: Added WEBUI_SECRET_KEY for OAuth session security"
                        fi
                    else
                        echo "❌ Failed to recreate container. Check Docker logs."
                    fi
                else
                    echo "Operation cancelled."
                fi

                echo "Press Enter to continue..."
                read
                ;;
            7)
                # Change domain/client while preserving data
                echo
                echo "╔════════════════════════════════════════╗"
                echo "║  Change Domain/Client (Preserve Data)  ║"
                echo "╚════════════════════════════════════════╝"
                echo

                # Get current configuration
                current_redirect_uri=$(docker exec "$container_name" env 2>/dev/null | grep "GOOGLE_REDIRECT_URI=" | cut -d'=' -f2- 2>/dev/null || echo "")
                current_webui_name=$(docker exec "$container_name" env 2>/dev/null | grep "WEBUI_NAME=" | cut -d'=' -f2- 2>/dev/null || echo "")
                current_port=$(docker ps -a --filter "name=$container_name" --format "{{.Ports}}" | grep -o '0.0.0.0:[0-9]*' | cut -d: -f2)

                if [[ -n "$current_redirect_uri" ]]; then
                    current_domain=$(echo "$current_redirect_uri" | sed -E 's|https?://||' | sed 's|/oauth/google/callback||')
                    echo "Current domain: $current_domain"
                else
                    echo "Current domain: Unable to determine"
                fi
                echo "Current port: $current_port"
                echo "Current WebUI name: $current_webui_name"
                echo

                # Get new client name
                echo -n "Enter new client name (lowercase, no spaces): "
                read new_client_name

                if [[ ! "$new_client_name" =~ ^[a-z0-9-]+$ ]]; then
                    echo "❌ Invalid client name. Use only lowercase letters, numbers, and hyphens."
                    echo "Press Enter to continue..."
                    read
                    continue
                fi

                # Check if new client name conflicts with existing deployments
                if docker ps -a --filter "name=openwebui-${new_client_name}" --format "{{.Names}}" | grep -q "openwebui-${new_client_name}"; then
                    echo "❌ Client '${new_client_name}' already exists!"
                    echo "Press Enter to continue..."
                    read
                    continue
                fi

                # Get new domain
                default_domain="${new_client_name}.quantabase.io"
                echo -n "Enter new domain (press Enter for '${default_domain}'): "
                read new_domain

                if [[ -z "$new_domain" ]]; then
                    new_domain="$default_domain"
                fi

                # Set new redirect URI based on domain type
                if [[ "$new_domain" == localhost* ]] || [[ "$new_domain" == 127.0.0.1* ]]; then
                    new_redirect_uri="http://${new_domain}/oauth/google/callback"
                    environment="development"
                else
                    new_redirect_uri="https://${new_domain}/oauth/google/callback"
                    environment="production"
                fi

                new_webui_name="QuantaBase - ${new_client_name}"

                echo
                echo "╔════════════════════════════════════════╗"
                echo "║            Change Summary              ║"
                echo "╚════════════════════════════════════════╝"
                echo "Old client: $client_name"
                echo "New client: $new_client_name"
                echo "Old domain: $current_domain"
                echo "New domain: $new_domain"
                echo "New redirect URI: $new_redirect_uri"
                echo "New WebUI name: $new_webui_name"
                echo "Port: $current_port (unchanged)"
                echo
                echo "⚠️  IMPORTANT: After this change you will need to:"
                echo "   1. Update nginx configuration for the new domain"
                echo "   2. Update Google OAuth redirect URI"
                echo "   3. Configure DNS for the new domain"
                echo
                echo "⚠️  This will:"
                echo "   - Rename the container to: openwebui-${new_client_name}"
                echo "   - Rename the volume to: openwebui-${new_client_name}-data"
                echo "   - Preserve ALL chat data and settings"
                echo "   - Remove old nginx configs (you'll need to recreate)"
                echo
                echo -n "Continue with domain/client change? (y/N): "
                read confirm

                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    echo
                    echo "Changing domain/client..."

                    # Get current allowed domains
                    current_allowed_domains=$(docker exec "$container_name" env 2>/dev/null | grep "OAUTH_ALLOWED_DOMAINS=" | cut -d'=' -f2- 2>/dev/null || echo "martins.net")

                    # Stop and remove old container
                    echo "Stopping old container..."
                    docker stop "$container_name" 2>/dev/null
                    echo "Removing old container..."
                    docker rm "$container_name" 2>/dev/null

                    # Calculate new FQDN and container/volume names
                    local new_fqdn=$(echo "$new_redirect_uri" | sed -E 's|https?://||' | sed 's|/oauth/google/callback||')
                    local sanitized_new_fqdn=$(echo "$new_fqdn" | sed 's/\./-/g' | sed 's/:/-/g')

                    # Phase 1: Use client directories instead of Docker volumes
                    local old_client_id="${container_name#openwebui-}"
                    local old_client_dir="/opt/openwebui/${old_client_id}"
                    local new_client_id="${sanitized_new_fqdn}"
                    local new_client_dir="/opt/openwebui/${new_client_id}"

                    new_container_name="openwebui-${sanitized_new_fqdn}"

                    echo "Moving client directories..."
                    # Move/rename client directory
                    if [ -d "$old_client_dir" ]; then
                        if [ -d "$new_client_dir" ]; then
                            echo "❌ Target directory $new_client_dir already exists. Operation cancelled."
                            echo "Press Enter to continue..."
                            read
                            continue
                        fi
                        mv "$old_client_dir" "$new_client_dir"
                        if [ $? -eq 0 ]; then
                            echo "✅ Client directories moved successfully"
                        else
                            echo "❌ Failed to move directories. Operation cancelled."
                            echo "Press Enter to continue..."
                            read
                            continue
                        fi
                    else
                        echo "⚠️  Old client directory not found. Creating new directories..."
                        mkdir -p "${new_client_dir}/data" "${new_client_dir}/static"
                    fi

                    # Create new container with new name and domain
                    echo "Creating new container: $new_container_name"

                    # Calculate base URL from redirect URI
                    local new_base_url="${new_redirect_uri%/oauth/google/callback}"

                    # Use OPENWEBUI_IMAGE_TAG environment variable, default to 'main'
                    local IMAGE_TAG=${OPENWEBUI_IMAGE_TAG:-main}

                    docker run -d \
                        --name "$new_container_name" \
                        -p "${current_port}:8080" \
                        -e GOOGLE_CLIENT_ID=1063776054060-2fa0vn14b7ahi1tmfk49cuio44goosc1.apps.googleusercontent.com \
                        -e GOOGLE_CLIENT_SECRET=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 \
                        -e GOOGLE_REDIRECT_URI="$new_redirect_uri" \
                        -e ENABLE_OAUTH_SIGNUP=true \
                        -e OAUTH_ALLOWED_DOMAINS="$current_allowed_domains" \
                        -e OPENID_PROVIDER_URL=https://accounts.google.com/.well-known/openid-configuration \
                        -e WEBUI_NAME="$new_webui_name" \
                        -e WEBUI_URL="$new_base_url" \
                        -e WEBUI_BASE_URL="$new_base_url" \
                        -e USER_PERMISSIONS_CHAT_CONTROLS=false \
                        -e FQDN="$new_fqdn" \
                        -e CLIENT_NAME="$new_client_name" \
                        -v "${new_client_dir}/data:/app/backend/data" \
                        -v "${new_client_dir}/static:/app/backend/open_webui/static" \
                        --restart unless-stopped \
                        ghcr.io/imagicrafter/open-webui:${IMAGE_TAG}

                    if [ $? -eq 0 ]; then
                        echo "✅ Container recreated successfully!"
                        echo
                        echo "╔════════════════════════════════════════╗"
                        echo "║             Next Steps                 ║"
                        echo "╚════════════════════════════════════════╝"
                        echo "1. Generate new nginx config:"
                        echo "   Use option 4 (Generate nginx Configuration)"
                        echo
                        echo "2. Update Google OAuth Console:"
                        echo "   New redirect URI: $new_redirect_uri"
                        echo
                        echo "3. Configure DNS:"
                        echo "   Point $new_domain to this server"
                        echo
                        echo "4. Remove old nginx config if it exists:"
                        echo "   sudo rm /etc/nginx/sites-enabled/$current_domain"
                        echo "   sudo rm /etc/nginx/sites-available/$current_domain"
                        echo
                        echo "The deployment is now accessible as '$new_client_name' in the menu."
                        echo "All your chat data and settings have been preserved!"

                        # Since we changed the client name, we need to exit this menu
                        # as the container name has changed
                        echo
                        echo "Press Enter to return to main menu..."
                        read
                        return
                    else
                        echo "❌ Failed to create new container. Check Docker logs."
                    fi
                else
                    echo "Domain/client change cancelled."
                fi

                echo "Press Enter to continue..."
                read
                ;;
            8)
                # Sync Management
                sync_management_menu "$container_name"
                ;;
            9)
                # Database Migration / Configuration Viewer
                if [[ -n "$database_url" ]]; then
                    # PostgreSQL - Show configuration
                    clear
                    source "${SCRIPT_DIR}/DB_MIGRATION/db-migration-helper.sh"
                    display_postgres_config "$container_name"
                else
                    # SQLite - Offer migration
                    clear
                    echo "╔════════════════════════════════════════╗"
                    echo "║     Migrate to Supabase/PostgreSQL     ║"
                    echo "╚════════════════════════════════════════╝"
                    echo
                    echo "⚠️  WARNING: Database migration is a critical operation"
                    echo
                    echo "What will happen:"
                    echo "  1. Backup your current SQLite database"
                    echo "  2. Initialize PostgreSQL schema on Supabase"
                    echo "  3. Migrate all data to PostgreSQL"
                    echo "  4. Recreate container with PostgreSQL configuration"
                    echo
                    echo "Requirements:"
                    echo "  - Supabase account and project set up"
                    echo "  - pgvector extension enabled (recommended)"
                    echo "  - Stable internet connection"
                    echo
                    echo "Estimated time: 15-30 minutes"
                    echo "The service will be temporarily unavailable during migration"
                    echo
                    echo -n "Continue with migration? (y/N): "
                    read confirm

                    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                        echo "Migration cancelled."
                        echo "Press Enter to continue..."
                        read
                        continue
                    fi

                    # Source the helper script
                    source "${SCRIPT_DIR}/DB_MIGRATION/db-migration-helper.sh"

                    # Step 1: Get Supabase configuration
                    clear
                    if ! get_supabase_config; then
                        echo
                        echo "❌ Failed to configure Supabase connection"
                        echo "Press Enter to continue..."
                        read
                        continue
                    fi

                    # Step 2: Test connection
                    clear
                    if ! test_supabase_connection "$DATABASE_URL"; then
                        echo
                        echo "❌ Cannot connect to Supabase. Please check your credentials."
                        echo "Press Enter to continue..."
                        read
                        continue
                    fi

                    # Step 3: Check pgvector extension
                    clear
                    if ! check_pgvector_extension "$DATABASE_URL"; then
                        echo "Migration cancelled."
                        echo "Press Enter to continue..."
                        read
                        continue
                    fi

                    # Step 4: Backup SQLite database
                    clear
                    # Use FQDN for backup naming, fall back to client_name if not available
                    local backup_identifier="${fqdn:-$client_name}"
                    backup_path=$(backup_sqlite_database "$container_name" "$backup_identifier")

                    if [[ -z "$backup_path" ]]; then
                        echo
                        echo "❌ Failed to create backup. Migration aborted."
                        echo "Press Enter to continue..."
                        read
                        continue
                    fi

                    # Step 5: Get port for initialization
                    current_port=$(echo "$ports" | grep -o '0.0.0.0:[0-9]*' | head -1 | cut -d: -f2)
                    if [[ -z "$current_port" ]]; then
                        current_port=8080
                    fi

                    # Step 6: Initialize PostgreSQL schema
                    clear
                    if ! initialize_postgresql_schema "$container_name" "$DATABASE_URL" "$current_port"; then
                        echo
                        echo "❌ Failed to initialize PostgreSQL schema. Migration aborted."
                        echo "Press Enter to continue..."
                        read
                        continue
                    fi

                    # Step 7: Run migration tool
                    clear
                    echo "╔════════════════════════════════════════╗"
                    echo "║        Running Migration Tool          ║"
                    echo "╚════════════════════════════════════════╝"
                    echo
                    echo "The migration tool will now run interactively."
                    echo "When prompted for the SQLite database path, enter:"
                    echo "  $backup_path"
                    echo
                    echo "Press Enter to start migration..."
                    read

                    # Use FQDN for log file naming, fall back to client_name if not available
                    local migration_identifier="${fqdn:-$client_name}"

                    if ! run_migration_tool "$backup_path" "$DATABASE_URL" "$migration_identifier"; then
                        echo
                        echo "❌ Migration failed. Starting rollback..."
                        rollback_to_sqlite "$client_name" "$backup_path" "$current_port"
                        echo
                        echo "Press Enter to continue..."
                        read
                        continue
                    fi

                    # Step 8: Fix null byte issue
                    clear
                    fix_null_bytes "$DATABASE_URL"

                    # Step 9: Recreate container with PostgreSQL
                    clear
                    if ! recreate_container_with_postgres "$client_name" "$DATABASE_URL" "$current_port"; then
                        echo
                        echo "❌ Failed to recreate container. Starting rollback..."
                        rollback_to_sqlite "$client_name" "$backup_path" "$current_port"
                        echo
                        echo "Press Enter to continue..."
                        read
                        continue
                    fi

                    # Step 10: Success message
                    clear
                    echo "╔════════════════════════════════════════╗"
                    echo "║     Migration Completed Successfully!  ║"
                    echo "╚════════════════════════════════════════╝"
                    echo
                    echo "✅ Your deployment is now using PostgreSQL/Supabase"
                    echo
                    echo "Next steps:"
                    echo "  1. Test web access: http://localhost:$current_port"
                    echo "  2. Verify chat history and user data"
                    echo "  3. Monitor container logs for any errors"
                    echo "  4. SQLite backup saved at: $backup_path"
                    echo "  5. Keep backup for 2-4 weeks before deleting"
                    echo
                    echo "If you encounter any issues, you can rollback to SQLite"
                    echo "by using option 8 again and selecting rollback."
                fi

                echo
                echo "Press Enter to continue..."
                read
                ;;
            10)
                # User Management
                show_user_management "$container_name"
                ;;
            11)
                # Asset Management
                show_asset_management "$container_name" "$fqdn"
                ;;
            12)
                # Remove deployment
                echo "⚠️  WARNING: This will permanently remove the deployment!"
                echo "Data volume will be preserved but container will be deleted."
                echo -n "Type 'DELETE' to confirm: "
                read confirm
                if [ "$confirm" = "DELETE" ]; then
                    echo "Removing $container_name..."
                    docker stop "$container_name" 2>/dev/null
                    docker rm "$container_name"
                    echo "Deployment removed. Data volume preserved."
                    echo "Press Enter to continue..."
                    read
                    return
                else
                    echo "Removal cancelled."
                    echo "Press Enter to continue..."
                    read
                fi
                ;;
            13)
                # Return to deployment list
                return
                ;;
            *)
                echo "Invalid selection. Press Enter to continue..."
                read
                ;;
        esac
    done
}

show_user_management() {
    local container_name="$1"
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup/scripts"

    while true; do
        clear
        echo "╔════════════════════════════════════════╗"
        echo "║          User Management               ║"
        echo "╚════════════════════════════════════════╝"
        echo
        echo "Container: $container_name"
        echo
        echo "⚠️  Admin-only: Authorized client support use"
        echo
        echo "1) Promote Primary Admin"
        echo "2) Promote Admin"
        echo "3) Demote Admin"
        echo "4) Approve User"
        echo "5) Delete User"
        echo "6) Return to deployment menu"
        echo
        echo -n "Select action (1-6): "
        read action

        case "$action" in
            1)
                user_promote_primary_admin "$container_name" "$SCRIPT_DIR"
                ;;
            2)
                user_promote_admin "$container_name" "$SCRIPT_DIR"
                ;;
            3)
                user_demote_admin "$container_name" "$SCRIPT_DIR"
                ;;
            4)
                user_approve "$container_name" "$SCRIPT_DIR"
                ;;
            5)
                user_delete "$container_name" "$SCRIPT_DIR"
                ;;
            6)
                return
                ;;
            *)
                echo "Invalid selection. Press Enter to continue..."
                read
                ;;
        esac
    done
}

user_promote_primary_admin() {
    local container_name="$1"
    local script_dir="$2"
    local page=0
    local per_page=10

    while true; do
        clear
        echo "╔════════════════════════════════════════╗"
        echo "║      Promote Primary Admin             ║"
        echo "╚════════════════════════════════════════╝"
        echo
        echo "Select admin to make primary admin:"
        echo "(Primary admin is listed first)"
        echo

        # Get admin users
        local users_json=$(bash "$script_dir/user-list.sh" "$container_name" "admin" 2>/dev/null)
        if [ -z "$users_json" ] || [ "$users_json" = "[]" ]; then
            echo "No admin users found."
            echo
            echo "Press Enter to return..."
            read
            return
        fi

        # Parse JSON and display paginated list
        local emails=($(echo "$users_json" | jq -r '.[].email'))
        local total=${#emails[@]}
        local start=$((page * per_page))
        local end=$((start + per_page))

        if [ $end -gt $total ]; then
            end=$total
        fi

        local display_num=1
        for ((i=start; i<end; i++)); do
            local email="${emails[$i]}"
            if [ $i -eq 0 ]; then
                echo "$display_num) $email ⭐ PRIMARY"
            else
                echo "$display_num) $email"
            fi
            display_num=$((display_num + 1))
        done

        echo
        if [ $end -lt $total ]; then
            echo "N) Next page"
        fi
        if [ $page -gt 0 ]; then
            echo "P) Previous page"
        fi
        echo "R) Return"
        echo
        echo -n "Selection: "
        read selection

        case "$selection" in
            [Nn])
                if [ $end -lt $total ]; then
                    page=$((page + 1))
                fi
                ;;
            [Pp])
                if [ $page -gt 0 ]; then
                    page=$((page - 1))
                fi
                ;;
            [Rr])
                return
                ;;
            [0-9]|[0-9][0-9])
                local idx=$((start + selection - 1))
                if [ $selection -ge 1 ] && [ $selection -le $((end - start)) ]; then
                    local selected_email="${emails[$idx]}"
                    echo
                    echo "Promoting $selected_email to primary admin..."
                    if bash "$script_dir/user-promote-primary.sh" "$container_name" "$selected_email"; then
                        echo
                        echo "Press Enter to continue..."
                        read
                        return
                    else
                        echo "Failed to promote user."
                        echo "Press Enter to continue..."
                        read
                    fi
                else
                    echo "Invalid selection."
                    sleep 1
                fi
                ;;
            *)
                echo "Invalid input."
                sleep 1
                ;;
        esac
    done
}

user_promote_admin() {
    local container_name="$1"
    local script_dir="$2"
    local page=0
    local per_page=10

    while true; do
        clear
        echo "╔════════════════════════════════════════╗"
        echo "║           Promote Admin                ║"
        echo "╚════════════════════════════════════════╝"
        echo
        echo "Select user to promote to admin:"
        echo

        # Get non-admin users (regular users and approved pending)
        local users_json=$(bash "$script_dir/user-list.sh" "$container_name" "user" 2>/dev/null)
        if [ -z "$users_json" ] || [ "$users_json" = "[]" ]; then
            echo "No non-admin users found."
            echo
            echo "Press Enter to return..."
            read
            return
        fi

        # Parse JSON and display paginated list
        local emails=($(echo "$users_json" | jq -r '.[].email'))
        local total=${#emails[@]}
        local start=$((page * per_page))
        local end=$((start + per_page))

        if [ $end -gt $total ]; then
            end=$total
        fi

        local display_num=1
        for ((i=start; i<end; i++)); do
            echo "$display_num) ${emails[$i]}"
            display_num=$((display_num + 1))
        done

        echo
        if [ $end -lt $total ]; then
            echo "N) Next page"
        fi
        if [ $page -gt 0 ]; then
            echo "P) Previous page"
        fi
        echo "R) Return"
        echo
        echo -n "Selection: "
        read selection

        case "$selection" in
            [Nn])
                if [ $end -lt $total ]; then
                    page=$((page + 1))
                fi
                ;;
            [Pp])
                if [ $page -gt 0 ]; then
                    page=$((page - 1))
                fi
                ;;
            [Rr])
                return
                ;;
            [0-9]|[0-9][0-9])
                local idx=$((start + selection - 1))
                if [ $selection -ge 1 ] && [ $selection -le $((end - start)) ]; then
                    local selected_email="${emails[$idx]}"
                    echo
                    echo "Promoting $selected_email to admin..."
                    if bash "$script_dir/user-promote-admin.sh" "$container_name" "$selected_email"; then
                        echo
                        echo "Press Enter to continue..."
                        read
                        return
                    else
                        echo "Failed to promote user."
                        echo "Press Enter to continue..."
                        read
                    fi
                else
                    echo "Invalid selection."
                    sleep 1
                fi
                ;;
            *)
                echo "Invalid input."
                sleep 1
                ;;
        esac
    done
}

user_demote_admin() {
    local container_name="$1"
    local script_dir="$2"
    local page=0
    local per_page=10

    while true; do
        clear
        echo "╔════════════════════════════════════════╗"
        echo "║           Demote Admin                 ║"
        echo "╚════════════════════════════════════════╝"
        echo
        echo "Select admin to demote to user:"
        echo "(Primary admin cannot be demoted)"
        echo

        # Get admin users
        local users_json=$(bash "$script_dir/user-list.sh" "$container_name" "admin" 2>/dev/null)
        if [ -z "$users_json" ] || [ "$users_json" = "[]" ]; then
            echo "No admin users found."
            echo
            echo "Press Enter to return..."
            read
            return
        fi

        # Parse JSON and filter out primary (first admin)
        local all_emails=($(echo "$users_json" | jq -r '.[].email'))
        local emails=("${all_emails[@]:1}")  # Skip first (primary)

        if [ ${#emails[@]} -eq 0 ]; then
            echo "No secondary admins found."
            echo "(Primary admin cannot be demoted)"
            echo
            echo "Press Enter to return..."
            read
            return
        fi

        local total=${#emails[@]}
        local start=$((page * per_page))
        local end=$((start + per_page))

        if [ $end -gt $total ]; then
            end=$total
        fi

        local display_num=1
        for ((i=start; i<end; i++)); do
            echo "$display_num) ${emails[$i]}"
            display_num=$((display_num + 1))
        done

        echo
        if [ $end -lt $total ]; then
            echo "N) Next page"
        fi
        if [ $page -gt 0 ]; then
            echo "P) Previous page"
        fi
        echo "R) Return"
        echo
        echo -n "Selection: "
        read selection

        case "$selection" in
            [Nn])
                if [ $end -lt $total ]; then
                    page=$((page + 1))
                fi
                ;;
            [Pp])
                if [ $page -gt 0 ]; then
                    page=$((page - 1))
                fi
                ;;
            [Rr])
                return
                ;;
            [0-9]|[0-9][0-9])
                local idx=$((start + selection - 1))
                if [ $selection -ge 1 ] && [ $selection -le $((end - start)) ]; then
                    local selected_email="${emails[$idx]}"
                    echo
                    echo "Demoting $selected_email to user..."
                    if bash "$script_dir/user-demote-admin.sh" "$container_name" "$selected_email"; then
                        echo
                        echo "Press Enter to continue..."
                        read
                        return
                    else
                        echo "Failed to demote user."
                        echo "Press Enter to continue..."
                        read
                    fi
                else
                    echo "Invalid selection."
                    sleep 1
                fi
                ;;
            *)
                echo "Invalid input."
                sleep 1
                ;;
        esac
    done
}

user_approve() {
    local container_name="$1"
    local script_dir="$2"
    local page=0
    local per_page=10

    while true; do
        clear
        echo "╔════════════════════════════════════════╗"
        echo "║           Approve User                 ║"
        echo "╚════════════════════════════════════════╝"
        echo
        echo "Select pending user to approve:"
        echo

        # Get pending users
        local users_json=$(bash "$script_dir/user-list.sh" "$container_name" "pending" 2>/dev/null)
        if [ -z "$users_json" ] || [ "$users_json" = "[]" ]; then
            echo "No pending users found."
            echo
            echo "Press Enter to return..."
            read
            return
        fi

        # Parse JSON and display paginated list
        local emails=($(echo "$users_json" | jq -r '.[].email'))
        local total=${#emails[@]}
        local start=$((page * per_page))
        local end=$((start + per_page))

        if [ $end -gt $total ]; then
            end=$total
        fi

        local display_num=1
        for ((i=start; i<end; i++)); do
            echo "$display_num) ${emails[$i]}"
            display_num=$((display_num + 1))
        done

        echo
        if [ $end -lt $total ]; then
            echo "N) Next page"
        fi
        if [ $page -gt 0 ]; then
            echo "P) Previous page"
        fi
        echo "R) Return"
        echo
        echo -n "Selection: "
        read selection

        case "$selection" in
            [Nn])
                if [ $end -lt $total ]; then
                    page=$((page + 1))
                fi
                ;;
            [Pp])
                if [ $page -gt 0 ]; then
                    page=$((page - 1))
                fi
                ;;
            [Rr])
                return
                ;;
            [0-9]|[0-9][0-9])
                local idx=$((start + selection - 1))
                if [ $selection -ge 1 ] && [ $selection -le $((end - start)) ]; then
                    local selected_email="${emails[$idx]}"
                    echo
                    echo "Approving $selected_email..."
                    if bash "$script_dir/user-approve.sh" "$container_name" "$selected_email"; then
                        echo
                        echo "Press Enter to continue..."
                        read
                        return
                    else
                        echo "Failed to approve user."
                        echo "Press Enter to continue..."
                        read
                    fi
                else
                    echo "Invalid selection."
                    sleep 1
                fi
                ;;
            *)
                echo "Invalid input."
                sleep 1
                ;;
        esac
    done
}

user_delete() {
    local container_name="$1"
    local script_dir="$2"
    local page=0
    local per_page=10

    while true; do
        clear
        echo "╔════════════════════════════════════════╗"
        echo "║           Delete User                  ║"
        echo "╚════════════════════════════════════════╝"
        echo
        echo "⚠️  WARNING: This action is PERMANENT and will delete:"
        echo "   - User account and profile"
        echo "   - All chat history"
        echo "   - All files and folders"
        echo "   - All memories and feedbacks"
        echo "   - OAuth sessions"
        echo "   - Group memberships"
        echo
        echo "Select user to delete:"
        echo "(Primary admin cannot be deleted)"
        echo

        # Get all users except primary admin
        local users_json=$(bash "$script_dir/user-list.sh" "$container_name" "all" 2>/dev/null)
        if [ -z "$users_json" ] || [ "$users_json" = "[]" ]; then
            echo "No users found."
            echo
            echo "Press Enter to return..."
            read
            return
        fi

        # Parse JSON and find primary admin
        local all_users=$(echo "$users_json" | jq -r 'sort_by(.created_at) | .[].email' 2>/dev/null)
        local all_roles=$(echo "$users_json" | jq -r 'sort_by(.created_at) | .[].role' 2>/dev/null)
        local all_created=$(echo "$users_json" | jq -r 'sort_by(.created_at) | .[].created_at' 2>/dev/null)

        # Convert to arrays
        local emails=($(echo "$all_users"))
        local roles=($(echo "$all_roles"))
        local created_ats=($(echo "$all_created"))

        # Find primary admin (earliest admin)
        local primary_admin_email=""
        local min_admin_timestamp=""
        for i in "${!emails[@]}"; do
            if [ "${roles[$i]}" = "admin" ]; then
                if [ -z "$min_admin_timestamp" ] || [ "${created_ats[$i]}" -lt "$min_admin_timestamp" ]; then
                    min_admin_timestamp="${created_ats[$i]}"
                    primary_admin_email="${emails[$i]}"
                fi
            fi
        done

        # Build list of deleteable users (excluding primary admin)
        local deleteable_emails=()
        local deleteable_roles=()
        for i in "${!emails[@]}"; do
            if [ "${emails[$i]}" != "$primary_admin_email" ]; then
                deleteable_emails+=("${emails[$i]}")
                deleteable_roles+=("${roles[$i]}")
            fi
        done

        if [ ${#deleteable_emails[@]} -eq 0 ]; then
            echo "No users available to delete (only primary admin exists)."
            echo
            echo "Press Enter to return..."
            read
            return
        fi

        # Pagination
        local total=${#deleteable_emails[@]}
        local start=$((page * per_page))
        local end=$((start + per_page))

        if [ $end -gt $total ]; then
            end=$total
        fi

        # Display page
        local display_index=1
        for i in $(seq $start $((end - 1))); do
            echo "$display_index) ${deleteable_emails[$i]} (${deleteable_roles[$i]})"
            ((display_index++))
        done

        echo
        if [ $total -gt $per_page ]; then
            echo "Showing $(($start + 1))-$end of $total"
            if [ $page -gt 0 ]; then
                echo "p) Previous page"
            fi
            if [ $end -lt $total ]; then
                echo "n) Next page"
            fi
        fi
        echo "b) Back to User Management"
        echo
        echo -n "Select user number to delete: "
        read selection

        case "$selection" in
            b|B)
                return
                ;;
            n|N)
                if [ $end -lt $total ]; then
                    ((page++))
                else
                    echo "Already on last page."
                    sleep 1
                fi
                ;;
            p|P)
                if [ $page -gt 0 ]; then
                    ((page--))
                else
                    echo "Already on first page."
                    sleep 1
                fi
                ;;
            [0-9]*)
                if [ "$selection" -ge 1 ] && [ "$selection" -le $((end - start)) ]; then
                    local actual_index=$((start + selection - 1))
                    local selected_email="${deleteable_emails[$actual_index]}"
                    local selected_role="${deleteable_roles[$actual_index]}"

                    # Confirmation prompt
                    echo
                    echo "═══════════════════════════════════════"
                    echo "⚠️  FINAL CONFIRMATION ⚠️"
                    echo "═══════════════════════════════════════"
                    echo "You are about to PERMANENTLY DELETE:"
                    echo "  Email: $selected_email"
                    echo "  Role: $selected_role"
                    echo
                    echo "This will remove ALL data associated with this user."
                    echo
                    echo -n "Type the user's email to confirm deletion: "
                    read confirm_email

                    if [ "$confirm_email" = "$selected_email" ]; then
                        echo
                        echo "Deleting user..."
                        if bash "$script_dir/user-delete.sh" "$container_name" "$selected_email"; then
                            echo
                            echo "Press Enter to continue..."
                            read
                            return
                        else
                            echo
                            echo "Failed to delete user."
                            echo "Press Enter to continue..."
                            read
                        fi
                    else
                        echo
                        echo "Email did not match. Deletion cancelled."
                        echo "Press Enter to continue..."
                        read
                    fi
                else
                    echo "Invalid selection."
                    sleep 1
                fi
                ;;
            *)
                echo "Invalid input."
                sleep 1
                ;;
        esac
    done
}

show_asset_management() {
    local container_name="$1"
    local fqdn="$2"
    local ASSET_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup/scripts/asset_management"

    while true; do
        clear
        echo "╔════════════════════════════════════════╗"
        echo "║          Asset Management              ║"
        echo "╚════════════════════════════════════════╝"
        echo
        echo "Container: $container_name"
        if [[ -n "$fqdn" ]]; then
            echo "FQDN: $fqdn"
        fi
        echo
        # Get current WEBUI_NAME
        local current_webui_name=$(docker exec "$container_name" env 2>/dev/null | grep "WEBUI_NAME=" | cut -d'=' -f2- 2>/dev/null || echo "Not set")
        echo "Current Name: $current_webui_name"
        echo
        echo "⚠️  Logo changes: Container will restart (~15 seconds)"
        echo "⚠️  Name changes: Container will be recreated (preserves all data)"
        echo
        echo "1) Apply logo branding from URL"
        echo "2) Generate custom text logo (1-2 letters)"
        echo "3) Use default QuantaBase logo"
        echo "4) Update deployment name (WEBUI_NAME)"
        echo "5) Return to deployment menu"
        echo
        echo -n "Select action (1-5): "
        read action

        case "$action" in
            1)
                # Apply branding from URL
                clear
                echo "╔════════════════════════════════════════╗"
                echo "║       Apply Branding from URL          ║"
                echo "╚════════════════════════════════════════╝"
                echo

                # Check branding monitor service before proceeding
                if ! check_and_start_branding_monitor; then
                    echo
                    echo "Operation cancelled."
                    echo "Press Enter to continue..."
                    read
                    continue
                fi
                echo
                echo "Logo URL format:"
                echo "  https://8e7b926d-96e0-40e1-b4f0-45f653426723.quantabase.io/<domain>_logo.png"
                echo
                echo "Example:"
                echo "  Domain: chat.example.com"
                echo "  URL: https://8e7b926d-96e0-40e1-b4f0-45f653426723.quantabase.io/chat_example_com_logo.png"
                echo

                # Auto-generate URL from FQDN if available
                if [[ -n "$fqdn" ]]; then
                    # Convert dots to underscores for the URL
                    local suggested_filename=$(echo "$fqdn" | tr '.' '_')
                    local suggested_url="https://8e7b926d-96e0-40e1-b4f0-45f653426723.quantabase.io/${suggested_filename}_logo.png"
                    echo "Suggested URL based on FQDN:"
                    echo "  $suggested_url"
                    echo
                    echo "Press Enter to use this URL, or type a different URL:"
                    echo -n "Logo URL: "
                    read logo_url

                    # If empty, use the suggested URL
                    if [[ -z "$logo_url" ]]; then
                        logo_url="$suggested_url"
                        echo "Using suggested URL: $logo_url"
                    fi
                else
                    echo -n "Enter logo URL: "
                    read logo_url
                fi

                if [[ -z "$logo_url" ]]; then
                    echo "❌ No URL provided. Operation cancelled."
                    echo "Press Enter to continue..."
                    read
                    continue
                fi

                echo
                echo "Downloading and applying branding..."
                echo "This may take a moment..."
                echo

                # Detect if container uses Phase 1 bind mounts
                local client_id="${container_name#openwebui-}"
                local apply_mode="container"  # default to legacy mode

                if docker inspect "$container_name" --format '{{range .Mounts}}{{if eq .Destination "/app/backend/open_webui/static"}}true{{end}}{{end}}' 2>/dev/null | grep -q "true"; then
                    # Phase 1 container - use host mode with client_id
                    apply_mode="host"
                    target="$client_id"
                else
                    # Legacy container - use container mode
                    target="$container_name"
                fi

                # Call the apply-branding.sh script with appropriate mode
                if bash "$ASSET_SCRIPT_DIR/apply-branding.sh" "$target" "$logo_url" "$apply_mode"; then
                    echo
                    echo "✅ Branding applied successfully!"
                else
                    echo
                    echo "❌ Failed to apply branding."
                    echo "Please check:"
                    echo "  1. URL is correct and accessible"
                    echo "  2. Container is running"
                    echo "  3. ImageMagick is installed (sudo apt-get install imagemagick)"
                fi
                echo
                echo "Press Enter to continue..."
                read
                ;;
            2)
                # Generate custom text logo
                clear
                echo "╔════════════════════════════════════════╗"
                echo "║     Generate Custom Text Logo          ║"
                echo "╚════════════════════════════════════════╝"
                echo

                # Check branding monitor service before proceeding
                if ! check_and_start_branding_monitor; then
                    echo
                    echo "Operation cancelled."
                    echo "Press Enter to continue..."
                    read
                    continue
                fi

                echo "Create a custom logo from 1-2 letters."
                echo "Perfect for client initials or brand abbreviations."
                echo

                # Derive default text from FQDN or container name
                local default_text=""
                if [[ -n "$fqdn" ]]; then
                    # Extract first letters from domain parts
                    default_text=$(echo "$fqdn" | sed 's/\./ /g' | awk '{for(i=1;i<=2;i++) printf toupper(substr($i,1,1))}')
                fi
                if [[ -z "$default_text" ]]; then
                    default_text="OW"
                fi

                echo "Enter logo text (1-2 letters):"
                echo -n "Text [$default_text]: "
                read text_input
                text_input=${text_input:-$default_text}

                # Validate text length
                if [[ ${#text_input} -gt 2 ]]; then
                    echo "❌ Text must be 1-2 letters. Operation cancelled."
                    echo "Press Enter to continue..."
                    read
                    continue
                fi

                echo
                echo "Select font style:"
                echo "1) Helvetica-Bold (clean, modern)"
                echo "2) AvantGarde-Demi (geometric, professional)"
                echo "3) Bookman-Demi (serif, traditional)"
                echo "4) Courier-Bold (monospace, tech)"
                echo -n "Font [1]: "
                read font_choice
                font_choice=${font_choice:-1}

                local font=""
                case "$font_choice" in
                    1) font="Helvetica-Bold" ;;
                    2) font="AvantGarde-Demi" ;;
                    3) font="Bookman-Demi" ;;
                    4) font="Courier-Bold" ;;
                    *) font="Helvetica-Bold" ;;
                esac

                echo
                echo "Select background style:"
                echo "1) White circle on transparent"
                echo "2) Black circle on transparent"
                echo "3) No background (text only)"
                echo "4) Rounded square (white)"
                echo -n "Background [1]: "
                read bg_choice
                bg_choice=${bg_choice:-1}

                local bg_style=""
                local bg_color=""
                local text_color=""
                case "$bg_choice" in
                    1)
                        bg_style="circle"
                        bg_color="#FFFFFF"
                        text_color="#000000"
                        ;;
                    2)
                        bg_style="circle"
                        bg_color="#000000"
                        text_color="#FFFFFF"
                        ;;
                    3)
                        bg_style="none"
                        bg_color="none"
                        text_color="#000000"
                        ;;
                    4)
                        bg_style="rounded-square"
                        bg_color="#FFFFFF"
                        text_color="#000000"
                        ;;
                    *)
                        bg_style="circle"
                        bg_color="#FFFFFF"
                        text_color="#000000"
                        ;;
                esac

                echo
                echo "Summary:"
                echo "  Text: $text_input"
                echo "  Font: $font"
                echo "  Background: $bg_style ($bg_color)"
                echo "  Text color: $text_color"
                echo
                echo -n "Generate and apply logo? (Y/n): "
                read confirm

                if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
                    echo
                    echo "Generating custom text logo..."
                    echo

                    if bash "$ASSET_SCRIPT_DIR/generate-text-logo.sh" "$container_name" "$text_input" "$font" "$bg_style" "$bg_color" "$text_color"; then
                        echo
                        echo "✅ Custom text logo generated and applied successfully!"
                    else
                        echo
                        echo "❌ Failed to generate text logo."
                        echo "Please check:"
                        echo "  1. Container is running"
                        echo "  2. ImageMagick is installed (sudo apt-get install imagemagick)"
                    fi
                else
                    echo "Operation cancelled."
                fi
                echo
                echo "Press Enter to continue..."
                read
                ;;
            3)
                # Use default QuantaBase branding
                clear
                echo "╔════════════════════════════════════════╗"
                echo "║      Apply Default QuantaBase Branding ║"
                echo "╚════════════════════════════════════════╝"
                echo

                # Check branding monitor service before proceeding
                if ! check_and_start_branding_monitor; then
                    echo
                    echo "Operation cancelled."
                    echo "Press Enter to continue..."
                    read
                    continue
                fi

                echo "This will apply the default QuantaBase branding to the container."
                echo
                echo "Default logo URL:"
                echo "  https://8e7b926d-96e0-40e1-b4f0-45f653426723.quantabase.io/default_logo.png"
                echo
                echo -n "Continue? (y/N): "
                read confirm

                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    echo
                    echo "Applying default QuantaBase branding..."
                    echo

                    local default_logo_url="https://8e7b926d-96e0-40e1-b4f0-45f653426723.quantabase.io/default_logo.png"

                    # Detect if container uses Phase 1 bind mounts
                    local client_id="${container_name#openwebui-}"
                    local apply_mode="container"

                    if docker inspect "$container_name" --format '{{range .Mounts}}{{if eq .Destination "/app/backend/open_webui/static"}}true{{end}}{{end}}' 2>/dev/null | grep -q "true"; then
                        apply_mode="host"
                        target="$client_id"
                    else
                        target="$container_name"
                    fi

                    if bash "$ASSET_SCRIPT_DIR/apply-branding.sh" "$target" "$default_logo_url" "$apply_mode"; then
                        echo
                        echo "✅ Default branding applied successfully!"
                    else
                        echo
                        echo "❌ Failed to apply default branding."
                    fi
                else
                    echo "Operation cancelled."
                fi
                echo
                echo "Press Enter to continue..."
                read
                ;;
            4)
                # Update deployment name (WEBUI_NAME)
                clear
                echo "╔════════════════════════════════════════╗"
                echo "║       Update Deployment Name           ║"
                echo "╚════════════════════════════════════════╝"
                echo

                # Check branding monitor service before proceeding
                if ! check_and_start_branding_monitor; then
                    echo
                    echo "Operation cancelled."
                    echo "Press Enter to continue..."
                    read
                    continue
                fi

                echo "Current name: $current_webui_name"
                echo
                echo "⚠️  This will recreate the container with a new name."
                echo "    All data will be preserved (volumes are maintained)."
                echo
                echo "Enter new deployment name (or press Enter to cancel):"
                echo -n "New name: "
                read new_webui_name

                if [[ -z "$new_webui_name" ]]; then
                    echo "❌ No name provided. Operation cancelled."
                    echo "Press Enter to continue..."
                    read
                    continue
                fi

                echo
                echo "⚠️  Summary of changes:"
                echo "    Old name: $current_webui_name"
                echo "    New name: $new_webui_name"
                echo "    Container will be recreated (data preserved)"
                echo
                echo -n "Continue? (y/N): "
                read confirm

                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    echo
                    echo "Updating deployment name..."
                    echo

                    # Get all current environment variables from container
                    local google_client_id=$(docker exec "$container_name" env 2>/dev/null | grep "GOOGLE_CLIENT_ID=" | cut -d'=' -f2- 2>/dev/null || echo "")
                    local google_client_secret=$(docker exec "$container_name" env 2>/dev/null | grep "GOOGLE_CLIENT_SECRET=" | cut -d'=' -f2- 2>/dev/null || echo "")
                    local redirect_uri=$(docker exec "$container_name" env 2>/dev/null | grep "GOOGLE_REDIRECT_URI=" | cut -d'=' -f2- 2>/dev/null || echo "")
                    local oauth_domains=$(docker exec "$container_name" env 2>/dev/null | grep "OAUTH_ALLOWED_DOMAINS=" | cut -d'=' -f2- 2>/dev/null || echo "")
                    local webui_secret=$(docker exec "$container_name" env 2>/dev/null | grep "WEBUI_SECRET_KEY=" | cut -d'=' -f2- 2>/dev/null || echo "")
                    local webui_url=$(docker exec "$container_name" env 2>/dev/null | grep "WEBUI_URL=" | cut -d'=' -f2- 2>/dev/null || echo "")
                    local database_url=$(docker exec "$container_name" env 2>/dev/null | grep "DATABASE_URL=" | cut -d'=' -f2- 2>/dev/null || echo "")
                    local client_name_env=$(docker exec "$container_name" env 2>/dev/null | grep "CLIENT_NAME=" | cut -d'=' -f2- 2>/dev/null || echo "")

                    # Get port and network configuration
                    local ports=$(docker port "$container_name" 2>/dev/null)
                    local current_port=""
                    if [[ -n "$ports" ]]; then
                        current_port=$(echo "$ports" | grep -o '0.0.0.0:[0-9]*' | head -1 | cut -d: -f2)
                    fi

                    # Extract CLIENT_ID from container name (strip "openwebui-" prefix)
                    local client_id="${container_name#openwebui-}"
                    local client_dir="/opt/openwebui/${client_id}"

                    local volume_name="${container_name}-data"
                    local network_name=$(docker inspect "$container_name" --format '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' 2>/dev/null)
                    local network_name_str=$(docker network inspect "$network_name" --format '{{.Name}}' 2>/dev/null)

                    # Stop and remove container
                    echo "Stopping container..."
                    docker stop "$container_name" 2>/dev/null
                    docker rm "$container_name" 2>/dev/null

                    # Use OPENWEBUI_IMAGE_TAG environment variable
                    local image_tag="${OPENWEBUI_IMAGE_TAG:-main}"

                    # Build docker command
                    local docker_cmd="docker run -d --name ${container_name}"

                    # Add port mapping if exists
                    if [[ -n "$current_port" ]]; then
                        docker_cmd="$docker_cmd -p ${current_port}:8080"
                    fi

                    # Add network if exists
                    if [[ "$network_name_str" == "openwebui-network" ]]; then
                        docker_cmd="$docker_cmd --network openwebui-network"
                    fi

                    # Add environment variables
                    docker_cmd="$docker_cmd"
                    [[ -n "$google_client_id" ]] && docker_cmd="$docker_cmd -e GOOGLE_CLIENT_ID=\"$google_client_id\""
                    [[ -n "$google_client_secret" ]] && docker_cmd="$docker_cmd -e GOOGLE_CLIENT_SECRET=\"$google_client_secret\""
                    [[ -n "$redirect_uri" ]] && docker_cmd="$docker_cmd -e GOOGLE_REDIRECT_URI=\"$redirect_uri\""
                    [[ -n "$oauth_domains" ]] && docker_cmd="$docker_cmd -e OAUTH_ALLOWED_DOMAINS=\"$oauth_domains\""
                    docker_cmd="$docker_cmd -e ENABLE_OAUTH_SIGNUP=true"
                    docker_cmd="$docker_cmd -e OPENID_PROVIDER_URL=https://accounts.google.com/.well-known/openid-configuration"
                    docker_cmd="$docker_cmd -e WEBUI_NAME=\"$new_webui_name\""
                    [[ -n "$webui_secret" ]] && docker_cmd="$docker_cmd -e WEBUI_SECRET_KEY=\"$webui_secret\""
                    [[ -n "$webui_url" ]] && docker_cmd="$docker_cmd -e WEBUI_URL=\"$webui_url\""
                    [[ -n "$webui_url" ]] && docker_cmd="$docker_cmd -e WEBUI_BASE_URL=\"$webui_url\""
                    docker_cmd="$docker_cmd -e ENABLE_VERSION_UPDATE_CHECK=false"
                    docker_cmd="$docker_cmd -e USER_PERMISSIONS_CHAT_CONTROLS=false"
                    [[ -n "$fqdn" ]] && docker_cmd="$docker_cmd -e FQDN=\"$fqdn\""
                    [[ -n "$client_name_env" ]] && docker_cmd="$docker_cmd -e CLIENT_NAME=\"$client_name_env\""
                    [[ -n "$database_url" ]] && docker_cmd="$docker_cmd -e DATABASE_URL=\"$database_url\""

                    # Add Phase 1 bind mounts for data and static directories
                    docker_cmd="$docker_cmd -v ${client_dir}/data:/app/backend/data"
                    docker_cmd="$docker_cmd -v ${client_dir}/static:/app/backend/open_webui/static"
                    docker_cmd="$docker_cmd --restart unless-stopped"
                    docker_cmd="$docker_cmd ghcr.io/imagicrafter/open-webui:${image_tag}"

                    # Execute docker command
                    echo "Creating container with new name..."
                    eval "$docker_cmd"

                    if [ $? -eq 0 ]; then
                        echo
                        echo "✅ Deployment name updated successfully!"
                        echo "   New name: $new_webui_name"
                        echo
                        echo "ℹ️  Container recreated with Phase 1 bind mounts"
                        echo "   Custom logos preserved in: ${client_dir}/static/"
                        echo
                        echo "   Hard refresh browser to see name change"
                    else
                        echo
                        echo "❌ Failed to recreate container."
                        echo "   Check 'docker ps -a' for details"
                    fi
                else
                    echo "Operation cancelled."
                fi
                echo
                echo "Press Enter to continue..."
                read
                ;;
            5)
                # Return to deployment menu
                return
                ;;
            *)
                echo "Invalid selection. Press Enter to continue..."
                read
                ;;
        esac
    done
}

generate_nginx_config() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║      Generate nginx Configuration      ║"
    echo "╚════════════════════════════════════════╝"
    echo

    # List available clients (exclude sync nodes and nginx container)
    echo "Available deployments:"
    clients=($(docker ps -a --filter "name=openwebui-" --format "{{.Names}}" | grep -v "openwebui-sync-node-" | grep -v "^openwebui-nginx$"))

    if [ ${#clients[@]} -eq 0 ]; then
        echo "No deployments found. Create a deployment first."
        echo "Press Enter to continue..."
        read
        return
    fi

    for i in "${!clients[@]}"; do
        container_name="${clients[$i]}"
        ports=$(docker ps -a --filter "name=${container_name}" --format "{{.Ports}}" | grep -o '0.0.0.0:[0-9]*' | cut -d: -f2)

        # Try to get FQDN from container environment
        fqdn=$(docker exec "${container_name}" env 2>/dev/null | grep "^FQDN=" | cut -d'=' -f2- 2>/dev/null || echo "")

        # Fallback to extracting from GOOGLE_REDIRECT_URI
        if [[ -z "$fqdn" ]]; then
            redirect_uri=$(docker exec "${container_name}" env 2>/dev/null | grep "GOOGLE_REDIRECT_URI=" | cut -d'=' -f2- 2>/dev/null || echo "")
            if [[ -n "$redirect_uri" ]]; then
                fqdn=$(echo "$redirect_uri" | sed -E 's|https?://||' | sed 's|/oauth/google/callback||')
            fi
        fi

        # Check if nginx configuration exists (both host and containerized nginx)
        nginx_status="❌ Not configured"

        if [[ -n "$fqdn" ]]; then
            # Check containerized nginx first
            if [ -f "/opt/openwebui-nginx/conf.d/${fqdn}.conf" ]; then
                nginx_status="✅ Configured"
            # Check host nginx
            elif [ -f "/etc/nginx/sites-available/${fqdn}" ]; then
                nginx_status="✅ Configured"
            fi
        fi

        # Extract client_name for display
        client_name=$(docker exec "${container_name}" env 2>/dev/null | grep "^CLIENT_NAME=" | cut -d'=' -f2- 2>/dev/null || echo "")
        if [[ -z "$client_name" ]]; then
            client_name="${container_name#openwebui-}"
        fi

        if [[ -n "$fqdn" ]]; then
            echo "$((i+1))) $client_name → $fqdn (port: $ports) [$nginx_status]"
        else
            # Fallback if we can't get the FQDN
            echo "$((i+1))) $client_name (port: $ports) [$nginx_status]"
        fi
    done

    echo "$((${#clients[@]}+1))) Return to main menu"
    echo
    echo -n "Select client for nginx config (1-$((${#clients[@]}+1))): "
    read selection

    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -gt 0 ] && [ "$selection" -le ${#clients[@]} ]; then
        local container_name="${clients[$((selection-1))]}"
        local port=$(docker ps -a --filter "name=${container_name}" --format "{{.Ports}}" | grep -o '0.0.0.0:[0-9]*' | cut -d: -f2)

        # Extract client_name and FQDN for this container
        local client_name=$(docker exec "${container_name}" env 2>/dev/null | grep "^CLIENT_NAME=" | cut -d'=' -f2- 2>/dev/null || echo "")
        if [[ -z "$client_name" ]]; then
            client_name="${container_name#openwebui-}"
        fi

        local current_fqdn=$(docker exec "${container_name}" env 2>/dev/null | grep "^FQDN=" | cut -d'=' -f2- 2>/dev/null || echo "")
        if [[ -z "$current_fqdn" ]]; then
            local redirect_uri=$(docker exec "${container_name}" env 2>/dev/null | grep "GOOGLE_REDIRECT_URI=" | cut -d'=' -f2- 2>/dev/null || echo "")
            if [[ -n "$redirect_uri" ]]; then
                current_fqdn=$(echo "$redirect_uri" | sed -E 's|https?://||' | sed 's|/oauth/google/callback||')
            fi
        fi

        # Detect if nginx is containerized
        local nginx_containerized=false
        if docker ps --filter "name=openwebui-nginx" --format "{{.Names}}" | grep -q "^openwebui-nginx$"; then
            nginx_containerized=true
            echo -e "${GREEN}✓${NC} Detected containerized nginx"
        else
            echo "ℹ️  Using host nginx configuration"
        fi

        echo
        echo
        echo "Generating production nginx configuration..."
        echo "(HTTPS with Let's Encrypt SSL)"
        echo

        # Use current FQDN or default to client_name.quantabase.io
        if [[ -n "$current_fqdn" ]] && [[ "$current_fqdn" != localhost* ]]; then
            default_production_domain="$current_fqdn"
        else
            default_production_domain="${client_name}.quantabase.io"
        fi
        echo -n "Production domain (press Enter for '${default_production_domain}'): "
        read domain
        if [[ -z "$domain" ]]; then
            domain="$default_production_domain"
        fi

        # Choose template based on nginx type and SSL availability
        if [ "$nginx_containerized" = true ]; then
            # Check if SSL certs already exist for this domain
            if [ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]; then
                template_file="${SCRIPT_DIR}/nginx-container/nginx-template-containerized.conf"
                ssl_ready=true
            else
                template_file="${SCRIPT_DIR}/nginx-container/nginx-template-containerized-http-only.conf"
                ssl_ready=false
            fi
            config_file="/tmp/${domain}-nginx.conf"
            nginx_config_dest="/opt/openwebui-nginx/conf.d/${domain}.conf"
        else
            template_file="${SCRIPT_DIR}/nginx/templates/nginx-template-host.conf"
            config_file="/tmp/${domain}-nginx.conf"
            nginx_config_dest="/etc/nginx/sites-available/${domain}"
            ssl_ready=false
        fi
        setup_type="production"

        # Generate nginx config
        # Replace template variables (use different syntax for compatibility)
        if [ "$nginx_containerized" = true ]; then
            # For containerized nginx, use container name
            sed -e "s/\${CLIENT_NAME}/${client_name}/g" \
                -e "s/\${DOMAIN}/${domain}/g" \
                -e "s/\${CONTAINER_NAME}/${container_name}/g" \
                "$template_file" > "$config_file"
        else
            # For host nginx, use localhost:port
            sed -e "s/DOMAIN_PLACEHOLDER/${domain}/g" \
                -e "s/PORT_PLACEHOLDER/${port}/g" \
                "$template_file" > "$config_file"
        fi

        echo
        echo "✅ nginx configuration generated: $config_file"
        echo

        # Auto-deploy for containerized nginx
        if [ "$nginx_containerized" = true ] && [ "$setup_type" = "production" ]; then
            echo "╔════════════════════════════════════════╗"
            echo "║      Auto-Deploy Configuration         ║"
            echo "╚════════════════════════════════════════╝"
            echo
            echo "Detected containerized nginx - offering automated deployment"
            echo
            echo -n "Automatically deploy this configuration? (Y/n): "
            read auto_deploy

            if [[ "$auto_deploy" =~ ^[Nn]$ ]]; then
                echo "Skipping auto-deployment..."
            else
                echo
                echo "Step 1: Copying configuration to nginx container..."
                if cp "$config_file" "${nginx_config_dest}" 2>/dev/null || sudo cp "$config_file" "${nginx_config_dest}" 2>/dev/null; then
                    echo "✅ Configuration copied to ${nginx_config_dest}"
                else
                    echo "❌ Failed to copy configuration (permission denied)"
                    echo "   Run manually: sudo cp $config_file ${nginx_config_dest}"
                    auto_deploy="failed"
                fi

                if [[ "$auto_deploy" != "failed" ]]; then
                    echo
                    echo "Step 2: Testing nginx configuration..."
                    if docker exec openwebui-nginx nginx -t 2>&1 | grep -q "successful"; then
                        echo "✅ nginx configuration test passed"

                        echo
                        echo "Step 3: Reloading nginx..."
                        if docker exec openwebui-nginx nginx -s reload; then
                            echo "✅ nginx reloaded successfully"
                            echo
                            echo "╔════════════════════════════════════════╗"
                            echo "║     Configuration Deployed!            ║"
                            echo "╚════════════════════════════════════════╝"
                        else
                            echo "❌ Failed to reload nginx"
                        fi
                    else
                        echo "❌ nginx configuration test failed!"
                        echo "   Review the configuration and try again"
                        docker exec openwebui-nginx nginx -t
                        auto_deploy="failed"
                    fi
                fi
            fi
            echo
        fi

        if [ "$setup_type" = "production" ]; then
            # Auto-detect current server info
            current_user=$(whoami)
            current_hostname=$(hostname)

            echo "╔════════════════════════════════════════╗"
            echo "║         Production Setup Steps         ║"
            echo "╚════════════════════════════════════════╝"
            echo

            if [ "$nginx_containerized" = true ]; then
                # Containerized nginx instructions
                if [[ "$auto_deploy" != "failed" ]] && [[ ! "$auto_deploy" =~ ^[Nn]$ ]]; then
                    echo "✓ Configuration already deployed automatically"
                    echo
                fi

                echo "Next Steps:"
                echo
                if [[ "$auto_deploy" == "failed" ]] || [[ "$auto_deploy" =~ ^[Nn]$ ]]; then
                    echo "1. Copy config to nginx container directory:"
                    echo "   sudo cp $config_file ${nginx_config_dest}"
                    echo
                    echo "2. Test and reload nginx:"
                    echo "   docker exec openwebui-nginx nginx -t && docker exec openwebui-nginx nginx -s reload"
                    echo
                    step_num=3
                else
                    step_num=1
                fi

                echo "${step_num}. Configure DNS:"
                echo "   - Create A record: ${domain} → $(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_SERVER_IP')"
                echo "   - Wait for DNS propagation (1-5 minutes)"
                echo "   - Test: dig ${domain} +short"
                echo

                if [ "$ssl_ready" = false ]; then
                    ((step_num++))
                    echo "${step_num}. SSL Certificate Setup:"
                    echo

                    # Offer automated SSL setup
                    echo "Would you like to set up SSL certificate now?"
                    echo "Note: DNS must be configured first!"
                    echo
                    echo -n "Set up SSL certificate? (y/N): "
                    read setup_ssl

                    if [[ "$setup_ssl" =~ ^[Yy]$ ]]; then
                        echo
                        echo "Choose certificate type:"
                        echo "  1) Production (real certificate, rate limited)"
                        echo "  2) Staging (test certificate, no rate limits)"
                        echo
                        echo -n "Enter choice [1 or 2] (default: 1): "
                        read cert_type

                        # Default to production if empty
                        cert_type=${cert_type:-1}

                        if [[ "$cert_type" == "2" ]]; then
                            CERT_TYPE_FLAG="--test-cert"
                            echo "Using Let's Encrypt STAGING environment (test certificate)"
                        else
                            CERT_TYPE_FLAG=""
                            echo "Using Let's Encrypt PRODUCTION environment (real certificate)"
                        fi

                        echo
                        echo "Running certbot to obtain SSL certificate..."
                        echo

                        if sudo certbot certonly --webroot -w /opt/openwebui-nginx/webroot -d "${domain}" --non-interactive --agree-tos --email "admin@${domain}" ${CERT_TYPE_FLAG} 2>&1 | tee /tmp/certbot-output.log; then
                            echo
                            echo "✅ SSL certificate obtained successfully!"
                            echo

                            # Check if nginx container has SSL mount
                            echo "Checking nginx container SSL mount..."
                            if ! docker inspect openwebui-nginx --format '{{range .Mounts}}{{.Source}}{{end}}' 2>/dev/null | grep -q "/etc/letsencrypt"; then
                                echo
                                echo "⚠️  WARNING: nginx container does not have /etc/letsencrypt mounted!"
                                echo
                                echo "This happens when nginx was deployed before SSL certificates existed."
                                echo "The container needs to be redeployed to mount the SSL certificates."
                                echo
                                echo "Fix: Restart nginx container to pick up SSL mount"
                                echo
                                echo "Run these commands:"
                                echo "  cd ${SCRIPT_DIR}/nginx-container"
                                echo "  ./deploy-nginx-container.sh"
                                echo "  # Choose option 1 to remove and redeploy"
                                echo
                                echo "Then come back to this menu and select option 5 again to complete SSL setup."
                                echo
                                read -p "Press Enter to continue..."
                            else
                                echo "Updating nginx configuration to use SSL..."

                                # Generate SSL config
                                sed -e "s/\${CLIENT_NAME}/${client_name}/g" \
                                    -e "s/\${DOMAIN}/${domain}/g" \
                                    -e "s/\${CONTAINER_NAME}/${container_name}/g" \
                                    "${SCRIPT_DIR}/nginx-container/nginx-template-containerized.conf" > "$config_file"

                                # Deploy SSL config
                                if cp "$config_file" "${nginx_config_dest}" 2>/dev/null || sudo cp "$config_file" "${nginx_config_dest}" 2>/dev/null; then
                                    if docker exec openwebui-nginx nginx -t 2>&1 | grep -q "successful"; then
                                        docker exec openwebui-nginx nginx -s reload
                                        echo "✅ HTTPS is now enabled for ${domain}"
                                        echo
                                        echo "Test: curl -I https://${domain}"
                                    else
                                        echo "❌ nginx config test failed, check /opt/openwebui-nginx/conf.d/${domain}.conf"
                                        echo
                                        echo "Troubleshooting:"
                                        echo "  View nginx error: docker exec openwebui-nginx nginx -t"
                                        echo "  Check config file: cat /opt/openwebui-nginx/conf.d/${domain}.conf"
                                    fi
                                fi
                            fi
                        else
                            echo
                            echo "❌ Failed to obtain SSL certificate"
                            echo "Common issues:"
                            echo "  - DNS not configured or not propagated yet"
                            echo "  - Domain not pointing to this server"
                            echo "  - Port 80 not accessible from internet"
                            echo
                            echo "Manual command:"
                            echo "  sudo certbot certonly --webroot -w /opt/openwebui-nginx/webroot -d ${domain}"
                        fi
                    else
                        echo
                        echo "Manual SSL setup:"
                        echo "  sudo certbot certonly --webroot -w /opt/openwebui-nginx/webroot -d ${domain}"
                        echo
                        echo "Then regenerate nginx config and select option 1 (Production with HTTPS)"
                    fi
                else
                    echo "✅ SSL is already configured for this domain"
                fi
            else
                # Host nginx - AUTOMATED installation
                echo "╔════════════════════════════════════════╗"
                echo "║   Automated nginx Configuration        ║"
                echo "╚════════════════════════════════════════╝"
                echo

                # Step 1: Copy config to sites-available
                echo "📋 Installing nginx configuration..."
                echo
                if sudo cp "$config_file" "${nginx_config_dest}"; then
                    echo "✅ Config copied to ${nginx_config_dest}"
                else
                    echo "❌ Failed to copy config"
                    echo "Press Enter to continue..."
                    read
                    return 1
                fi

                # Step 2: Enable site
                echo
                if sudo ln -sf "${nginx_config_dest}" "/etc/nginx/sites-enabled/${domain}"; then
                    echo "✅ Site enabled in /etc/nginx/sites-enabled/${domain}"
                else
                    echo "❌ Failed to enable site"
                    echo "Press Enter to continue..."
                    read
                    return 1
                fi

                # Step 3: Test nginx config
                echo
                echo "🔍 Testing nginx configuration..."
                if sudo nginx -t; then
                    echo "✅ nginx configuration test passed"
                else
                    echo "❌ nginx configuration has errors"
                    echo "   Please review the config and try again"
                    echo "Press Enter to continue..."
                    read
                    return 1
                fi

                # Step 4: Reload nginx
                echo
                echo -n "Reload nginx now? (Y/n): "
                read reload_confirm
                if [[ ! "$reload_confirm" =~ ^[Nn]$ ]]; then
                    if sudo systemctl reload nginx; then
                        echo "✅ nginx reloaded successfully"
                    else
                        echo "❌ Failed to reload nginx"
                        echo "   Try: sudo systemctl status nginx"
                    fi
                else
                    echo "⚠️  Remember to reload nginx: sudo systemctl reload nginx"
                fi

                # Step 5: DNS Configuration reminder
                echo
                echo "═══════════════════════════════════════"
                echo "DNS Configuration Required"
                echo "═══════════════════════════════════════"
                echo "Create A record: ${domain} → $(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_SERVER_IP')"
                echo "Wait for DNS propagation (1-5 minutes)"
                echo "Test: dig ${domain} +short"
                echo

                # Step 6: SSL Certificate Setup
                echo "═══════════════════════════════════════"
                echo "SSL Certificate Setup"
                echo "═══════════════════════════════════════"
                echo
                echo "⚠️  NOTE: DNS must be configured and propagated first!"
                echo
                echo "Do you want to generate an SSL certificate now?"
                echo "1) Production certificate (Let's Encrypt - rate limited)"
                echo "2) Staging certificate (for testing - no rate limits)"
                echo "3) Skip (generate later)"
                echo
                echo -n "Choose option (1-3): "
                read cert_choice

                case "$cert_choice" in
                    1)
                        echo
                        echo "Generating production SSL certificate..."
                        echo "⚠️  Let's Encrypt rate limit: 5 certificates per domain per week"
                        echo
                        if sudo certbot --nginx -d "${domain}" --non-interactive --agree-tos --email "admin@${domain}"; then
                            echo
                            echo "✅ Production SSL certificate installed!"
                            echo "✅ nginx automatically configured for HTTPS"
                            echo
                            echo "Test: curl -I https://${domain}"
                        else
                            echo
                            echo "❌ Failed to obtain SSL certificate"
                            echo "Common issues:"
                            echo "  - DNS not configured or not propagated yet"
                            echo "  - Domain not pointing to this server: $(curl -s ifconfig.me)"
                            echo "  - Port 80 not accessible from internet"
                            echo
                            echo "Manual retry: sudo certbot --nginx -d ${domain}"
                        fi
                        ;;
                    2)
                        echo
                        echo "Generating staging SSL certificate..."
                        echo "ℹ️  This creates a test certificate (not trusted by browsers)"
                        echo
                        if sudo certbot --nginx -d "${domain}" --staging --non-interactive --agree-tos --email "admin@${domain}"; then
                            echo
                            echo "✅ Staging SSL certificate installed!"
                            echo "⚠️  This is a TEST certificate - browsers will show warnings"
                            echo
                            echo "For production certificate:"
                            echo "  1. Remove staging cert: sudo certbot delete --cert-name ${domain}"
                            echo "  2. Run option 5 again and choose production"
                        else
                            echo
                            echo "❌ Failed to obtain staging certificate"
                            echo "Manual retry: sudo certbot --nginx -d ${domain} --staging"
                        fi
                        ;;
                    3)
                        echo
                        echo "Skipped SSL certificate generation."
                        echo
                        echo "Generate later with:"
                        echo "  Production: sudo certbot --nginx -d ${domain}"
                        echo "  Staging: sudo certbot --nginx -d ${domain} --staging"
                        ;;
                    *)
                        echo
                        echo "Invalid choice. Skipping SSL setup."
                        echo
                        echo "Generate manually with:"
                        echo "  Production: sudo certbot --nginx -d ${domain}"
                        echo "  Staging: sudo certbot --nginx -d ${domain} --staging"
                        ;;
                esac
            fi
            echo
            echo "7. Update Google OAuth with redirect URI:"
            echo "   https://${domain}/oauth/google/callback"
        else
            echo "╔════════════════════════════════════════╗"
            echo "║          Local Testing Steps           ║"
            echo "╚════════════════════════════════════════╝"
            echo
            echo "1. Enable the site:"
            echo "   cp ${SCRIPT_DIR}/nginx/sites-available/${domain} ${SCRIPT_DIR}/nginx/sites-enabled/"
            echo
            echo "2. Start nginx container:"
            echo "   docker-compose -f docker-compose.nginx.yml up -d"
            echo
            echo "3. Test configuration:"
            echo "   docker exec local-nginx nginx -t"
            echo
            echo "4. Access your client:"
            echo "   http://localhost (nginx will proxy to port ${port})"
            echo
            echo "5. Update Google OAuth with redirect URI:"
            echo "   http://localhost/oauth/google/callback"
            echo
            echo "6. Stop nginx when done:"
            echo "   docker-compose -f docker-compose.nginx.yml down"
        fi
        echo

        echo "Press Enter to view the generated config..."
        read
        echo "Generated nginx configuration:"
        echo "============================="
        cat "$config_file"

    elif [ "$selection" -eq $((${#clients[@]}+1)) ]; then
        return
    else
        echo "Invalid selection. Press Enter to continue..."
        read
    fi

    echo
    echo "Press Enter to continue..."
    read
}

list_clients() {
    echo "Open WebUI Client Containers:"
    echo "============================="

    # Get all openwebui containers
    containers=($(docker ps -a --filter "name=openwebui-" --format "{{.Names}}"))

    if [ ${#containers[@]} -eq 0 ]; then
        echo "No Open WebUI deployments found."
        return
    fi

    # Header
    printf "%-25s %-30s %-20s %s\n" "CLIENT" "DOMAIN" "STATUS" "PORTS"
    printf "%-25s %-30s %-20s %s\n" "------" "------" "------" "-----"

    for container in "${containers[@]}"; do
        client_name=$(echo "$container" | sed 's/openwebui-//')
        status=$(docker ps -a --filter "name=${container}" --format "{{.Status}}")
        ports=$(docker ps -a --filter "name=${container}" --format "{{.Ports}}")

        # Try to get the redirect URI from container environment to extract domain
        redirect_uri=$(docker exec "$container" env 2>/dev/null | grep "GOOGLE_REDIRECT_URI=" | cut -d'=' -f2- 2>/dev/null || echo "")

        if [[ -n "$redirect_uri" ]]; then
            # Extract domain from redirect URI
            domain=$(echo "$redirect_uri" | sed -E 's|https?://||' | sed 's|/oauth/google/callback||')
        else
            domain="unknown"
        fi

        printf "%-25s %-30s %-20s %s\n" "$client_name" "$domain" "$status" "$ports"
    done
}

stop_all() {
    echo "Stopping all Open WebUI clients..."
    docker ps --filter "name=openwebui-" --format "{{.Names}}" | xargs -r docker stop
}

start_all() {
    echo "Starting all Open WebUI clients..."
    docker ps -a --filter "name=openwebui-" --filter "status=exited" --format "{{.Names}}" | xargs -r docker start
}

show_logs() {
    if [ -z "$2" ]; then
        echo "Usage: $0 logs CLIENT_NAME"
        echo "Available clients:"
        docker ps -a --filter "name=openwebui-" --format "{{.Names}}" | sed 's/openwebui-/  /'
        exit 1
    fi
    docker logs -f "openwebui-$2"
}

show_security_advisor_menu() {
    while true; do
        clear
        echo "╔════════════════════════════════════════╗"
        echo "║          Security Advisor              ║"
        echo "╚════════════════════════════════════════╝"
        echo

        local issues=0

        # 1. Root SSH Login
        echo "1. Root SSH Login Protection"
        local root_ssh=$(check_root_ssh_status)
        if [[ "$root_ssh" == "secured" ]]; then
            echo "   ✅ Secured (prohibit-password or no)"
        else
            echo "   ❌ VULNERABLE - Password login enabled"
            echo "   Fix: sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config && sudo systemctl reload sshd"
            ((issues++))
        fi
        echo

        # 2. Firewall Configuration
        echo "2. Firewall (UFW)"
        local firewall=$(check_firewall_status)
        if [[ "$firewall" == "configured" ]]; then
            echo "   ✅ Configured (ports 22, 80, 443 allowed)"
        elif [[ "$firewall" == "not_installed" ]]; then
            echo "   ❌ NOT INSTALLED"
            echo "   Install: sudo apt-get install -y ufw"
            echo "   Configure: sudo ufw allow 22/tcp && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp && sudo ufw enable"
            ((issues++))
        else
            echo "   ❌ NOT CONFIGURED"
            echo "   Fix: sudo ufw allow 22/tcp && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp && sudo ufw enable"
            ((issues++))
        fi
        echo

        # 3. fail2ban
        echo "3. fail2ban (SSH Brute Force Protection)"
        local fail2ban=$(check_fail2ban_status)
        if [[ "$fail2ban" == "active" ]]; then
            echo "   ✅ Active and running"
        elif [[ "$fail2ban" == "not_installed" ]]; then
            echo "   ❌ NOT INSTALLED"
            echo "   Install: sudo apt-get install -y fail2ban && sudo systemctl enable fail2ban && sudo systemctl start fail2ban"
            ((issues++))
        else
            echo "   ❌ INSTALLED BUT NOT ACTIVE"
            echo "   Fix: sudo systemctl enable fail2ban && sudo systemctl start fail2ban"
            ((issues++))
        fi
        echo

        # 4. SSH Password Authentication
        echo "4. SSH Password Authentication"
        local ssh_password=$(check_ssh_password_auth)
        if [[ "$ssh_password" == "disabled" ]]; then
            echo "   ✅ Disabled (key-only authentication)"
        else
            echo "   ❌ ENABLED - Vulnerable to brute force"
            echo "   Fix: echo 'PasswordAuthentication no' | sudo tee -a /etc/ssh/sshd_config && sudo systemctl reload sshd"
            echo "   Note: Ensure SSH key access works BEFORE disabling password auth!"
            ((issues++))
        fi
        echo

        # 5. Automatic Security Updates
        echo "5. Automatic Security Updates"
        local auto_updates=$(check_auto_updates)
        if [[ "$auto_updates" == "configured" ]]; then
            echo "   ✅ Configured (unattended-upgrades)"
        elif [[ "$auto_updates" == "not_installed" ]]; then
            echo "   ❌ NOT INSTALLED"
            echo "   Install: sudo apt-get install -y unattended-upgrades && sudo dpkg-reconfigure -plow unattended-upgrades"
            ((issues++))
        else
            echo "   ❌ INSTALLED BUT NOT ENABLED"
            echo "   Fix: sudo dpkg-reconfigure -plow unattended-upgrades"
            ((issues++))
        fi
        echo

        # Summary
        echo "═══════════════════════════════════════"
        if [[ $issues -eq 0 ]]; then
            echo "✅ All security configurations are properly set!"
        else
            echo "⚠️  $issues security issue(s) need attention"
        fi
        echo "═══════════════════════════════════════"
        echo
        echo "See setup/README for detailed security guidance"
        echo
        echo "0) Return to Main Menu"
        echo
        echo -n "Enter option: "

        read sec_choice

        case "$sec_choice" in
            0)
                return
                ;;
            *)
                # Any other key refreshes the display
                ;;
        esac
    done
}

# ═══════════════════════════════════════
# nginx Management Functions
# ═══════════════════════════════════════

check_nginx_status() {
    clear

    # Check if status script exists
    local status_script="${SCRIPT_DIR}/nginx/scripts/check-nginx-status.sh"
    if [ -f "$status_script" ]; then
        # Run the HOST nginx status check script
        bash "$status_script"
    else
        # Fallback to inline HOST nginx check
        echo "╔════════════════════════════════════════╗"
        echo "║         nginx Status Check             ║"
        echo "╚════════════════════════════════════════╝"
        echo

        if command -v nginx &> /dev/null; then
            echo "🔍 HOST nginx Installation:"
            echo "  Version: $(nginx -v 2>&1 | cut -d/ -f2)"
            echo
            if systemctl is-active --quiet nginx; then
                echo "  Status: ✅ RUNNING"
            else
                echo "  Status: ❌ STOPPED"
            fi
        else
            echo "❌ HOST nginx not installed"
        fi
        echo
    fi

    # Check for containerized nginx (keep this inline as it's simple)
    echo "─────────────────────────────────────────"
    echo
    if docker ps -a --filter "name=openwebui-nginx" --format "{{.Names}}" 2>/dev/null | grep -q "openwebui-nginx"; then
        echo "🔍 Containerized nginx:"
        nginx_status=$(docker inspect -f '{{.State.Status}}' openwebui-nginx 2>/dev/null)
        if [[ "$nginx_status" == "running" ]]; then
            echo "  Status: ✅ RUNNING"
        else
            echo "  Status: ❌ STOPPED (state: $nginx_status)"
        fi
        echo "  Container: openwebui-nginx"
        echo
        docker ps -a --filter "name=openwebui-nginx" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo
    else
        echo "❌ Containerized nginx not deployed"
        echo
    fi

    echo "Press Enter to continue..."
    read
}

install_nginx_host() {
    clear

    # Check if installation script exists
    local install_script="${SCRIPT_DIR}/nginx/scripts/install-nginx-host.sh"
    if [ -f "$install_script" ]; then
        # Run the installation script
        bash "$install_script"
    else
        echo "╔════════════════════════════════════════╗"
        echo "║    Install nginx on HOST (Production)  ║"
        echo "╚════════════════════════════════════════╝"
        echo
        echo "❌ Installation script not found: $install_script"
        echo
        echo "Expected location: mt/nginx/scripts/install-nginx-host.sh"
        echo
        echo "Falling back to quick installation..."
        echo
        echo -n "Continue with installation? (y/N): "
        read confirm

        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Installation cancelled."
            echo "Press Enter to continue..."
            read
            return
        fi

    echo
    echo "📦 Installing nginx and certbot..."

    # Update package list
    sudo apt-get update

    # Install nginx
    if ! command -v nginx &> /dev/null; then
        sudo apt-get install -y nginx
        if [ $? -ne 0 ]; then
            echo "❌ Failed to install nginx"
            echo "Press Enter to continue..."
            read
            return
        fi
    else
        echo "✅ nginx already installed"
    fi

    # Install certbot for SSL
    echo "📦 Installing certbot and nginx plugin..."

    # Check and install certbot binary
    if ! command -v certbot &> /dev/null; then
        sudo apt-get install -y certbot
        if [ $? -ne 0 ]; then
            echo "❌ Failed to install certbot"
            echo "Press Enter to continue..."
            read
            return
        fi
        echo "✅ certbot installed"
    else
        echo "✅ certbot already installed"
    fi

    # Check and install nginx plugin (independent check - critical!)
    if ! dpkg -l python3-certbot-nginx 2>/dev/null | grep -q "^ii"; then
        sudo apt-get install -y python3-certbot-nginx
        if [ $? -ne 0 ]; then
            echo "❌ Failed to install python3-certbot-nginx plugin"
            echo "Press Enter to continue..."
            read
            return
        fi
        echo "✅ python3-certbot-nginx installed"
    else
        echo "✅ python3-certbot-nginx already installed"
    fi

    # Configure firewall for nginx
    echo
    echo "🔥 Configuring firewall for nginx..."
    if command -v ufw &> /dev/null; then
        # Check if ufw is active
        if sudo ufw status | grep -q "Status: active"; then
            # Try 'Nginx Full' profile first, fallback to direct port rules
            if sudo ufw allow 'Nginx Full' 2>/dev/null; then
                # Verify the rule was added
                if sudo ufw status | grep -qiE "(Nginx Full|80.*ALLOW|443.*ALLOW)"; then
                    echo "✅ Firewall configured to allow HTTP (80) and HTTPS (443)"
                else
                    echo "⚠️  'Nginx Full' command succeeded but rules not visible"
                    echo "   Trying direct port configuration..."
                    sudo ufw allow 80/tcp
                    sudo ufw allow 443/tcp
                    echo "✅ Firewall configured with direct port rules"
                fi
            else
                echo "ℹ️  'Nginx Full' profile not available, using direct port rules..."
                sudo ufw allow 80/tcp
                sudo ufw allow 443/tcp
                if sudo ufw status | grep -qE "(80/tcp.*ALLOW|443/tcp.*ALLOW)"; then
                    echo "✅ Firewall configured to allow HTTP (80) and HTTPS (443)"
                else
                    echo "❌ Failed to configure firewall rules"
                    echo "   Please run manually: sudo ufw allow 80/tcp && sudo ufw allow 443/tcp"
                fi
            fi
        else
            echo "⚠️  UFW firewall is installed but not active"
            echo "   To enable: sudo ufw enable"
            echo "   Then run: sudo ufw allow 80/tcp && sudo ufw allow 443/tcp"
        fi
    else
        echo "⚠️  UFW firewall not installed (nginx will still work)"
        echo "   Install with: sudo apt-get install -y ufw"
    fi

    # Enable and start nginx
    echo
    echo "🚀 Enabling and starting nginx service..."
    sudo systemctl enable nginx
    sudo systemctl start nginx

    # Check status
    if systemctl is-active --quiet nginx; then
        echo
        echo "✅ nginx installed and running successfully!"
        echo
        echo "📋 Next steps:"
        echo "  1. Create client deployment (option 3 from main menu)"
        echo "  2. Generate nginx config (option 5 from main menu)"
        echo "  3. Copy config: sudo cp /tmp/DOMAIN-nginx.conf /etc/nginx/sites-available/DOMAIN"
        echo "  4. Enable site: sudo ln -s /etc/nginx/sites-available/DOMAIN /etc/nginx/sites-enabled/"
        echo "  5. Test config: sudo nginx -t"
        echo "  6. Generate SSL: sudo certbot --nginx -d DOMAIN"
        echo "  7. Reload nginx: sudo systemctl reload nginx"
    else
        echo
        echo "❌ nginx installed but failed to start. Check logs with:"
        echo "   sudo systemctl status nginx"
        echo "   sudo journalctl -u nginx -n 50"
    fi

        echo
        echo "Press Enter to continue..."
        read
    fi

    echo
    echo "Press Enter to continue..."
    read
}

install_nginx_container() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║   Install nginx in Container (TESTING) ║"
    echo "╚════════════════════════════════════════╝"
    echo
    echo "⚠️  WARNING: EXPERIMENTAL - For testing only!"
    echo
    echo "This deployment mode has known issues:"
    echo "  - Function pipe saves may fail"
    echo "  - Still under validation and debugging"
    echo
    echo "Use HOST nginx installation (option 1) for production."
    echo
    echo -n "Continue with containerized nginx? (y/N): "
    read confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        echo "Press Enter to continue..."
        read
        return
    fi

    echo
    echo "Deploying containerized nginx..."
    echo

    # Check if deployment script exists
    local deploy_script="${SCRIPT_DIR}/nginx-container/deploy-nginx-container.sh"
    if [ ! -f "$deploy_script" ]; then
        echo "❌ Deployment script not found: $deploy_script"
        echo
        echo "Expected location: mt/nginx-container/deploy-nginx-container.sh"
        echo
        echo "Press Enter to continue..."
        read
        return 1
    fi

    # Run the deployment script
    if bash "$deploy_script"; then
        echo
        echo "✅ Containerized nginx deployment completed"
        echo
        echo "⚠️  REMINDER: This is EXPERIMENTAL"
        echo "   Known issue: Function pipe saves may fail"
        echo "   For production, use HOST nginx (option 1)"
    else
        echo
        echo "❌ Deployment failed"
        echo "   Check the error messages above"
        echo "   For production deployments, use HOST nginx (option 1)"
    fi

    echo
    echo "Press Enter to continue..."
    read
}

uninstall_nginx() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║         Uninstall nginx                 ║"
    echo "╚════════════════════════════════════════╝"
    echo

    # Detect what's installed
    host_installed=false
    container_installed=false

    if command -v nginx &> /dev/null; then
        host_installed=true
    fi

    if docker ps -a --filter "name=openwebui-nginx" --format "{{.Names}}" | grep -q "openwebui-nginx"; then
        container_installed=true
    fi

    if [[ "$host_installed" == false ]] && [[ "$container_installed" == false ]]; then
        echo "❌ No nginx installation found"
        echo
        echo "Press Enter to continue..."
        read
        return
    fi

    # Show what will be removed
    echo "The following will be removed:"
    echo
    if [[ "$host_installed" == true ]]; then
        echo "  - HOST nginx (systemd service)"
        echo "  - nginx configuration files in /etc/nginx/"
        echo "  - certbot and SSL certificates"
    fi
    if [[ "$container_installed" == true ]]; then
        echo "  - Containerized nginx (Docker container)"
        echo "  - Container volumes and configs"
    fi
    echo
    echo "⚠️  WARNING: This will stop all nginx services!"
    echo
    echo -n "Type 'REMOVE' to confirm removal: "
    read confirm

    if [[ "$confirm" != "REMOVE" ]]; then
        echo "Uninstallation cancelled."
        echo "Press Enter to continue..."
        read
        return
    fi

    echo

    # Remove containerized nginx first
    if [[ "$container_installed" == true ]]; then
        echo "🗑️  Removing containerized nginx..."
        docker stop openwebui-nginx 2>/dev/null
        docker rm openwebui-nginx 2>/dev/null
        echo "✅ Containerized nginx removed"
        echo
    fi

    # Remove HOST nginx
    if [[ "$host_installed" == true ]]; then
        echo "🗑️  Removing HOST nginx..."
        echo

        # Check if uninstall script exists
        local uninstall_script="${SCRIPT_DIR}/nginx/scripts/uninstall-nginx-host.sh"
        if [ -f "$uninstall_script" ]; then
            # Run the uninstall script
            bash "$uninstall_script"
        else
            # Fallback to inline uninstallation
            echo -n "Also remove SSL certificates? (y/N): "
            read remove_ssl

            sudo systemctl stop nginx
            sudo systemctl disable nginx
            sudo apt-get remove -y nginx nginx-common

            if [[ "$remove_ssl" =~ ^[Yy]$ ]]; then
                sudo apt-get remove -y certbot python3-certbot-nginx
                echo "Note: SSL certificates in /etc/letsencrypt/ preserved."
                echo "      Remove manually if desired: sudo rm -rf /etc/letsencrypt/"
            fi

            sudo apt-get autoremove -y

            echo "✅ HOST nginx uninstalled"
            echo
            echo "Note: Configuration files in /etc/nginx/ preserved."
            echo "      Remove manually if desired: sudo rm -rf /etc/nginx/"
        fi
    fi

    echo
    echo "Press Enter to continue..."
    read
}

# Manage containerized nginx container submenu
manage_nginx_container_submenu() {
    while true; do
        clear
        echo "╔════════════════════════════════════════╗"
        echo "║      Manage nginx Container            ║"
        echo "╚════════════════════════════════════════╝"
        echo

        # Show nginx container status
        local status=$(docker ps --filter "name=openwebui-nginx" --format "{{.Status}}" 2>/dev/null)
        local ports=$(docker ps -a --filter "name=openwebui-nginx" --format "{{.Ports}}" 2>/dev/null)

        if [ -z "$status" ]; then
            echo "⚠️  nginx container not found"
            echo
            echo "Press Enter to return to nginx menu..."
            read
            return
        fi

        echo "Status: $status"
        echo "Ports:  $ports"
        echo "Network: openwebui-network"
        echo

        echo "1) View nginx Logs"
        echo "2) Test nginx Configuration"
        echo "3) Reload nginx"
        echo "4) Restart nginx Container"
        echo "5) Stop nginx Container"
        echo "6) Back to nginx Menu"
        echo
        echo -n "Select action (1-6): "
        read action

        case "$action" in
            1)
                clear
                echo "Showing nginx logs (Ctrl+C to exit)..."
                echo
                docker logs -f openwebui-nginx
                ;;
            2)
                clear
                echo "Testing nginx configuration..."
                echo
                docker exec openwebui-nginx nginx -t
                echo
                echo "Press Enter to continue..."
                read
                ;;
            3)
                clear
                echo "Reloading nginx..."
                docker exec openwebui-nginx nginx -s reload
                echo "✅ nginx reloaded"
                echo
                echo "Press Enter to continue..."
                read
                ;;
            4)
                clear
                echo "Restarting nginx container..."
                docker restart openwebui-nginx
                echo "✅ nginx container restarted"
                echo
                echo "Press Enter to continue..."
                read
                ;;
            5)
                clear
                echo "⚠️  Stopping nginx will make all client sites inaccessible!"
                echo -n "Are you sure? (y/N): "
                read confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    docker stop openwebui-nginx
                    echo "✅ nginx container stopped"
                else
                    echo "Cancelled"
                fi
                echo
                echo "Press Enter to continue..."
                read
                ;;
            6)
                return
                ;;
            *)
                echo "Invalid selection. Press Enter to continue..."
                read
                ;;
        esac
    done
}

manage_nginx_menu() {
    while true; do
        clear
        echo "╔════════════════════════════════════════╗"
        echo "║        Manage nginx Installation        ║"
        echo "╚════════════════════════════════════════╝"
        echo

        # Check if containerized nginx exists
        local nginx_container_exists=false
        if docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^openwebui-nginx$"; then
            nginx_container_exists=true
        fi

        echo "1) Install nginx on HOST (Production - Recommended)"
        echo "2) Install nginx in Container (Experimental)"

        if [ "$nginx_container_exists" = true ]; then
            echo "3) Manage nginx Container ✓"
        else
            echo "3) Manage nginx Container (not installed)"
        fi

        echo "4) Generate nginx Configuration for Client"
        echo "5) Check nginx Status"
        echo "6) Uninstall nginx"
        echo "7) Back to Main Menu"
        echo
        echo -n "Please select an option (1-7): "
        read choice

        case "$choice" in
            1)
                install_nginx_host
                ;;
            2)
                install_nginx_container
                ;;
            3)
                if [ "$nginx_container_exists" = true ]; then
                    manage_nginx_container_submenu
                else
                    echo
                    echo "nginx container is not installed."
                    echo "Use option 2 to install nginx in container."
                    echo
                    echo "Press Enter to continue..."
                    read
                fi
                ;;
            4)
                generate_nginx_config
                ;;
            5)
                check_nginx_status
                ;;
            6)
                uninstall_nginx
                ;;
            7)
                return
                ;;
            *)
                echo "Invalid choice. Press Enter to continue..."
                read
                ;;
        esac
    done
}

# Main execution logic
if [ $# -eq 0 ]; then
    # Interactive menu mode
    while true; do
        show_main_menu
        read choice

        case "$choice" in
            1)
                clear
                list_clients
                echo
                echo "Press Enter to continue..."
                read
                ;;
            2)
                create_new_deployment
                ;;
            3)
                manage_deployment_menu
                ;;
            4)
                manage_sync_cluster_menu
                ;;
            5)
                manage_nginx_menu
                ;;
            6)
                show_security_advisor_menu
                ;;
            7)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                echo "Invalid choice. Press Enter to continue..."
                read
                ;;
        esac
    done
else
    # Command line mode (preserve original functionality)
    case "$1" in
        "help"|"-h"|"--help")
            show_help
            ;;
        "list")
            list_clients
            ;;
        "stop")
            stop_all
            ;;
        "start")
            start_all
            ;;
        "logs")
            show_logs "$@"
            ;;
        *)
            echo "Unknown command: $1"
            echo "Run './client-manager.sh help' for available commands"
            exit 1
            ;;
    esac
fi
