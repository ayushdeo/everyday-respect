#!/usr/bin/env bash
# =============================================================================
# CVAT Azure VM Setup Script
# Repo: https://github.com/ayushdeo/everyday-respect (branch: develop)
# =============================================================================
# Run this on the Azure VM after SSH-ing in:
#   bash <(curl -fsSL https://raw.githubusercontent.com/ayushdeo/everyday-respect/develop/deployment/azure/setup.sh)
#
# Or copy it to the VM and run:
#   chmod +x setup.sh && sudo bash setup.sh
# =============================================================================
set -euo pipefail

REPO_URL="https://github.com/ayushdeo/everyday-respect.git"
REPO_BRANCH="develop"
APP_DIR="/opt/cvat"

log()  { echo -e "\n\033[1;34m[SETUP]\033[0m $*"; }
good() { echo -e "\033[1;32m[OK]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# Must run as root (sudo)
if [ "$(id -u)" -ne 0 ]; then
    err "Please run as root: sudo bash setup.sh"
fi

# ── 1. System packages ────────────────────────────────────────────────────────
log "Installing system dependencies..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    ca-certificates curl gnupg lsb-release git python3 python3-pip ffmpeg
good "System packages installed."

# ── 2. Docker ─────────────────────────────────────────────────────────────────
if command -v docker &>/dev/null; then
    good "Docker already installed: $(docker --version)"
else
    log "Installing Docker..."
    curl -fsSL https://get.docker.com | bash
    systemctl enable docker
    systemctl start docker
    good "Docker installed."
fi

# Ensure Docker Compose v2 plugin
if ! docker compose version &>/dev/null; then
    log "Installing Docker Compose plugin..."
    apt-get install -y -qq docker-compose-plugin
fi
good "Docker Compose: $(docker compose version --short)"

# ── 3. Node.js 20 ────────────────────────────────────────────────────────────
if command -v node &>/dev/null; then
    good "Node.js already installed: $(node --version)"
else
    log "Installing Node.js 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y -qq nodejs
    good "Node.js installed: $(node --version)"
fi

# ── 4. Clone or update repo ───────────────────────────────────────────────────
log "Setting up repository at $APP_DIR..."
# GIT_TERMINAL_PROMPT=0 prevents git from hanging trying to open /dev/tty
# for credentials in headless/non-interactive shells (az run-command, cron, etc.)
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=echo

if [ -d "$APP_DIR/.git" ]; then
    log "Repo exists — pulling latest from $REPO_BRANCH..."
    git -C "$APP_DIR" -c credential.helper= fetch origin "$REPO_BRANCH" 2>&1 || true
    git -C "$APP_DIR" checkout "$REPO_BRANCH"
    git -C "$APP_DIR" -c credential.helper= pull origin "$REPO_BRANCH"
else
    log "Cloning repository (branch: $REPO_BRANCH)..."
    if ! git clone \
            -c credential.helper= \
            --branch "$REPO_BRANCH" \
            "$REPO_URL" \
            "$APP_DIR"; then
        echo ""
        echo "ERROR: git clone failed. This usually means the repo is private."
        echo "Fix one of:"
        echo "  A) Make the repo public: github.com/ayushdeo/everyday-respect -> Settings -> Change visibility -> Public"
        echo "  B) Use a token URL: export REPO_URL=https://<TOKEN>@github.com/ayushdeo/everyday-respect.git"
        echo ""
        exit 1
    fi
fi
good "Repository ready at $APP_DIR"

# ── 5. Detect public IP and write .env ───────────────────────────────────────
log "Detecting VM public IP..."

# Priority 1: explicit argument passed by caller (az run-command --parameters)
PUBLIC_IP="${1:-}"

# Priority 2: Azure IMDS (works when SSH'd in; may not work via az run-command)
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -s --connect-timeout 3 \
        -H "Metadata:true" \
        "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text" \
        2>/dev/null || true)
fi

# Priority 3: external IP lookup
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -s --connect-timeout 5 https://ifconfig.me 2>/dev/null || true)
fi

# Priority 4: first non-loopback NIC address
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(hostname -I | awk '{print $1}')
fi

if [ -z "$PUBLIC_IP" ]; then
    err "Could not detect public IP. Pass it explicitly: bash setup.sh <YOUR_IP>"
fi
good "Public IP: $PUBLIC_IP"

log "Writing .env file..."
SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
cat > "$APP_DIR/.env" <<ENV
CVAT_HOST=$PUBLIC_IP
DJANGO_SECRET_KEY=$SECRET
CVAT_VERSION=dev
ENV
good ".env written with CVAT_HOST=$PUBLIC_IP"

# ── 6. Build backend image ────────────────────────────────────────────────────
log "Building CVAT backend image (cvat/server:dev) — takes ~3 min..."
docker build \
    -f "$APP_DIR/Dockerfile" \
    -t cvat/server:dev \
    "$APP_DIR" \
    2>&1 | tail -20
good "Backend image built."

# ── 7. Build UI image (includes audio player modifications) ──────────────────
log "Building CVAT UI image (cvat/ui:dev) — takes ~5 min..."
export NODE_OPTIONS="--max_old_space_size=4096"
export DISABLE_SOURCE_MAPS=true
docker build \
    -f "$APP_DIR/Dockerfile.ui" \
    -t cvat/ui:dev \
    "$APP_DIR" \
    2>&1 | tail -20
good "UI image built."

# ── 8. Start all services via Docker Compose ─────────────────────────────────
log "Starting CVAT services..."
cd "$APP_DIR"
docker compose \
    -f docker-compose.yml \
    -f deployment/azure/docker-compose.azure.yml \
    --env-file .env \
    up -d
good "Services started."

# ── 9. Wait for backend to be ready ──────────────────────────────────────────
log "Waiting for backend to become healthy (up to 90s)..."
for i in $(seq 1 18); do
    if docker exec cvat_server python manage.py check 2>/dev/null; then
        good "Backend is healthy."
        break
    fi
    echo "  Waiting... ($i/18)"
    sleep 5
done

# ── 10. Create admin superuser ────────────────────────────────────────────────
log "Creating admin superuser..."
docker exec \
    -e DJANGO_SUPERUSER_PASSWORD=cvat2024demo \
    cvat_server \
    python manage.py createsuperuser \
        --username admin \
        --email admin@example.com \
        --noinput \
    2>/dev/null && good "Superuser created." || good "Superuser already exists."

# ── 11. Open port 80 in Ubuntu firewall (ufw) if active ──────────────────────
if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    log "Opening port 80 in ufw..."
    ufw allow 80/tcp
    good "Port 80 allowed in ufw."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  CVAT with Audio Feature is RUNNING!"
echo "============================================================"
echo "  URL:      http://$PUBLIC_IP"
echo "  Username: admin"
echo "  Password: cvat2024demo"
echo ""
echo "  Monitor services:"
echo "    cd $APP_DIR"
echo "    docker compose logs -f cvat_server cvat_worker_import"
echo ""
echo "  Stop everything:"
echo "    docker compose -f docker-compose.yml -f deployment/azure/docker-compose.azure.yml down"
echo "============================================================"
