# Open WebUI Infrastructure

> **Production-ready multi-tenant deployment infrastructure for [Open WebUI](https://github.com/open-webui/open-webui)**

## ⚡ Quick Start

```bash
# Clone this repository
git clone https://github.com/imagicrafter/open-webui-infrastructure.git
cd open-webui-infrastructure

# Run automated setup
./setup/quick-setup.sh

# Or deploy a single client manually
./start-template.sh my-client 8080 my-domain.com
```

## 📖 Overview

This standalone infrastructure toolkit enables **production-ready, multi-tenant deployments** of [Open WebUI](https://github.com/open-webui/open-webui) using official upstream Docker images. Deploy multiple isolated Open WebUI instances on a single server or across multiple hosts for SaaS offerings, enterprise deployments, or managed hosting.

### Why This Infrastructure?

**Separated from the Application**: This infrastructure works with **official Open WebUI images** from `ghcr.io/open-webui/open-webui` - no fork required! Choose your Open WebUI version (latest stable, development, or pinned version) and let the infrastructure handle deployment, isolation, and management.

**Production-Ready**: Deploy confidently with automated SSL, OAuth integration, custom branding, and comprehensive management tools.

**Multi-Tenant by Design**: Each client gets complete isolation with dedicated containers, data volumes, and custom configurations.

## ✨ Key Features

### 🔐 Complete Client Isolation
- **Dedicated Containers**: Separate Docker containers per client with resource limits
- **Isolated Data**: Per-client SQLite databases, uploads, and user settings
- **Custom Branding**: Client-specific logos, favicons, and application names
- **Custom Domains**: Each deployment can use its own domain or subdomain

### 🚀 Flexible Image Selection
- **Latest Stable**: `ghcr.io/open-webui/open-webui:latest` (recommended for production)
- **Development**: `ghcr.io/open-webui/open-webui:main` (bleeding edge features)
- **Pinned Versions**: `ghcr.io/open-webui/open-webui:v0.5.1` (version locking)
- **Custom Images**: Bring your own fork or modified image

### 🛠️ Production Infrastructure
- **Automated Setup**: Single-command server provisioning with `quick-setup.sh`
- **Interactive Management**: `client-manager.sh` provides menu-driven operations
- **Dual nginx Modes**: Systemd-based (production) or containerized (testing)
- **SSL Automation**: Let's Encrypt integration with automatic renewal
- **OAuth Ready**: Pre-configured Google OAuth with domain restrictions

### 📊 Advanced Capabilities
- **Database Migration**: Built-in SQLite → PostgreSQL migration tools
- **High Availability**: Sync system with leader election and failover (experimental)
- **Persistent Branding**: Volume-mounted static assets survive container recreation
- **Testing Suite**: Comprehensive security, failover, and integration tests

## 🏗️ Architecture

### Directory Structure
```
/opt/openwebui/               # Base directory for all deployments
├── defaults/
│   └── static/               # Default Open WebUI assets (extracted once)
├── client-a/
│   ├── data/                 # SQLite DB, uploads, cache
│   └── static/               # Custom branding assets
├── client-b/
│   ├── data/
│   └── static/
└── ...
```

### Container Deployment
```
┌─────────────────────────────────────────┐
│  Host Server (Ubuntu 24.04)             │
│                                          │
│  ┌────────────────┐  ┌────────────────┐│
│  │  openwebui-    │  │  openwebui-    ││
│  │  client-a      │  │  client-b      ││
│  │                │  │                ││
│  │  Port: 8081    │  │  Port: 8082    ││
│  │  Image: upstream│  │  Image: upstream││
│  │                │  │                ││
│  │  Volumes:      │  │  Volumes:      ││
│  │  - client-a/   │  │  - client-b/   ││
│  │    data        │  │    data        ││
│  │  - client-a/   │  │  - client-b/   ││
│  │    static      │  │    static      ││
│  └────────────────┘  └────────────────┘│
│                                          │
│  ┌────────────────────────────────────┐ │
│  │  nginx (systemd service)           │ │
│  │  - Reverse proxy with SSL          │ │
│  │  - client-a.yourdomain.com → 8081  │ │
│  │  - client-b.yourdomain.com → 8082  │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

## 📦 Installation

### Prerequisites
- **Operating System**: Ubuntu 24.04 LTS (recommended) or Ubuntu 22.04 LTS
- **Docker**: Version 20.10+ with Docker Compose v2
- **Domain**: For SSL certificates (optional for local testing)
- **Resources**: 2GB+ RAM per client instance, 10GB+ disk space

### Quick Installation

**Option 1: Automated Setup (Recommended)**
```bash
# Clone repository
git clone https://github.com/imagicrafter/open-webui-infrastructure.git
cd open-webui-infrastructure

# Run quick setup (interactive)
./setup/quick-setup.sh

# Follow prompts to configure:
# - Server type (test/production)
# - Open WebUI version (latest/main/specific)
# - OAuth credentials (optional)
# - SSL certificates (optional)
```

**Option 2: Manual Client Deployment**
```bash
# Deploy a single client
./start-template.sh \
  my-client \          # Client name
  8080 \               # Port
  my-domain.com \      # Domain
  openwebui-my-client \# Container name
  my-domain.com        # OAuth domain (optional)

# Access at http://localhost:8080
```

## 🎯 Usage Examples

### Deploy Multiple Clients
```bash
# Deploy client A
./start-template.sh client-a 8081 client-a.example.com

# Deploy client B with different Open WebUI version
OPENWEBUI_IMAGE_TAG="v0.5.1" ./start-template.sh client-b 8082 client-b.example.com

# Apply custom branding to client A
cd setup/lib
./apply-branding.sh client-a https://example.com/logo.png
```

### Manage Deployments
```bash
# Launch interactive manager
./client-manager.sh

# Available operations:
# 1. List all deployments
# 2. Create new deployment
# 3. Stop/Start/Restart deployments
# 4. View logs and health status
# 5. Manage nginx configuration
# 6. Apply branding
# 7. Database migration
# 8. And more...
```

### Switch Open WebUI Versions
```bash
# Update to latest stable
export OPENWEBUI_IMAGE_TAG="latest"

# Recreate container (preserves data via volumes)
docker stop openwebui-my-client
docker rm openwebui-my-client
./start-template.sh my-client 8080 my-domain.com
```

## 🔧 Configuration

### Central Configuration
All infrastructure settings are centralized in `config/global.conf` (created during setup):

```bash
# Open WebUI Image Configuration
OPENWEBUI_IMAGE="ghcr.io/open-webui/open-webui"
OPENWEBUI_IMAGE_TAG="latest"  # or "main", "v0.5.1", etc.

# Base Directories
BASE_DIR="/opt/openwebui"
DEFAULTS_DIR="${BASE_DIR}/defaults"

# Container Defaults
DEFAULT_MEMORY_LIMIT="700m"
DEFAULT_MEMORY_RESERVATION="600m"
DEFAULT_MEMORY_SWAP="1400m"

# Network Configuration
NETWORK_NAME="openwebui-network"
```

### Environment Variables
Override configuration per deployment:
```bash
# Use specific Open WebUI version
OPENWEBUI_IMAGE_TAG="v0.5.1" ./start-template.sh my-client 8080

# Use custom image (e.g., your fork)
OPENWEBUI_FULL_IMAGE="ghcr.io/yourname/open-webui:custom" ./start-template.sh my-client 8080
```

### OAuth Configuration
Configure Google OAuth in `.env` or during quick-setup:
```bash
GOOGLE_CLIENT_ID="your_client_id_here"
GOOGLE_CLIENT_SECRET="your_secret_here"
OAUTH_ALLOWED_DOMAINS="yourdomain.com"
```

## 📚 Documentation

- **[ARCHITECTURE.md](ARCHITECTURE.md)** - System design and technical decisions
- **[COMPATIBILITY.md](COMPATIBILITY.md)** - Tested Open WebUI versions
- **[MIGRATION_GUIDE.md](migration/MIGRATION_GUIDE.md)** - Migrate from fork-based deployments
- **[QUICKSTART-FRESH-DEPLOYMENT.md](QUICKSTART-FRESH-DEPLOYMENT.md)** - Detailed deployment guide
- **[REFACTOR_PLAN.md](REFACTOR_PLAN.md)** - Infrastructure evolution roadmap

## 🎨 Custom Branding

Apply custom logos and branding that persist across container updates:

```bash
# From URL
./setup/lib/apply-branding.sh my-client https://example.com/logo.png

# From local file
./setup/lib/apply-branding.sh my-client /path/to/logo.png

# Text-based logo (generates image from text)
./setup/lib/apply-branding.sh my-client "MyBrand" --text

# Branding is stored in /opt/openwebui/my-client/static/
# and survives container recreation via volume mounts
```

## 🔄 Database Migration

Migrate from SQLite to PostgreSQL/Supabase:

```bash
# Via client-manager.sh
./client-manager.sh
# → Choose "Database Migration" → "Migrate to PostgreSQL"

# Or directly
cd DB_MIGRATION
./migrate-open-webui.sh \
  openwebui-my-client \
  "postgresql://user:pass@host:5432/db"
```

## 🧪 Testing

Run comprehensive integration tests:

```bash
cd tests/integration
./test-full-deployment.sh

# Specific test suites
./test-security.sh       # Security validation
./test-failover.sh       # HA sync testing
./test-migration.sh      # Database migration testing
```

## 🛡️ Security Features

- **Container Isolation**: Dedicated containers with resource limits
- **Network Segmentation**: Optional Docker networks per client
- **OAuth Domain Restrictions**: Limit access to specific email domains
- **Automated SSL**: Let's Encrypt certificates with auto-renewal
- **Credential Management**: Secure credential storage outside containers
- **Regular Updates**: Easy version updates via image tag changes

## 🔗 Related Projects

- **[Open WebUI](https://github.com/open-webui/open-webui)** - The upstream application
- **[Open WebUI Documentation](https://docs.openwebui.com)** - Official docs

## 📋 Requirements

### Minimum System Requirements (per client)
- **CPU**: 1 core
- **RAM**: 512MB (1GB recommended)
- **Disk**: 2GB (10GB recommended for chat history)

### Recommended Production Server
- **CPU**: 4+ cores
- **RAM**: 8GB+ (for 5-10 clients)
- **Disk**: 100GB+ SSD
- **Network**: Static IP, domain name

## 🤝 Contributing

Contributions are welcome! This infrastructure toolkit is independent of the Open WebUI application:

1. Fork this repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

- **[Open WebUI Team](https://github.com/open-webui/open-webui)** - For the excellent upstream application
- Built with ❤️ for the Open WebUI community

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/imagicrafter/open-webui-infrastructure/issues)
- **Discussions**: [GitHub Discussions](https://github.com/imagicrafter/open-webui-infrastructure/discussions)
- **Open WebUI**: [Official Docs](https://docs.openwebui.com)

---

**Note**: This infrastructure toolkit is designed to work with official Open WebUI images and is maintained independently of the Open WebUI project.
