param(
    [string]$ResourceGroup = "cvat-demo-rg",
    [string]$Location      = "westus2",
    [string]$VmName        = "cvat-demo-vm",
    [string]$VmSize        = "Standard_B2s",
    [string]$AdminUser     = "azureuser",
    [string]$AdminPassword = "CvatDemo2024!",
    [string]$DnsLabel      = ("cvatdemo" + ([System.Guid]::NewGuid().ToString("N").Substring(0,6)))
)

function Log($msg)  { Write-Host "[PROVISION] $msg" -ForegroundColor Cyan }
function Good($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Fail($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }

# Allowed regions for Azure for Students: centralus, eastus2, westus2, canadacentral, southcentralus
Write-Host ""
Write-Host "Using location: $Location" -ForegroundColor Cyan
Write-Host "Allowed student regions: centralus, eastus2, westus2, canadacentral, southcentralus" -ForegroundColor Gray
Write-Host ""

# Step 1: Check az CLI
Log "Checking Azure CLI..."
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Fail "az not on PATH. Open a NEW terminal and retry."
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
$account  = $accountJson | ConvertFrom-Json
$userName = $account.user.name
$subName  = $account.name
Good "Logged in: $userName ($subName)"

# Step 3: Delete old failed resource group if it exists (clean slate)
$rgExists = az group show --name $ResourceGroup --output json 2>$null
if ($rgExists) {
    Log "Deleting old resource group $ResourceGroup (clean slate before retry)..."
    az group delete --name $ResourceGroup --yes 2>$null
    Good "Old resource group deleted."
}

# Step 4: Create resource group in allowed region
Log "Creating resource group $ResourceGroup in $Location..."
az group create --name $ResourceGroup --location $Location --output none
if ($LASTEXITCODE -ne 0) { Fail "Could not create resource group in $Location." }
Good "Resource group ready."

# Step 5: Create VM
Log "Creating VM $VmName ($VmSize) in $Location - takes ~2 minutes..."
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
    --location $Location `
    --output json

if ($LASTEXITCODE -ne 0) { Fail "VM creation failed. Try a different -Location value from: centralus, eastus2, westus2, canadacentral, southcentralus" }
$PublicIp = ($VmJson | ConvertFrom-Json).publicIpAddress
Good "VM created at $PublicIp"

$FQDN = "$DnsLabel.$Location.cloudapp.azure.com"

# Step 6: Open port 80
Log "Opening port 80..."
az vm open-port --resource-group $ResourceGroup --name $VmName --port 80 --priority 1001 --output none
Good "Port 80 open."

# Step 7: Run setup.sh on VM via Azure run-command (no scp/ssh needed)
$SetupScriptPath = Join-Path $PSScriptRoot "setup.sh"
if (-not (Test-Path $SetupScriptPath)) {
    Fail "setup.sh not found at: $SetupScriptPath"
}
Log "Sending setup.sh to VM via Azure API - runs 10-15 minutes..."
Log "Monitor at: https://portal.azure.com (search for your VM, then Run command)"

$ResultJson = az vm run-command invoke `
    --resource-group $ResourceGroup `
    --name $VmName `
    --command-id RunShellScript `
    --scripts "@$SetupScriptPath" `
    --output json

if ($LASTEXITCODE -ne 0) { Fail "run-command failed. Check Azure Portal." }

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

# Step 8: Summary
Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host "  Deployment complete!" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host "  URL:      http://$PublicIp" -ForegroundColor Green
Write-Host "  FQDN:     http://$FQDN" -ForegroundColor Green
Write-Host "  Username: admin" -ForegroundColor Green
Write-Host "  Password: cvat2024demo" -ForegroundColor Green
Write-Host ""
Write-Host "  SSH: ssh ${AdminUser}@${PublicIp}   (password: $AdminPassword)" -ForegroundColor White
Write-Host ""
Write-Host "  Delete everything when done:" -ForegroundColor Yellow
Write-Host "    az group delete --name $ResourceGroup --yes --no-wait" -ForegroundColor Yellow
Write-Host "====================================================" -ForegroundColor Green