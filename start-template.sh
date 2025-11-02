#!/bin/bash

# =============================================================================
# Open WebUI Multi-Client Template Script (Phase 2)
# =============================================================================
# Deploys isolated Open WebUI instances using official upstream images.
#
# Usage: ./start-template.sh SUBDOMAIN PORT DOMAIN CONTAINER_NAME FQDN [OAUTH_DOMAINS] [WEBUI_SECRET_KEY]
#
# Examples:
#   ./start-template.sh chat 8081 chat.client-a.com openwebui-chat-client-a-com chat.client-a.com
#   ./start-template.sh chat 8082 localhost:8082 openwebui-localhost-8082 localhost:8082 martins.net SECRET_KEY
#
# Environment Variables:
#   OPENWEBUI_IMAGE_TAG     - Image version (latest, main, v0.5.1)
#   OPENWEBUI_FULL_IMAGE    - Full image reference (overrides IMAGE + TAG)
# =============================================================================

# Load configuration and libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/setup/lib/colors.sh" 2>/dev/null || {
    # Fallback if colors.sh not available
    success() { echo "✓ $*"; }
    error() { echo "✗ $*" >&2; }
    warning() { echo "⚠ $*"; }
    info() { echo "ℹ $*"; }
}

source "${SCRIPT_DIR}/setup/lib/config.sh" 2>/dev/null || {
    error "Failed to load configuration library"
    error "Make sure setup/lib/config.sh exists"
    exit 1
}

# Load global configuration
load_global_config || {
    error "Failed to load global configuration"
    exit 1
}

