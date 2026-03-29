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
function Good($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }

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
$userName = $account.user.name
$subName  = $account.name
Good "Logged in: $userName ($subName)"

# Step 3: Resource group
Log "Creating resource group $ResourceGroup in $Location..."
az group create --name $ResourceGroup --location $Location --output none
Good "Resource group ready."

# Step 4: Create VM or reuse existing
$existingVm = az vm show --resource-group $ResourceGroup --name $VmName --output json 2>$null
if ($existingVm) {
    Log "VM already exists - reusing it."
    $addrObj  = az vm list-ip-addresses --resource-group $ResourceGroup --name $VmName --output json | ConvertFrom-Json
    $PublicIp = $addrObj[0].virtualMachine.network.publicIpAddresses[0].ipAddress
} else {
    Log "Creating VM $VmName ($VmSize) with password auth - takes ~2 min..."
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
    if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: VM creation failed." -ForegroundColor Red; exit 1 }
    $PublicIp = ($VmJson | ConvertFrom-Json).publicIpAddress
    Good "VM created at $PublicIp"
}

# Step 5: Open port 80
Log "Opening port 80..."
az vm open-port --resource-group $ResourceGroup --name $VmName --port 80 --priority 1001 --output none
Good "Port 80 open."

# Step 6: Run setup.sh on the VM via Azure API (no SSH/scp needed)
$SetupScriptPath = Join-Path $PSScriptRoot "setup.sh"
if (-not (Test-Path $SetupScriptPath)) {
    Write-Host "ERROR: setup.sh not found at $SetupScriptPath" -ForegroundColor Red; exit 1
}
Log "Running setup.sh on VM via Azure run-command (10-15 min)..."
Log "You can also watch progress at: https://portal.azure.com"

$ResultJson = az vm run-command invoke `
    --resource-group $ResourceGroup `
    --name $VmName `
    --command-id RunShellScript `
    --scripts "@$SetupScriptPath" `
    --output json

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: run-command failed. Check Azure Portal for details." -ForegroundColor Red; exit 1
}

$Result = $ResultJson | ConvertFrom-Json
($Result.value | Where-Object { $_.code -like "*StdOut*" } | Select-Object -ExpandProperty message) | Write-Host
$errText = ($Result.value | Where-Object { $_.code -like "*StdErr*" } | Select-Object -ExpandProperty message)
if ($errText) { Write-Host $errText -ForegroundColor Yellow }

# Step 7: Print summary
$FQDN = "$DnsLabel.$Location.cloudapp.azure.com"
Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host "  Deployment complete!" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host "  URL:      http://$PublicIp" -ForegroundColor Green
Write-Host "  FQDN:     http://$FQDN" -ForegroundColor Green
Write-Host "  Username: admin" -ForegroundColor Green
Write-Host "  Password: cvat2024demo" -ForegroundColor Green
Write-Host ""
Write-Host "  SSH (optional):" -ForegroundColor White
Write-Host "    ssh ${AdminUser}@${PublicIp}   (VM password: $AdminPassword)" -ForegroundColor White
Write-Host ""
Write-Host "  To delete all resources when done:" -ForegroundColor Yellow
Write-Host "    az group delete --name $ResourceGroup --yes --no-wait" -ForegroundColor Yellow
Write-Host "====================================================" -ForegroundColor Green