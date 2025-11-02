#!/bin/bash

# Create SSL Options Files for nginx Container
# This script creates the Let's Encrypt SSL configuration files
# that are commonly referenced in nginx configurations

set -e

echo "╔════════════════════════════════════════╗"
echo "║   Create SSL Options for nginx         ║"
echo "╚════════════════════════════════════════╝"
echo

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ] && [ -z "$SUDO_USER" ]; then
    echo "⚠️  Warning: This script may need sudo privileges to write to /opt/openwebui-nginx/"
    echo "If you encounter permission errors, run with sudo."
    echo
fi

# Define paths
NGINX_BASE="/opt/openwebui-nginx"
SSL_DIR="${NGINX_BASE}/ssl"
OPTIONS_FILE="${SSL_DIR}/options-ssl-nginx.conf"
DHPARAM_FILE="${SSL_DIR}/ssl-dhparams.pem"

# Create SSL directory if it doesn't exist
if [ ! -d "$SSL_DIR" ]; then
    echo "Creating SSL directory: $SSL_DIR"
    mkdir -p "$SSL_DIR"
fi

# Create options-ssl-nginx.conf
echo "Creating SSL options file: $OPTIONS_FILE"
cat > "$OPTIONS_FILE" << 'EOF'
# SSL Configuration for nginx
# This file provides secure SSL/TLS settings for modern browsers
# Compatible with Let's Encrypt and other certificate providers

ssl_session_cache shared:le_nginx_SSL:10m;
ssl_session_timeout 1440m;
ssl_session_tickets off;

ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;

ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
EOF

echo "✅ Created: $OPTIONS_FILE"

# Create DH parameters file (2048-bit for faster generation, still secure)
if [ ! -f "$DHPARAM_FILE" ]; then
    echo
    echo "Creating DH parameters file: $DHPARAM_FILE"
    echo "⚠️  This may take 1-2 minutes..."

    # Generate DH params
    openssl dhparam -out "$DHPARAM_FILE" 2048 2>/dev/null

    echo "✅ Created: $DHPARAM_FILE"
else
    echo "ℹ️  DH parameters file already exists: $DHPARAM_FILE"
fi

# Set proper permissions
echo
echo "Setting permissions..."
chmod 644 "$OPTIONS_FILE"
chmod 600 "$DHPARAM_FILE"

echo
echo "╔════════════════════════════════════════╗"
echo "║   SSL Options Created Successfully     ║"
echo "╚════════════════════════════════════════╝"
echo
echo "Files created:"
echo "  - $OPTIONS_FILE"
echo "  - $DHPARAM_FILE"
echo
echo "These files can now be referenced in nginx configs:"
echo "  include /etc/nginx/ssl/options-ssl-nginx.conf;"
echo "  ssl_dhparam /etc/nginx/ssl/ssl-dhparams.pem;"
echo
echo "Note: In the nginx container, these files will be mounted at:"
echo "  /etc/nginx/ssl/options-ssl-nginx.conf"
echo "  /etc/nginx/ssl/ssl-dhparams.pem"
echo
