param()

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$NodeScript = Join-Path $ScriptDir "read-work-log.js"

function Resolve-RecordWorkRoot([string]$StartDir) {
    function Test-RecordWorkRoot([string]$Path_) {
        if (-not $Path_ -or -not (Test-Path -LiteralPath $Path_)) { return $false }
        $resolved = (Resolve-Path -LiteralPath $Path_).Path
        $hasEnv = (Test-Path -LiteralPath (Join-Path $resolved ".env")) -or (Test-Path -LiteralPath (Join-Path $resolved ".env.example"))
        $hasVpnScript = Test-Path -LiteralPath (Join-Path $resolved "vpn-connect.ps1")
        $hasVpnBat = @(Get-ChildItem -LiteralPath $resolved -Filter "*VPN*.bat" -File -ErrorAction SilentlyContinue).Count -gt 0
        return ($hasEnv -and $hasVpnScript -and $hasVpnBat)
    }
    if ($env:RECORD_WORK_ROOT -and (Test-RecordWorkRoot $env:RECORD_WORK_ROOT)) { return (Resolve-Path -LiteralPath $env:RECORD_WORK_ROOT).Path }
    $rootFile = Join-Path $StartDir ".record-work-root"
    if (Test-Path -LiteralPath $rootFile) {
        $configuredRoot = (Get-Content -LiteralPath $rootFile -Encoding UTF8 | Select-Object -First 1).Trim()
        if (Test-RecordWorkRoot $configuredRoot) { return (Resolve-Path -LiteralPath $configuredRoot).Path }
        Write-Error "Invalid project root in $rootFile`: $configuredRoot"
        exit 2
    }
    $dir = (Resolve-Path -LiteralPath $StartDir).Path
    while ($dir) {
        if (Test-RecordWorkRoot $dir) { return $dir }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    Write-Error "Cannot locate record_work project root from $StartDir."
    exit 2
}

$RecordWork = Resolve-RecordWorkRoot $ScriptDir
Write-Host "[work-log-read] Project root: $RecordWork"

$envFile = Join-Path $RecordWork ".env"
$envVars = @{}
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match "^(\w+)=(.+)$") { $envVars[$Matches[1]] = $Matches[2] }
    }
}
$VpnTarget = $envVars["internal_ip"]
if (-not $VpnTarget) { Write-Error ".env 缺少 internal_ip 設定"; exit 2 }

function Test-TcpPort([string]$Host_, [int]$Port, [int]$TimeoutMs = 1500) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($Host_, $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            try { $client.EndConnect($iar); return $true } catch { return $false }
        }
        return $false
    } finally { $client.Close() }
}

$VpnReachable = Test-TcpPort $VpnTarget 80
$WeStartedVpn = $false
if ($VpnReachable) {
    Write-Host "[work-log-read] VPN already connected ($VpnTarget reachable)."
} else {
    $WeStartedVpn = $true
    Write-Host "[work-log-read] $VpnTarget unreachable, starting VPN..."
    $VpnBat = Get-ChildItem -Path $RecordWork -Filter "*VPN*.bat" -File -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if (-not $VpnBat -or -not (Test-Path -LiteralPath $VpnBat)) { Write-Error "VPN .bat not found in $RecordWork"; exit 2 }
    Start-Process -FilePath $VpnBat -WorkingDirectory $RecordWork -WindowStyle Hidden | Out-Null
    Write-Host "[work-log-read] Polling $VpnTarget`:80 for up to 60s..."
    $deadline = (Get-Date).AddSeconds(60)
    $vpnUp = $false
    while ((Get-Date) -lt $deadline) {
        if (Test-TcpPort $VpnTarget 80) { Write-Host "[work-log-read] VPN up ($VpnTarget`:80 reachable)."; $vpnUp = $true; break }
        Start-Sleep -Seconds 2
    }
    if (-not $vpnUp) { Write-Error "VPN did not come up within 60s ($VpnTarget`:80 still unreachable)"; exit 3 }
}

$nodeExit = 0
try {
    & node $NodeScript
    $nodeExit = $LASTEXITCODE
} finally {
    if ($WeStartedVpn) {
        Write-Host "[work-log-read] Closing VPN (this script started it)..."
        try {
            Start-Process -FilePath "taskkill.exe" -ArgumentList "/F /IM openconnect.exe" -Verb RunAs -Wait -WindowStyle Hidden -ErrorAction Stop
            Start-Sleep -Seconds 1
            $still = Get-Process -Name openconnect -ErrorAction SilentlyContinue
            if ($still) { Write-Warning "[work-log-read] openconnect still running after taskkill" } else { Write-Host "[work-log-read] VPN closed." }
        } catch { Write-Warning "[work-log-read] Failed to close VPN: $($_.Exception.Message)" }
    } else {
        Write-Host "[work-log-read] Leaving VPN as-is (was already up before this script)."
    }
}
Write-Host "[work-log-read] Done (exit=$nodeExit)"
exit $nodeExit
