#!/usr/bin/env pwsh
# =============================================================================
# Provision Azure VM and deploy CVAT with Audio Feature
# =============================================================================
# Run this LOCALLY from PowerShell (requires Azure CLI: https://aka.ms/install-azure-cli)
# Usage: ./provision.ps1
# Estimated cost: ~$0.05/hr (Standard_B2s), well within free student credits.
# =============================================================================

param(
    [string]$ResourceGroup  = "cvat-demo-rg",
    [string]$Location       = "eastus",
    [string]$VmName         = "cvat-demo-vm",
    [string]$VmSize         = "Standard_B2s",        # 2 vCPU, 4 GB RAM
    [string]$AdminUser      = "azureuser",
    [string]$DnsLabel       = "cvatdemo-$([System.Guid]::NewGuid().ToString('N').Substring(0,6))"
)

$ErrorActionPreference = "Stop"

function Log($msg) { Write-Host "`n[PROVISION] $msg" -ForegroundColor Cyan }

# ── 1. Login check ────────────────────────────────────────────────────────────
Log "Checking Azure CLI login..."
az account show --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    Log "Not logged in. Running az login..."
    az login
}

# ── 2. Resource group ─────────────────────────────────────────────────────────
Log "Creating resource group: $ResourceGroup in $Location"
az group create `
    --name $ResourceGroup `
    --location $Location `
    --output none

# ── 3. VM with public IP + DNS label ─────────────────────────────────────────
Log "Creating VM: $VmName ($VmSize)"
$VmResult = az vm create `
    --resource-group $ResourceGroup `
    --name $VmName `
    --image Ubuntu2204 `
    --size $VmSize `
    --admin-username $AdminUser `
    --generate-ssh-keys `
    --public-ip-sku Standard `
    --public-ip-address-dns-name $DnsLabel `
    --output json | ConvertFrom-Json

$PublicIp = $VmResult.publicIpAddress
$FQDN     = "$DnsLabel.$Location.cloudapp.azure.com"
Log "VM created. Public IP: $PublicIp  FQDN: $FQDN"

# ── 4. Open port 80 (CVAT UI + API) ──────────────────────────────────────────
Log "Opening port 80..."
az vm open-port `
    --resource-group $ResourceGroup `
    --name $VmName `
    --port 80 `
    --priority 1001 `
    --output none

# ── 5. Copy and run setup.sh on VM ───────────────────────────────────────────
Log "Uploading setup script to VM..."
scp -o StrictHostKeyChecking=no `
    "$PSScriptRoot/setup.sh" `
    "${AdminUser}@${PublicIp}:~/setup.sh"

Log "Running setup.sh on VM (this takes ~10 minutes)..."
ssh -o StrictHostKeyChecking=no "${AdminUser}@${PublicIp}" `
    "chmod +x ~/setup.sh && ~/setup.sh"

# ── 6. Summary ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║              Deployment complete!                        ║" -ForegroundColor Green
Write-Host "╠══════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║  CVAT URL:  http://$FQDN" -ForegroundColor Green
Write-Host "║  Alt URL:   http://$PublicIp" -ForegroundColor Green
Write-Host "║  Username:  admin" -ForegroundColor Green
Write-Host "║  Password:  cvat2024demo" -ForegroundColor Green
Write-Host "║" -ForegroundColor Green
Write-Host "║  SSH:  ssh ${AdminUser}@${PublicIp}" -ForegroundColor Green
Write-Host "║  Logs: ssh then 'docker compose logs -f cvat_server'" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Green
