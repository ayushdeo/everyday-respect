#!/usr/bin/env pwsh
# =============================================================================
# Provision Azure VM and deploy CVAT with Audio Feature
# Windows-compatible: no scp, no ssh, no embedded bash in PowerShell
# All setup logic lives in setup.sh and is sent via az vm run-command
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

# ── 1. Check az CLI ───────────────────────────────────────────────────────────
Log "Checking Azure CLI..."
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: 'az' not on PATH. Open a NEW terminal after installing Azure CLI and retry." -ForegroundColor Red
    exit 1
}
Good "Azure CLI found."

# ── 2. Check login ────────────────────────────────────────────────────────────
Log "Checking Azure login..."
$accountJson = az account show --output json 2>$null
if ($LASTEXITCODE -ne 0 -or -not $accountJson) {
    Log "Not logged in — launching browser login..."
    az login
    $accountJson = az account show --output json
}
$account = $accountJson | ConvertFrom-Json
Good "Logged in: $($account.user.name) | $($account.name)"

# ── 3. Resource group ─────────────────────────────────────────────────────────
Log "Creating resource group '$ResourceGroup' in $Location..."
az group create --name $ResourceGroup --location $Location --output none
Good "Resource group ready."

# ── 4. Create VM (password auth avoids Windows SSH-key-gen bug) ───────────────
$existingVm = az vm show --resource-group $ResourceGroup --name $VmName --output json 2>$null
if ($existingVm) {
    Log "VM already exists — skipping creation."
    $PublicIp = (az vm list-ip-addresses `
        --resource-group $ResourceGroup `
        --name $VmName `
        --output json | ConvertFrom-Json)[0].virtualMachine.network.publicIpAddresses[0].ipAddress
} else {
    Log "Creating VM '$VmName' ($VmSize) — takes ~2 minutes..."
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
        Write-Host "ERROR: VM creation failed. See az output above." -ForegroundColor Red
        exit 1
    }
    $PublicIp = ($VmJson | ConvertFrom-Json).publicIpAddress
    Good "VM created. IP: $PublicIp"
}

$FQDN = "$DnsLabel.$Location.cloudapp.azure.com"

# ── 5. Open port 80 ───────────────────────────────────────────────────────────
Log "Opening port 80..."
az vm open-port `
    --resource-group $ResourceGroup `
    --name $VmName `
    --port 80 `
    --priority 1001 `
    --output none
Good "Port 80 open."

# ── 6. Send setup.sh to the VM via Azure run-command (no scp/ssh needed) ──────
# az vm run-command reads the script file from disk using the "@filepath" prefix.
# This sends the file through the Azure API — no OpenSSH client required.
$SetupScriptPath = Join-Path $PSScriptRoot "setup.sh"

if (-not (Test-Path $SetupScriptPath)) {
    Write-Host "ERROR: setup.sh not found at $SetupScriptPath" -ForegroundColor Red
    exit 1
}

Log "Uploading and running setup.sh on VM via Azure API..."
Log "This takes 10-15 minutes. Watch progress at:"
Log "  https://portal.azure.com -> $VmName -> Run command"

$ResultJson = az vm run-command invoke `
    --resource-group $ResourceGroup `
    --name $VmName `
    --command-id RunShellScript `
    --scripts "@$SetupScriptPath" `
    --output json

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: run-command failed. Check the VM in Azure Portal." -ForegroundColor Red
    exit 1
}

$Result = $ResultJson | ConvertFrom-Json
$StdOut = ($Result.value | Where-Object { $_.code -like "*StdOut*" }).message
$StdErr = ($Result.value | Where-Object { $_.code -like "*StdErr*" }).message

Write-Host ""
Write-Host "--- VM Output ---" -ForegroundColor Gray
Write-Host $StdOut

if ($StdErr -and $StdErr.Trim() -ne "") {
    Write-Host ""
    Write-Host "--- VM Stderr (warnings are usually OK) ---" -ForegroundColor Yellow
    Write-Host $StdErr
}

# ── 7. Summary ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host "  Deployment complete!" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host "  URL:       http://$PublicIp" -ForegroundColor Green
Write-Host "  FQDN:      http://$FQDN" -ForegroundColor Green
Write-Host "  Username:  admin" -ForegroundColor Green
Write-Host "  Password:  cvat2024demo" -ForegroundColor Green
Write-Host ""
Write-Host "  SSH (optional, uses password):" -ForegroundColor White
Write-Host "    ssh ${AdminUser}@${PublicIp}" -ForegroundColor White
Write-Host "    VM password: $AdminPassword" -ForegroundColor White
Write-Host ""
Write-Host "  To delete all Azure resources when done:" -ForegroundColor Yellow
Write-Host "    az group delete --name $ResourceGroup --yes --no-wait" -ForegroundColor Yellow
Write-Host "====================================================" -ForegroundColor Green
