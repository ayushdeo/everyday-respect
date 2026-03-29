param(
    [string]$ResourceGroup = "cvat-demo-rg",
    [string]$VmName        = "cvat-demo-vm",
    [string]$AdminUser     = "azureuser",
    [string]$AdminPassword = "CvatDemo2024!",
    [string]$VmSize        = "",
    [string]$Location      = ""
)

function Log($msg)  { Write-Host "[PROVISION] $msg" -ForegroundColor Cyan }
function Good($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red }

# Allowed regions for Azure for Students subscription (verified from policy)
$AllowedRegions = @("eastus2", "southcentralus", "canadacentral", "centralus", "westus2")

# VM sizes to try in order (2+ vCPU, 4+ GB recommended for Docker image builds)
$SizesToTry = @("Standard_D2s_v5", "Standard_B2ms", "Standard_DS2_v2", "Standard_B2s", "Standard_B1ms")

# If user specified overrides, put those first
if ($Location -ne "") { $AllowedRegions = @($Location) + ($AllowedRegions | Where-Object { $_ -ne $Location }) }
if ($VmSize  -ne "") { $SizesToTry    = @($VmSize)    + ($SizesToTry    | Where-Object { $_ -ne $VmSize    }) }

Write-Host ""
Write-Host "Will try regions: $($AllowedRegions -join ', ')" -ForegroundColor Gray
Write-Host "Will try sizes:   $($SizesToTry -join ', ')" -ForegroundColor Gray
Write-Host ""

# Step 1: Check az CLI
Log "Checking Azure CLI..."
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: az not on PATH. Open a NEW terminal and retry." -ForegroundColor Red
    exit 1
}
Good "Azure CLI found."

# Step 2: Check login
Log "Checking Azure login..."
$accountJson = az account show --output json 2>$null
if ($LASTEXITCODE -ne 0 -or -not $accountJson) {
    Log "Not logged in - launching browser login..."
    az login
    $accountJson = az account show --output json
}
$account = $accountJson | ConvertFrom-Json
Good "Logged in: $($account.user.name) ($($account.name))"

# Step 3: Clean up any prior failed attempt
$rgExists = az group show --name $ResourceGroup --output json 2>$null
if ($rgExists) {
    Log "Removing old resource group $ResourceGroup..."
    az group delete --name $ResourceGroup --yes 2>$null | Out-Null
    Good "Old resource group removed."
}

# Step 4: Try region + size combos until one succeeds
$PublicIp  = $null
$ChosenLoc = $null
$ChosenSku = $null
$DnsLabel  = "cvatdemo" + ([System.Guid]::NewGuid().ToString("N").Substring(0,6))

