#!/bin/bash

# Check nginx status on HOST
# Displays service status, version, listening ports, and configuration

echo "═══════════════════════════════════════"
echo "nginx Status Check"
echo "═══════════════════════════════════════"
echo

# Check if nginx is installed
if ! command -v nginx &> /dev/null; then
    echo "❌ nginx is not installed"
    echo
    echo "To install nginx:"
    echo "  cd ~/open-webui/mt/nginx"
    echo "  ./scripts/install-nginx-host.sh"
    exit 1
fi

# Display nginx version
echo "nginx Version:"
nginx -v 2>&1 | sed 's/^/  /'
echo

# Check service status
echo "Service Status:"
if systemctl is-active --quiet nginx 2>/dev/null; then
    echo "  ✅ nginx is running"

    # Show how long it's been running
    uptime=$(systemctl show nginx --property=ActiveEnterTimestamp --value 2>/dev/null)
    if [ -n "$uptime" ]; then
        echo "  Started: $uptime"
    fi
else
    echo "  ❌ nginx is not running"

    # Check if service exists
    if systemctl list-unit-files | grep -q nginx.service; then
        echo "  Service exists but is stopped"
        echo
        echo "  To start: sudo systemctl start nginx"
    fi
fi
echo

# Check if enabled on boot
echo "Boot Configuration:"
if systemctl is-enabled --quiet nginx 2>/dev/null; then
    echo "  ✅ nginx will start on boot"
else
    echo "  ⚠️  nginx will NOT start on boot"
    echo "  To enable: sudo systemctl enable nginx"
fi
echo

# Check listening ports
echo "Listening Ports:"
if command -v netstat &> /dev/null; then
    netstat -tlnp 2>/dev/null | grep nginx | awk '{print "  " $4}' || echo "  No ports found"
elif command -v ss &> /dev/null; then
    sudo ss -tlnp 2>/dev/null | grep nginx | awk '{print "  " $4}' || echo "  No ports found"
else
    echo "  (netstat/ss not available)"
fi
echo

# Check certbot
echo "SSL Certificate Management:"
if command -v certbot &> /dev/null; then
    echo "  ✅ certbot installed ($(certbot --version 2>&1 | head -1))"

    # List certificates
    cert_count=$(sudo certbot certificates 2>/dev/null | grep "Certificate Name:" | wc -l)
    if [ "$cert_count" -gt 0 ]; then
        echo "  📜 Active certificates: $cert_count"
        sudo certbot certificates 2>/dev/null | grep -E "Certificate Name:|Domains:" | sed 's/^/    /'
    else
        echo "  ℹ️  No certificates installed yet"
    fi
else
    echo "  ❌ certbot not installed"
fi
echo

# Check configuration syntax
echo "Configuration Test:"
if sudo nginx -t &> /dev/null; then
    echo "  ✅ Configuration is valid"
else
    echo "  ❌ Configuration has errors"
    echo
    sudo nginx -t 2>&1 | sed 's/^/  /'
fi
echo

# Check enabled sites
echo "Enabled Sites:"
if [ -d "/etc/nginx/sites-enabled" ]; then
    site_count=$(ls -1 /etc/nginx/sites-enabled/ 2>/dev/null | wc -l)
    if [ "$site_count" -gt 0 ]; then
        echo "  📄 $site_count site(s) configured:"
        ls -1 /etc/nginx/sites-enabled/ | sed 's/^/    - /'
    else
        echo "  ℹ️  No sites configured yet"
    fi
else
    echo "  ⚠️  sites-enabled directory not found"
fi
echo

# Firewall status
echo "Firewall Status:"
if command -v ufw &> /dev/null; then
    if sudo ufw status | grep -q "Status: active"; then
        echo "  ✅ UFW is active"

        # Check for nginx rules
        if sudo ufw status | grep -qiE "(Nginx Full|80.*ALLOW|443.*ALLOW)"; then
            echo "  ✅ nginx ports allowed (80, 443)"
        else
            echo "  ⚠️  nginx ports may not be allowed"
            echo "  Add rules: sudo ufw allow 'Nginx Full'"
        fi
    else
        echo "  ⚠️  UFW is not active"
    fi
else
    echo "  ℹ️  UFW not installed"
fi
echo

# Useful commands
echo "═══════════════════════════════════════"
echo "Useful Commands:"
echo "═══════════════════════════════════════"
echo "  Status:   sudo systemctl status nginx"
echo "  Stop:     sudo systemctl stop nginx"
echo "  Start:    sudo systemctl start nginx"
echo "  Restart:  sudo systemctl restart nginx"
echo "  Reload:   sudo systemctl reload nginx"
echo "  Test:     sudo nginx -t"
echo "  Logs:     sudo journalctl -u nginx -f"
echo "  Certs:    sudo certbot certificates"
echo

exit 0
