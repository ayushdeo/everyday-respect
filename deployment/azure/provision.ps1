param(
    [string]$ResourceGroup = "cvat-demo-rg",
    [string]$Location      = "eastus",
    [string]$VmName        = "cvat-demo-vm",
    [string]$VmSize        = "Standard_B2s",
    [string]$AdminUser     = "azureuser",
    [string]$AdminPassword = "CvatDemo2024!",
    [string]$DnsLabel      = ("cvatdemo" + ([System.Guid]::NewGuid().ToString("N").Substring(0,6)))
)

function Log($msg)  { Write-Host "[PROVISION] $msg" -ForegroundColor Cyan }
function Good($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Fail($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }

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

# Step 3: Resource group
Log "Creating resource group $ResourceGroup in $Location..."
az group create --name $ResourceGroup --location $Location --output none
if ($LASTEXITCODE -ne 0) { Fail "Could not create resource group." }
Good "Resource group ready."

# Step 4: Create VM or reuse existing
# Use --query to silently check - avoids stderr noise on missing VM
$existingIp = az vm list-ip-addresses --resource-group $ResourceGroup --name $VmName --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" --output tsv 2>$null

if ($existingIp -and $existingIp.Trim() -ne "") {
    $PublicIp = $existingIp.Trim()
    Log "VM already exists at $PublicIp - skipping creation."
} else {
    Log "Creating VM $VmName ($VmSize) - takes ~2 minutes..."
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
    if ($LASTEXITCODE -ne 0) { Fail "VM creation failed. See output above." }
    $PublicIp = ($VmJson | ConvertFrom-Json).publicIpAddress
    Good "VM created at $PublicIp"
}

$FQDN = "$DnsLabel.$Location.cloudapp.azure.com"

# Step 5: Open port 80
Log "Opening port 80..."
az vm open-port --resource-group $ResourceGroup --name $VmName --port 80 --priority 1001 --output none
Good "Port 80 open."

# Step 6: Run setup.sh via Azure run-command (no scp/ssh needed)
$SetupScriptPath = Join-Path $PSScriptRoot "setup.sh"
if (-not (Test-Path $SetupScriptPath)) {
    Fail "setup.sh not found at: $SetupScriptPath"
}
Log "Sending setup.sh to VM and running it via Azure API (~10-15 min)..."
Log "Track live in Azure Portal: https://portal.azure.com"

$ResultJson = az vm run-command invoke `
    --resource-group $ResourceGroup `
    --name $VmName `
    --command-id RunShellScript `
    --scripts "@$SetupScriptPath" `
    --output json

if ($LASTEXITCODE -ne 0) { Fail "run-command failed. Check Azure Portal for details." }

$Result  = $ResultJson | ConvertFrom-Json
$StdOut  = ($Result.value | Where-Object { $_.code -like "*StdOut*" } | Select-Object -ExpandProperty message)
$StdErr  = ($Result.value | Where-Object { $_.code -like "*StdErr*" } | Select-Object -ExpandProperty message)

Write-Host ""
Write-Host "--- VM Output ---" -ForegroundColor Gray
Write-Host $StdOut
if ($StdErr -and $StdErr.Trim()) {
    Write-Host "--- VM Stderr (warnings OK) ---" -ForegroundColor Yellow
    Write-Host $StdErr
}

# Step 7: Summary
Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host "  Deployment complete!" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host "  URL:      http://$PublicIp" -ForegroundColor Green
Write-Host "  FQDN:     http://$FQDN" -ForegroundColor Green
Write-Host "  Username: admin" -ForegroundColor Green
Write-Host "  Password: cvat2024demo" -ForegroundColor Green
Write-Host ""
Write-Host "  SSH (optional, password auth):" -ForegroundColor White
Write-Host "    ssh ${AdminUser}@${PublicIp}   password: $AdminPassword" -ForegroundColor White
Write-Host ""
Write-Host "  Delete all Azure resources when done:" -ForegroundColor Yellow
Write-Host "    az group delete --name $ResourceGroup --yes --no-wait" -ForegroundColor Yellow
Write-Host "====================================================" -ForegroundColor Green