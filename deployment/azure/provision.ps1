#!/usr/bin/env pwsh
# =============================================================================
# Provision Azure VM and deploy CVAT with Audio Feature
# Windows-compatible — uses az vm run-command (no scp/ssh required)
# =============================================================================
param(
    [string]$ResourceGroup = "cvat-demo-rg",
    [string]$Location      = "eastus",
    [string]$VmName        = "cvat-demo-vm",
    [string]$VmSize        = "Standard_B2s",
    [string]$AdminUser     = "azureuser",
    [string]$AdminPassword = "CvatDemo2024!",
    [string]$DnsLabel      = ("cvatdemo" + ([System.Guid]::NewGuid().ToString("N").Substring(0,6)))
)

$ErrorActionPreference = "Stop"

function Log($msg)  { Write-Host "[PROVISION] $msg" -ForegroundColor Cyan }
function Good($msg) { Write-Host "[OK]        $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[WARN]      $msg" -ForegroundColor Yellow }

# ── 1. Check az CLI ───────────────────────────────────────────────────────────
Log "Checking Azure CLI..."
$azCheck = Get-Command az -ErrorAction SilentlyContinue
if (-not $azCheck) {
    Write-Host "ERROR: Azure CLI not on PATH. Close this terminal, open a NEW one, and retry." -ForegroundColor Red
    exit 1
}
Good "Azure CLI found at: $($azCheck.Source)"

# ── 2. Check login ────────────────────────────────────────────────────────────
Log "Checking Azure login..."
$accountJson = az account show --output json 2>$null
if ($LASTEXITCODE -ne 0 -or -not $accountJson) {
    Log "Not logged in. Running az login..."
    az login
    $accountJson = az account show --output json
}
$account = $accountJson | ConvertFrom-Json
Good "Logged in: $($account.user.name) | Subscription: $($account.name)"