:outer foreach ($loc in $AllowedRegions) {
    foreach ($sku in $SizesToTry) {
        Log "Trying: $loc / $sku ..."

        # Create resource group in this region
        az group create --name $ResourceGroup --location $loc --output none 2>$null | Out-Null

        # Attempt VM creation - capture all output, do NOT stop on error
        $vmOut = az vm create `
            --resource-group $ResourceGroup `
            --name $VmName `
            --image Ubuntu2204 `
            --size $sku `
            --admin-username $AdminUser `
            --admin-password $AdminPassword `
            --authentication-type password `
            --public-ip-sku Standard `
            --public-ip-address-dns-name $DnsLabel `
            --location $loc `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            $vmObj = ($vmOut | Where-Object { $_ -notlike "WARNING:*" -and $_ -notlike "ERROR:*" }) -join "" | ConvertFrom-Json
            $PublicIp  = $vmObj.publicIpAddress
            $ChosenLoc = $loc
            $ChosenSku = $sku
            Good "VM created! Location: $loc  Size: $sku  IP: $PublicIp"
            break outer
        } else {
            $errLine = $vmOut | Where-Object { $_ -like "*SkuNotAvailable*" -or $_ -like "*RequestDisallowedByAzure*" -or $_ -like "*Capacity*" } | Select-Object -First 1
            if ($errLine) {
                Warn "  $loc/$sku unavailable - trying next..."
            } else {
                Fail "  $loc/$sku failed with unexpected error:"
                $vmOut | Where-Object { $_ -like "Exception*" -or $_ -like "Code:*" -or $_ -like "Message:*" } | Select-Object -First 3 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
                Warn "  Trying next combination..."
            }
            # Clean up the resource group before next region attempt
            az group delete --name $ResourceGroup --yes --no-wait 2>$null | Out-Null
            Start-Sleep -Seconds 5
        }
    }
}

if (-not $PublicIp) {
    Write-Host ""
    Write-Host "FATAL: Could not create a VM in any region/size combination." -ForegroundColor Red
    Write-Host "Tried regions: $($AllowedRegions -join ', ')" -ForegroundColor Red
    Write-Host "Tried sizes:   $($SizesToTry -join ', ')" -ForegroundColor Red
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  1. Wait a few minutes and retry (Azure capacity fluctuates)" -ForegroundColor Yellow
    Write-Host "  2. Try: .\provision.ps1 -Location southcentralus -VmSize Standard_D2s_v5" -ForegroundColor Yellow
    exit 1
}

$FQDN = "$DnsLabel.$ChosenLoc.cloudapp.azure.com"

# Step 5: Open port 80
Log "Opening port 80..."
az vm open-port --resource-group $ResourceGroup --name $VmName --port 80 --priority 1001 --output none
Good "Port 80 open."

# Step 6: Run setup.sh via Azure run-command
$SetupScriptPath = Join-Path $PSScriptRoot "setup.sh"
if (-not (Test-Path $SetupScriptPath)) {
    Write-Host "ERROR: setup.sh not found at $SetupScriptPath" -ForegroundColor Red
    exit 1
}

Log "Running setup.sh on VM via Azure API (10-15 min)..."
Log "Monitor at portal.azure.com -> $VmName -> Run command"

$ResultJson = az vm run-command invoke `
    --resource-group $ResourceGroup `
    --name $VmName `
    --command-id RunShellScript `
    --scripts "@$SetupScriptPath" `
    --output json

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: run-command failed. SSH in and check: ssh ${AdminUser}@${PublicIp}" -ForegroundColor Red
    exit 1
}

$Result = $ResultJson | ConvertFrom-Json
$StdOut = ($Result.value | Where-Object { $_.code -like "*StdOut*" } | Select-Object -ExpandProperty message)
$StdErr = ($Result.value | Where-Object { $_.code -like "*StdErr*" } | Select-Object -ExpandProperty message)

Write-Host ""
Write-Host "--- VM Output ---" -ForegroundColor Gray
Write-Host $StdOut
if ($StdErr -and $StdErr.Trim()) {
    Write-Host "--- VM Stderr ---" -ForegroundColor Yellow
    Write-Host $StdErr
}

# Step 7: Summary
Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host "  CVAT deployed successfully!" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host "  Region:   $ChosenLoc" -ForegroundColor Green
Write-Host "  VM Size:  $ChosenSku" -ForegroundColor Green
Write-Host "  URL:      http://$PublicIp" -ForegroundColor Green
Write-Host "  FQDN:     http://$FQDN" -ForegroundColor Green
Write-Host "  Username: admin" -ForegroundColor Green
Write-Host "  Password: cvat2024demo" -ForegroundColor Green
Write-Host ""
Write-Host "  SSH: ssh ${AdminUser}@${PublicIp}   password: $AdminPassword" -ForegroundColor White
Write-Host ""
Write-Host "  Delete all resources when done:" -ForegroundColor Yellow
Write-Host "    az group delete --name $ResourceGroup --yes --no-wait" -ForegroundColor Yellow
Write-Host "====================================================" -ForegroundColor Green