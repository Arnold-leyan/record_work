# VPN Connect - FortiGate SSL-VPN via openconnect
# Must be run as Administrator (will self-elevate)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Wait
    exit
}

# Set base directory to the script's location
$baseDir = Split-Path -Parent $PSCommandPath
$binDir  = Join-Path $baseDir "vpn-installer\bin"

# Pre-check: See if internal network route is already present
# 檢查路由表中是否已有 192.168.40.61 的路由 (VPN 連線後會自動新增)
$routeExists = Get-NetRoute -DestinationPrefix "192.168.40.61/32" -ErrorAction SilentlyContinue
if ($null -ne $routeExists) {
    exit
}

# Read credentials from .env
$envFile = Join-Path $baseDir ".env"
$envVars = @{}
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match "^(\w+)=(.+)$") { $envVars[$Matches[1]] = $Matches[2] }
    }
}

$user    = $envVars["VPN_account"]
$pass    = $envVars["VPN_password"]
$gateway = $envVars["VPN_gateway"]
$cert    = $envVars["VPN_cert"]

if (-not $gateway) { Write-Error "Missing VPN_gateway in .env"; exit 1 }
if (-not $cert) { Write-Error "Missing VPN_cert in .env"; exit 1 }

# Use tools from the local vpn-installer directory
$oc      = Join-Path $binDir "openconnect.exe"
$script  = Join-Path $binDir "vpnc-script.js"

# Ensure the bin directory is in PATH so DLLs can be found
$env:PATH = "$binDir;" + $env:PATH

if (-not (Test-Path $oc)) {
    Write-Host "Error: openconnect.exe not found at $oc" -ForegroundColor Red
    pause
    exit
}

Write-Host "Connecting to $gateway as $user ..." -ForegroundColor Cyan
Write-Host "Press Ctrl+C to disconnect." -ForegroundColor Gray

$pinfo = New-Object System.Diagnostics.ProcessStartInfo
$pinfo.FileName = $oc
$pinfo.Arguments = "--protocol=fortinet --user=$user --passwd-on-stdin --no-dtls --servercert `"$cert`" --script `"$script`" $gateway"
$pinfo.RedirectStandardInput = $true
$pinfo.UseShellExecute = $false
$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $pinfo
$proc.Start() | Out-Null
$proc.StandardInput.WriteLine($pass)
$proc.StandardInput.Close()
$proc.WaitForExit()