# Validate arguments
if [ $# -lt 5 ]; then
    error "Insufficient arguments"
    echo ""
    echo "Usage: $0 SUBDOMAIN PORT DOMAIN CONTAINER_NAME FQDN [OAUTH_DOMAINS] [WEBUI_SECRET_KEY]"
    echo ""
    echo "Examples:"
    echo "  $0 chat 8081 chat.client-a.com openwebui-chat-client-a-com chat.client-a.com"
    echo "  $0 chat 8082 localhost:8082 openwebui-localhost-8082 localhost:8082 martins.net SECRET_KEY"
    echo ""
    echo "Environment Variables:"
    echo "  OPENWEBUI_IMAGE_TAG=latest    # Use latest stable release"
    echo "  OPENWEBUI_IMAGE_TAG=main      # Use development version"
    echo "  OPENWEBUI_IMAGE_TAG=v0.5.1    # Use specific version"
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

# Per-client directory for volume mounts (uses CLIENT_ID from config)
CLIENT_DIR="${BASE_DIR}/${CLIENT_ID}"

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

# Validate that image tag is set
if [ -z "$OPENWEBUI_IMAGE_TAG" ]; then
    error "OPENWEBUI_IMAGE_TAG is not set"
    echo ""
    warning "You must set the Open WebUI image version:"
    echo "  export OPENWEBUI_IMAGE_TAG=latest    # Latest stable (recommended)"
    echo "  export OPENWEBUI_IMAGE_TAG=main      # Development version"
    echo "  export OPENWEBUI_IMAGE_TAG=v0.5.1    # Specific version"
    echo ""
    exit 1
fi

header "Starting Open WebUI Deployment"
echo "Client:       ${CLIENT_ID}"
echo "Subdomain:    ${SUBDOMAIN}"
echo "Container:    ${CONTAINER_NAME}"
echo "Memory:       ${DEFAULT_MEMORY_LIMIT} (limit), ${DEFAULT_MEMORY_RESERVATION} (reservation)"
if [[ "$PORT" != "N/A" ]]; then
    echo "Port:         ${PORT}"
fi
echo "Domain:       ${DOMAIN}"
echo "Environment:  ${ENVIRONMENT}"
echo "Image:        ${OPENWEBUI_FULL_IMAGE}"
echo "Redirect URI: ${REDIRECT_URI}"
separator

# Create per-client directory structure using library function
step "Setting up client directory: ${CLIENT_DIR}"
if ! init_client_directory "$CLIENT_ID"; then
    error "Failed to initialize client directory"
    exit 1
fi

# Check if container already exists using library function
if container_exists "$CONTAINER_NAME"; then
    error "Container '${CONTAINER_NAME}' already exists!"
    info "Use: docker start ${CONTAINER_NAME}"
    exit 1
fi

# Detect if nginx is containerized
NGINX_CONTAINERIZED=false
NETWORK_CONFIG=""
PORT_CONFIG=""

if docker ps --filter "name=openwebui-nginx" --format "{{.Names}}" | grep -q "^openwebui-nginx$"; then
    NGINX_CONTAINERIZED=true
    NETWORK_CONFIG="--network ${NETWORK_NAME:-openwebui-network}"
    # No port mapping needed for containerized nginx
    success "Detected containerized nginx - deploying on network"
    info "(No port mapping needed - container-to-container communication)"
else
    NGINX_CONTAINERIZED=false
    if [[ "$PORT" != "N/A" ]]; then
        PORT_CONFIG="-p ${PORT}:8080"
    fi
    info "Using host nginx mode - deploying with port mapping"
fi

# Build Docker command using configuration from global.conf
step "Building Docker deployment command"

docker_cmd="docker run -d \
    --name ${CONTAINER_NAME} \
    --memory=\"${DEFAULT_MEMORY_LIMIT}\" \
    --memory-reservation=\"${DEFAULT_MEMORY_RESERVATION}\" \
    --memory-swap=\"${DEFAULT_MEMORY_SWAP}\" \
    --health-cmd=\"${DEFAULT_HEALTH_CMD}\" \
    --health-interval=${DEFAULT_HEALTH_INTERVAL} \
    --health-timeout=${DEFAULT_HEALTH_TIMEOUT} \
    --health-retries=${DEFAULT_HEALTH_RETRIES} \
    ${PORT_CONFIG} \
    ${NETWORK_CONFIG} \
    -e GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID:-1063776054060-2fa0vn14b7ahi1tmfk49cuio44goosc1.apps.googleusercontent.com} \
    -e GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET:-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} \
    -e GOOGLE_REDIRECT_URI=${REDIRECT_URI} \
    -e ENABLE_OAUTH_SIGNUP=${ENABLE_OAUTH_SIGNUP} \
    -e OAUTH_ALLOWED_DOMAINS=${OAUTH_DOMAINS} \
    -e OPENID_PROVIDER_URL=${OPENID_PROVIDER_URL} \
    -e WEBUI_NAME=\"${DEFAULT_WEBUI_NAME} - ${CLIENT_ID}\" \
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

# Volume mounts: bind mount to host directories for persistence and portability
# Uses configuration paths from global.conf
docker_cmd="$docker_cmd \
    -v \"${CLIENT_DIR}/data\":${CONTAINER_DATA_PATH} \
    -v \"${CLIENT_DIR}/static\":${CONTAINER_STATIC_PATH} \
    --restart ${DEFAULT_RESTART_POLICY} \
    ${OPENWEBUI_FULL_IMAGE}"

step "Deploying container..."
eval $docker_cmd

if [ $? -eq 0 ]; then
    echo ""
    success "${CLIENT_ID} Open WebUI started successfully!"
    echo ""

    if [ "$NGINX_CONTAINERIZED" = true ]; then
        info "Access URL: https://${DOMAIN}"
        info "(Container accessible only via nginx - no direct port access)"
    else
        info "Internal URL: http://localhost:${PORT}"
        info "External URL: https://${DOMAIN}"
    fi

    echo ""
    echo "📦 Data:      ${CLIENT_DIR}/data"
    echo "🎨 Static:    ${CLIENT_DIR}/static"
    echo "🐳 Container: ${CONTAINER_NAME}"
    echo "🖼️  Image:     ${OPENWEBUI_FULL_IMAGE}"
    echo ""

    if [ "$NGINX_CONTAINERIZED" = true ]; then
        subheader "Next Steps:"
        bullet "Configure nginx for ${DOMAIN} using client-manager.sh option 5"
        bullet "Set up SSL certificate for ${DOMAIN}"
        bullet "(Optional) Apply custom branding after container is healthy"
    else
        subheader "Next Steps:"
        bullet "Configure nginx reverse proxy for ${DOMAIN}"
        bullet "Set up SSL certificate"
        bullet "(Optional) Apply custom branding: ./setup/scripts/asset_management/apply-branding.sh ${CLIENT_ID}"
    fi
    echo ""
else
    error "Failed to start container for ${CLIENT_ID}"
    exit 1
fi