# ── 3. Clean up any previous failed attempt ───────────────────────────────────
Log "Checking if VM already exists from a previous run..."
$existingVm = az vm show --resource-group $ResourceGroup --name $VmName --output json 2>$null
if ($existingVm) {
    Warn "VM already exists. Fetching its IP..."
    $PublicIp = (az vm list-ip-addresses `
        --resource-group $ResourceGroup `
        --name $VmName `
        --output json | ConvertFrom-Json)[0].virtualMachine.network.publicIpAddresses[0].ipAddress
    Good "Reusing existing VM at: $PublicIp"
} else {
    # ── 4. Resource group ─────────────────────────────────────────────────────
    Log "Creating resource group: $ResourceGroup..."
    az group create --name $ResourceGroup --location $Location --output none
    Good "Resource group ready."

    # ── 5. Create VM (password auth — avoids Windows SSH key generation bug) ──
    Log "Creating VM $VmName ($VmSize) with password auth..."
    Log "This takes ~2 minutes..."

    $VmJson = az vm create `
        --resource-group $ResourceGroup `
        --name $VmName `
        --image Ubuntu2204 `
        --size $VmSize `
        --admin-username $AdminUser `
        --admin-password $AdminPassword `
        --authentication-type password `
        --public-ip-sku Standard `
        --public-ip-address-dns-name $DnsLabel `
        --output json

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: VM creation failed. Check az error above." -ForegroundColor Red
        exit 1
    }

    $Vm = $VmJson | ConvertFrom-Json
    $PublicIp = $Vm.publicIpAddress
    Good "VM created. Public IP: $PublicIp"
}

$FQDN = "$DnsLabel.$Location.cloudapp.azure.com"

# ── 6. Open port 80 ───────────────────────────────────────────────────────────
Log "Opening port 80..."
az vm open-port `
    --resource-group $ResourceGroup `
    --name $VmName `
    --port 80 `
    --priority 1001 `
    --output none
Good "Port 80 open."

# ── 7. Deploy CVAT via Azure run-command (no scp/ssh needed!) ─────────────────
# az vm run-command invokes a bash script on the VM through the Azure API.
# Much more reliable on Windows than scp + ssh.

Log "Running setup on VM via Azure run-command (this takes 10-15 minutes)..."
Log "You can watch progress in Azure Portal > VM > Run command"

$SetupCommands = @"
#!/bin/bash
set -euo pipefail

REPO_URL="https://github.com/ayushdeo/everyday-respect.git"
REPO_BRANCH="develop"
APP_DIR="/opt/cvat"

echo "[1/8] Installing system dependencies..."
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg git python3 python3-pip

echo "[2/8] Installing Docker..."
curl -fsSL https://get.docker.com | bash
systemctl enable docker
systemctl start docker

echo "[3/8] Installing Docker Compose plugin..."
apt-get install -y docker-compose-plugin

echo "[4/8] Installing Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

echo "[5/8] Cloning repository..."
if [ -d "$APP_DIR" ]; then
  cd "$APP_DIR" && git fetch origin "$REPO_BRANCH" && git checkout "$REPO_BRANCH" && git pull
else
  git clone --branch "$REPO_BRANCH" "$REPO_URL" "$APP_DIR"
fi
cd "$APP_DIR"

echo "[6/8] Configuring environment..."
PUBLIC_IP=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text" 2>/dev/null || hostname -I | awk '{print $1}')
SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
cat > .env <<ENV
CVAT_HOST=$PUBLIC_IP
DJANGO_SECRET_KEY=$SECRET
CVAT_VERSION=dev
ENV
echo "CVAT_HOST set to: $PUBLIC_IP"

echo "[7/8] Building Docker images (takes 5-8 min)..."
export NODE_OPTIONS="--max_old_space_size=4096"
export DISABLE_SOURCE_MAPS=true
docker build -f Dockerfile -t cvat/server:dev . 2>&1 | tail -5
docker build -f Dockerfile.ui -t cvat/ui:dev . 2>&1 | tail -5

echo "[8/8] Starting CVAT services..."
docker compose -f docker-compose.yml -f deployment/azure/docker-compose.azure.yml --env-file .env up -d

echo "Waiting for backend to be ready..."
sleep 30
docker exec cvat_server python manage.py check --deploy 2>/dev/null || true

echo "Creating admin superuser..."
docker exec -e DJANGO_SUPERUSER_PASSWORD=cvat2024demo cvat_server \
  python manage.py createsuperuser --username admin --email admin@example.com --noinput 2>/dev/null || true

echo "DONE. CVAT is running at http://$PUBLIC_IP"
"@

$result = az vm run-command invoke `
    --resource-group $ResourceGroup `
    --name $VmName `
    --command-id RunShellScript `
    --scripts $SetupCommands `
    --output json | ConvertFrom-Json

$output = $result.value | Where-Object { $_.code -eq "ComponentStatus/StdOut/succeeded" } | Select-Object -ExpandProperty message
$errors = $result.value | Where-Object { $_.code -eq "ComponentStatus/StdErr/succeeded" } | Select-Object -ExpandProperty message

Write-Host ""
Write-Host "--- VM Output ---" -ForegroundColor Gray
Write-Host $output
if ($errors) {
    Write-Host "--- Stderr (warnings/logs, usually OK) ---" -ForegroundColor Yellow
    Write-Host $errors
}

# ── 8. Summary ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host "  Deployment complete!" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host "  URL:       http://$PublicIp" -ForegroundColor Green
Write-Host "  FQDN:      http://$FQDN" -ForegroundColor Green
Write-Host "  Username:  admin" -ForegroundColor Green
Write-Host "  Password:  cvat2024demo" -ForegroundColor Green
Write-Host ""
Write-Host "  SSH into VM:" -ForegroundColor White
Write-Host "    ssh ${AdminUser}@${PublicIp}" -ForegroundColor White
Write-Host "    (VM password: $AdminPassword)" -ForegroundColor White
Write-Host ""
Write-Host "  To delete everything when done:" -ForegroundColor Yellow
Write-Host "    az group delete --name $ResourceGroup --yes --no-wait" -ForegroundColor Yellow
Write-Host "====================================================" -ForegroundColor Green
