#!/bin/bash

# Install nginx on HOST (Production Mode)
# This script installs nginx as a systemd service on the host system
# Matches the proven working configuration on server 159.65.34.41

set -e  # Exit on error

echo "╔════════════════════════════════════════╗"
echo "║  Install nginx on HOST (Production)   ║"
echo "╚════════════════════════════════════════╝"
echo

# Check if running with appropriate privileges
if [ "$EUID" -eq 0 ]; then
    echo "⚠️  Running as root. This script should be run as a regular user with sudo access."
    echo
fi

echo "This will install nginx as a systemd service on the host."
echo "This is the RECOMMENDED configuration for production deployments."
echo
echo "Components installed:"
echo "  - nginx (web server)"
echo "  - certbot (SSL certificate management)"
echo "  - python3-certbot-nginx (nginx plugin for certbot)"
echo

# Update package list
echo "📦 Updating package list..."
if sudo apt-get update; then
    echo "✅ Package list updated"
else
    echo "❌ Failed to update package list"
    exit 1
fi

# Install nginx
echo
echo "📦 Installing nginx..."
if command -v nginx &> /dev/null; then
    echo "✅ nginx already installed ($(nginx -v 2>&1))"
else
    if sudo apt-get install -y nginx; then
        echo "✅ nginx installed successfully ($(nginx -v 2>&1))"
    else
        echo "❌ Failed to install nginx"
        exit 1
    fi
fi

# Install certbot for SSL
echo
echo "📦 Installing certbot and nginx plugin..."

# Check and install certbot binary
if command -v certbot &> /dev/null; then
    echo "✅ certbot already installed ($(certbot --version 2>&1 | head -1))"
else
    if sudo apt-get install -y certbot; then
        echo "✅ certbot installed successfully"
    else
        echo "❌ Failed to install certbot"
        exit 1
    fi
fi

# Check and install nginx plugin (independent check - critical!)
if dpkg -l python3-certbot-nginx 2>/dev/null | grep -q "^ii"; then
    echo "✅ python3-certbot-nginx already installed"
else
    echo "📦 Installing python3-certbot-nginx plugin..."
    if sudo apt-get install -y python3-certbot-nginx; then
        echo "✅ python3-certbot-nginx installed successfully"
    else
        echo "❌ Failed to install python3-certbot-nginx"
        exit 1
    fi
fi

# Configure firewall for nginx
echo
echo "🔥 Configuring firewall..."
if command -v ufw &> /dev/null; then
    # Check if UFW is active
    if sudo ufw status | grep -q "Status: active"; then
        # Try 'Nginx Full' profile first
        if sudo ufw allow 'Nginx Full' 2>/dev/null; then
            # Verify the rule was added
            if sudo ufw status | grep -qiE "(Nginx Full|80.*ALLOW|443.*ALLOW)"; then
                echo "✅ Firewall configured (Nginx Full profile)"
            else
                echo "⚠️  Nginx Full profile exists but rules not visible, using direct ports..."
                sudo ufw allow 80/tcp
                sudo ufw allow 443/tcp
                echo "✅ Firewall configured (direct ports 80, 443)"
            fi
        else
            # Fallback to direct port rules
            echo "ℹ️  Nginx Full profile not available, using direct port rules..."
            sudo ufw allow 80/tcp
            sudo ufw allow 443/tcp
            if sudo ufw status | grep -qE "(80/tcp.*ALLOW|443/tcp.*ALLOW)"; then
                echo "✅ Firewall configured (direct ports 80, 443)"
            else
                echo "❌ Failed to configure firewall rules"
                echo "   Please run manually:"
                echo "   sudo ufw allow 80/tcp"
                echo "   sudo ufw allow 443/tcp"
                exit 1
            fi
        fi
    else
        echo "⚠️  UFW firewall is not active"
        echo "   Consider enabling it: sudo ufw enable"
    fi
else
    echo "⚠️  UFW not installed, skipping firewall configuration"
fi

# Start and enable nginx service
echo
echo "🚀 Starting nginx service..."
if sudo systemctl start nginx; then
    echo "✅ nginx service started"
else
    echo "❌ Failed to start nginx service"
    exit 1
fi

if sudo systemctl enable nginx; then
    echo "✅ nginx service enabled (will start on boot)"
else
    echo "⚠️  Failed to enable nginx service"
fi

# Verify nginx is running
echo
echo "🔍 Verifying installation..."
if systemctl is-active --quiet nginx; then
    echo "✅ nginx is running"
else
    echo "❌ nginx is not running"
    exit 1
fi

# Test nginx configuration
if sudo nginx -t &> /dev/null; then
    echo "✅ nginx configuration is valid"
else
    echo "⚠️  nginx configuration has warnings"
    sudo nginx -t
fi

# Display installation summary
echo
echo "═══════════════════════════════════════"
echo "Installation Complete!"
echo "═══════════════════════════════════════"
echo
echo "Installed components:"
echo "  nginx:   $(nginx -v 2>&1 | grep -o 'nginx/[0-9.]*')"
echo "  certbot: $(certbot --version 2>&1 | head -1 | grep -o 'certbot [0-9.]*')"
echo
echo "nginx status: $(systemctl is-active nginx)"
echo "Firewall:     Ports 80, 443 allowed"
echo
echo "📋 Next steps:"
echo "  1. Create client deployment (via client-manager.sh)"
echo "  2. Generate nginx config for client"
echo "  3. SSL certificate will be generated automatically"
echo
echo "Useful commands:"
echo "  Status:  sudo systemctl status nginx"
echo "  Stop:    sudo systemctl stop nginx"
echo "  Start:   sudo systemctl start nginx"
echo "  Reload:  sudo systemctl reload nginx"
echo "  Test:    sudo nginx -t"
echo "  Logs:    sudo journalctl -u nginx -n 50"
echo

exit 0
