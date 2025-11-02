#!/bin/bash

# Multi-Client Open WebUI Template Script
# Usage: ./start-template.sh SUBDOMAIN PORT DOMAIN CONTAINER_NAME FQDN [OAUTH_DOMAINS] [WEBUI_SECRET_KEY]
# FQDN-based container naming for multi-tenant deployments

if [ $# -lt 5 ]; then
    echo "Usage: $0 SUBDOMAIN PORT DOMAIN CONTAINER_NAME FQDN [OAUTH_DOMAINS] [WEBUI_SECRET_KEY]"
    echo "Examples:"
    echo "  $0 chat 8081 chat.client-a.com openwebui-chat-client-a-com chat.client-a.com"
    echo "  $0 chat 8082 localhost:8082 openwebui-localhost-8082 localhost:8082 martins.net SECRET_KEY"
    exit 1
fi

SUBDOMAIN=$1
PORT=$2
DOMAIN=$3
CONTAINER_NAME=$4
FQDN=$5
OAUTH_DOMAINS="${6:-martins.net}"  # Default to martins.net if not provided
WEBUI_SECRET_KEY="${7:-$(openssl rand -base64 32)}"  # Generate if not provided

# Extract CLIENT_ID from CONTAINER_NAME (strip "openwebui-" prefix)
# This is the unique identifier for this deployment (sanitized FQDN)
CLIENT_ID="${CONTAINER_NAME#openwebui-}"

# Per-client directory for volume mounts (uses CLIENT_ID for uniqueness)
CLIENT_DIR="/opt/openwebui/${CLIENT_ID}"

# Legacy Docker volume name (for backward compatibility detection)
VOLUME_NAME="${CONTAINER_NAME}-data"

# Set redirect URI, base URL, and environment based on domain type
if [[ "$DOMAIN" == localhost* ]] || [[ "$DOMAIN" == 127.0.0.1* ]]; then
    REDIRECT_URI="http://${DOMAIN}/oauth/google/callback"
    BASE_URL="http://${DOMAIN}"
    ENVIRONMENT="development"
else
    REDIRECT_URI="https://${DOMAIN}/oauth/google/callback"
    BASE_URL="https://${DOMAIN}"
    ENVIRONMENT="production"
fi

echo "Starting Open WebUI for client: ${CLIENT_ID}"
echo "Subdomain: ${SUBDOMAIN}"
echo "Container: ${CONTAINER_NAME}"
echo "Memory Limits: 700MB (hard limit), 600MB (reservation)"
if [[ "$PORT" != "N/A" ]]; then
    echo "Port: ${PORT}"
fi
echo "Domain: ${DOMAIN}"
echo "Environment: ${ENVIRONMENT}"
echo "Docker Image: ghcr.io/imagicrafter/open-webui:${OPENWEBUI_IMAGE_TAG:-main}"
echo "Redirect URI: ${REDIRECT_URI}"

# Create per-client directory structure
echo "Setting up client directory: ${CLIENT_DIR}"
if ! mkdir -p "${CLIENT_DIR}/data"; then
    echo "❌ ERROR: Failed to create ${CLIENT_DIR}/data"
    echo "   Check permissions on /opt/openwebui/"
    exit 1
fi
if ! mkdir -p "${CLIENT_DIR}/static"; then
    echo "❌ ERROR: Failed to create ${CLIENT_DIR}/static"
    echo "   Check permissions on /opt/openwebui/"
    exit 1
fi
echo "✓ Directories created successfully"

# Initialize static assets from defaults if empty
if [ ! -f "${CLIENT_DIR}/static/favicon.png" ]; then
    echo "Initializing static assets from defaults..."
    if [ -d "/opt/openwebui/defaults/static" ]; then
        cp -a /opt/openwebui/defaults/static/. "${CLIENT_DIR}/static/"
        echo "✓ Static assets initialized"
    else
        echo "⚠️  Warning: /opt/openwebui/defaults/static not found"
        echo "   Run: ./setup/lib/extract-default-static.sh"
        echo "   Continuing with empty static directory..."
    fi
else
    echo "✓ Static assets already initialized"
fi

# Check if container already exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Container '${CONTAINER_NAME}' already exists!"
    echo "Use: docker start ${CONTAINER_NAME}"
    exit 1
fi

# Detect if nginx is containerized
NGINX_CONTAINERIZED=false
NETWORK_CONFIG=""
PORT_CONFIG=""

if docker ps --filter "name=openwebui-nginx" --format "{{.Names}}" | grep -q "^openwebui-nginx$"; then
    NGINX_CONTAINERIZED=true
    NETWORK_CONFIG="--network openwebui-network"
    # No port mapping needed for containerized nginx
    echo "✓ Detected containerized nginx - deploying on openwebui-network"
    echo "  (No port mapping needed - container-to-container communication)"
else
    NGINX_CONTAINERIZED=false
    if [[ "$PORT" != "N/A" ]]; then
        PORT_CONFIG="-p ${PORT}:8080"
    fi
    echo "ℹ️  Using host nginx mode - deploying with port mapping"
fi

# Memory limits for multi-container deployments
# - 700MB hard limit: Prevents Python from excessive memory usage
# - 600MB reservation: Triggers garbage collection before hitting limit
# - 1400MB swap: 2x memory (prevents OOM kills, uses host swap space)
# - Allows 2 containers on 2GB droplet, 5 containers on 4GB droplet
docker_cmd="docker run -d \
    --name ${CONTAINER_NAME} \
    --memory=\"700m\" \
    --memory-reservation=\"600m\" \
    --memory-swap=\"1400m\" \
    --health-cmd=\"curl --silent --fail http://localhost:8080/health || exit 1\" \
    --health-interval=10s \
    --health-timeout=5s \
    --health-retries=3 \
    ${PORT_CONFIG} \
    ${NETWORK_CONFIG} \
    -e GOOGLE_CLIENT_ID=1063776054060-2fa0vn14b7ahi1tmfk49cuio44goosc1.apps.googleusercontent.com \
    -e GOOGLE_CLIENT_SECRET=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 \
    -e GOOGLE_REDIRECT_URI=${REDIRECT_URI} \
    -e ENABLE_OAUTH_SIGNUP=true \
    -e OAUTH_ALLOWED_DOMAINS=${OAUTH_DOMAINS} \
    -e OPENID_PROVIDER_URL=https://accounts.google.com/.well-known/openid-configuration \
    -e WEBUI_NAME=\"QuantaBase - ${CLIENT_ID}\" \
    -e WEBUI_SECRET_KEY=\"${WEBUI_SECRET_KEY}\" \
    -e WEBUI_URL=\"${REDIRECT_URI%/oauth/google/callback}\" \
    -e ENABLE_VERSION_UPDATE_CHECK=false \
    -e USER_PERMISSIONS_CHAT_CONTROLS=false \
    -e FQDN=\"${FQDN}\" \
    -e CLIENT_ID=\"${CLIENT_ID}\" \
    -e SUBDOMAIN=\"${SUBDOMAIN}\""

# Add BASE_URL if set (for nginx proxy mode)
if [[ -n "$BASE_URL" ]]; then
    docker_cmd="$docker_cmd -e WEBUI_BASE_URL=${BASE_URL}"
fi

# Use OPENWEBUI_IMAGE_TAG environment variable, default to 'main'
IMAGE_TAG=${OPENWEBUI_IMAGE_TAG:-main}

# Volume mounts: bind mount to host directories for persistence and portability
# - data: SQLite database and user files
# - static: Custom branding assets (SINGLE mount to backend only, not /app/build)
docker_cmd="$docker_cmd \
    -v \"${CLIENT_DIR}/data\":/app/backend/data \
    -v \"${CLIENT_DIR}/static\":/app/backend/open_webui/static \
    --restart unless-stopped \
    ghcr.io/imagicrafter/open-webui:${IMAGE_TAG}"

eval $docker_cmd

if [ $? -eq 0 ]; then
    echo "✅ ${CLIENT_ID} Open WebUI started successfully!"

    if [ "$NGINX_CONTAINERIZED" = true ]; then
        echo "🌐 Access: https://${DOMAIN}"
        echo "   (Container accessible only via nginx - no direct port access)"
    else
        echo "📱 Internal: http://localhost:${PORT}"
        echo "🌐 External: https://${DOMAIN}"
    fi

    echo "📦 Data: ${CLIENT_DIR}/data"
    echo "🎨 Static: ${CLIENT_DIR}/static"
    echo "🐳 Container: ${CONTAINER_NAME}"

    if [ "$NGINX_CONTAINERIZED" = true ]; then
        echo ""
        echo "Next steps:"
        echo "1. Configure nginx for ${DOMAIN} using client-manager.sh option 5"
        echo "2. Set up SSL certificate for ${DOMAIN}"
        echo "3. (Optional) Apply custom branding after container is healthy"
    fi
else
    echo "❌ Failed to start container for ${CLIENT_ID}"
    exit 1
fi