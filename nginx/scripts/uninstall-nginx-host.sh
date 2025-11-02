#!/bin/bash

# Uninstall nginx from HOST
# Removes nginx, certbot, and related configuration files

set -e  # Exit on error

echo "╔════════════════════════════════════════╗"
echo "║      Uninstall nginx from HOST         ║"
echo "╚════════════════════════════════════════╝"
echo

echo "⚠️  WARNING: This will remove nginx and all configurations!"
echo "   This will make all client sites inaccessible."
echo
echo -n "Continue with uninstall? (y/N): "
read confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo
echo "🛑 Stopping nginx service..."
if sudo systemctl stop nginx 2>/dev/null; then
    echo "✅ nginx service stopped"
else
    echo "ℹ️  nginx service was not running"
fi

if sudo systemctl disable nginx 2>/dev/null; then
    echo "✅ nginx service disabled"
fi

echo
echo "📦 Removing packages..."
if sudo apt-get remove --purge -y nginx nginx-common nginx-core certbot python3-certbot-nginx 2>/dev/null; then
    echo "✅ Packages removed"
else
    echo "⚠️  Some packages may not have been installed"
fi

echo
echo "🧹 Cleaning up configuration files..."

# Remove nginx configs
if [ -d "/etc/nginx" ]; then
    echo "   Removing /etc/nginx..."
    sudo rm -rf /etc/nginx
    echo "✅ nginx configuration removed"
fi

# Remove Let's Encrypt certificates
if [ -d "/etc/letsencrypt" ]; then
    echo "   Removing /etc/letsencrypt..."
    sudo rm -rf /etc/letsencrypt
    echo "✅ SSL certificates removed"
fi

# Remove nginx logs
if [ -d "/var/log/nginx" ]; then
    echo "   Removing /var/log/nginx..."
    sudo rm -rf /var/log/nginx
    echo "✅ nginx logs removed"
fi

# Remove web root if empty
if [ -d "/var/www/html" ]; then
    if [ -z "$(ls -A /var/www/html 2>/dev/null)" ]; then
        echo "   Removing empty /var/www/html..."
        sudo rm -rf /var/www/html
    fi
fi

echo
echo "🧹 Cleaning up package cache..."
sudo apt-get autoremove -y 2>/dev/null || true
sudo apt-get autoclean 2>/dev/null || true

echo
echo "═══════════════════════════════════════"
echo "Uninstall Complete!"
echo "═══════════════════════════════════════"
echo
echo "nginx has been completely removed from this system."
echo
echo "Firewall rules for ports 80 and 443 are still in place."
echo "To remove them:"
echo "  sudo ufw delete allow 80/tcp"
echo "  sudo ufw delete allow 443/tcp"
echo "  sudo ufw delete allow 'Nginx Full'"
echo

exit 0
