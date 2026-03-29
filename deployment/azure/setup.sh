#!/usr/bin/env bash
# =============================================================================
# CVAT Azure VM Setup Script
# =============================================================================
# Architecture: Standard_B2s VM (2 vCPU, 4 GB RAM) — Ubuntu 22.04 LTS
# Runs CVAT via Docker Compose with all Part A audio modifications preserved.
# All services (UI + backend) are served on port 80 through Traefik — no split.
#
# Usage (run on VM after SSH):
#   chmod +x setup.sh && ./setup.sh
# =============================================================================
set -euo pipefail

REPO_URL="https://github.com/ayushdeo/everyday-respect.git"
REPO_BRANCH="develop"
APP_DIR="/opt/cvat"
COMPOSE_CMD="docker compose"

log() { echo -e "\n\033[1;34m[SETUP]\033[0m $*"; }
err() { echo -e "\n\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# ── 1. System dependencies ────────────────────────────────────────────────────
log "Installing system dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    ca-certificates curl gnupg lsb-release git \
    python3 python3-pip ffmpeg

# ── 2. Docker ─────────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    log "Installing Docker..."
    curl -fsSL https://get.docker.com | sudo bash
    sudo usermod -aG docker "$USER"
    log "Docker installed. You may need to log out and back in for group changes."
else
    log "Docker already installed: $(docker --version)"
fi

# Ensure Docker Compose v2 plugin is available
if ! docker compose version &>/dev/null; then
    log "Installing Docker Compose plugin..."
    sudo apt-get install -y docker-compose-plugin
fi

# ── 3. Node.js (needed to build the UI) ────────────────────────────────────────
if ! command -v node &>/dev/null; then
    log "Installing Node.js 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

# ── 4. Clone repo ────────────────────────────────────────────────────────────
log "Cloning repository..."
if [ -d "$APP_DIR" ]; then
    log "Directory $APP_DIR already exists — pulling latest..."
    cd "$APP_DIR"
    git fetch origin "$REPO_BRANCH"
    git checkout "$REPO_BRANCH"
    git pull origin "$REPO_BRANCH"
else
    sudo git clone --branch "$REPO_BRANCH" "$REPO_URL" "$APP_DIR"
    sudo chown -R "$USER":"$USER" "$APP_DIR"
    cd "$APP_DIR"
fi

# ── 5. Environment config ─────────────────────────────────────────────────────
log "Configuring environment..."
cd "$APP_DIR"

if [ ! -f .env ]; then
    cp deployment/azure/.env.example .env
    # Auto-detect the public IP from Azure IMDS
    PUBLIC_IP=$(curl -s -H "Metadata:true" \
        "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text" \
        2>/dev/null || echo "")
    
    if [ -n "$PUBLIC_IP" ]; then
        sed -i "s/YOUR_VM_PUBLIC_IP_HERE/$PUBLIC_IP/" .env
        log "Auto-detected public IP: $PUBLIC_IP"
    else
        echo ""
        echo "⚠️  Could not auto-detect public IP. Please edit .env and set CVAT_HOST manually:"
        echo "   nano $APP_DIR/.env"
        echo ""
    fi
    
    # Generate a random secret key
    SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    sed -i "s/change-me-please/$SECRET/" .env
    log "Generated new DJANGO_SECRET_KEY"
fi

# ── 6. Build UI image (with audio modifications) ─────────────────────────────
log "Building CVAT UI image (this takes ~5 minutes)..."
# Increase Node.js memory limit for the build (carry-over from Part A)
export NODE_OPTIONS="--max_old_space_size=4096"
export DISABLE_SOURCE_MAPS=true

docker build \
    --build-arg DJANGO_SECRET_KEY="$(grep DJANGO_SECRET_KEY .env | cut -d= -f2)" \
    -f Dockerfile.ui \
    -t cvat/ui:dev \
    .

# ── 7. Build backend image ────────────────────────────────────────────────────
log "Building CVAT backend image (this takes ~3 minutes)..."
docker build \
    -f Dockerfile \
    -t cvat/server:dev \
    .

# ── 8. Start services ─────────────────────────────────────────────────────────
log "Starting CVAT services..."
$COMPOSE_CMD \
    -f docker-compose.yml \
    -f deployment/azure/docker-compose.azure.yml \
    --env-file .env \
    up -d

# ── 9. Create superuser ───────────────────────────────────────────────────────
log "Waiting for backend to be healthy (up to 60s)..."
for i in $(seq 1 12); do
    if docker exec cvat_server python manage.py check --deploy 2>/dev/null; then
        break
    fi
    echo "  attempt $i/12..."
    sleep 5
done

log "Creating admin superuser..."
docker exec -e DJANGO_SUPERUSER_PASSWORD=cvat2024demo \
    cvat_server python manage.py createsuperuser \
    --username admin \
    --email admin@example.com \
    --noinput \
    2>/dev/null || log "Superuser already exists — skipping"

# ── 10. Summary ───────────────────────────────────────────────────────────────
PUBLIC_IP=$(grep CVAT_HOST .env | cut -d= -f2)
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║            CVAT (Audio Feature) is RUNNING!              ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  URL:       http://$PUBLIC_IP"
echo "║  Username:  admin"
echo "║  Password:  cvat2024demo"
echo "║                                                          ║"
echo "║  To stream logs:                                         ║"
echo "║    docker compose logs -f cvat_server cvat_worker_import ║"
echo "║                                                          ║"
echo "║  To stop:                                                ║"
echo "║    docker compose -f docker-compose.yml                  ║"
echo "║      -f deployment/azure/docker-compose.azure.yml down   ║"
echo "╚══════════════════════════════════════════════════════════╝"
