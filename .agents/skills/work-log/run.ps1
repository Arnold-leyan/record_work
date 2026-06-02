param(
    [Parameter(Mandatory = $true)]
    [string]$Content,

    [string]$Content2 = "",

    # When set, keep the same VPN session open and run the read-only verifier
    # before auto-closing VPN. This avoids opening VPN twice for the normal
    # Hermes workflow: write -> verify.
    [switch]$Verify
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$NodeScript = Join-Path $ScriptDir "work-log.js"
$ReadNodeScript = Join-Path $ScriptDir "read-work-log.js"

function Resolve-RecordWorkRoot([string]$StartDir) {
    function Test-RecordWorkRoot([string]$Path_) {
        if (-not $Path_ -or -not (Test-Path -LiteralPath $Path_)) { return $false }
        $resolved = (Resolve-Path -LiteralPath $Path_).Path
        $hasEnv = (Test-Path -LiteralPath (Join-Path $resolved ".env")) -or
                  (Test-Path -LiteralPath (Join-Path $resolved ".env.example"))
        $hasVpnScript = Test-Path -LiteralPath (Join-Path $resolved "vpn-connect.ps1")
        $hasVpnBat = @(Get-ChildItem -LiteralPath $resolved -Filter "*VPN*.bat" -File -ErrorAction SilentlyContinue).Count -gt 0
        return ($hasEnv -and $hasVpnScript -and $hasVpnBat)
    }

    if ($env:RECORD_WORK_ROOT -and (Test-RecordWorkRoot $env:RECORD_WORK_ROOT)) {
        return (Resolve-Path -LiteralPath $env:RECORD_WORK_ROOT).Path
    }

    $rootFile = Join-Path $StartDir ".record-work-root"
    if (Test-Path -LiteralPath $rootFile) {
        $configuredRoot = (Get-Content -LiteralPath $rootFile -Encoding UTF8 | Select-Object -First 1).Trim()
        if (Test-RecordWorkRoot $configuredRoot) {
            return (Resolve-Path -LiteralPath $configuredRoot).Path
        }
        Write-Error "Invalid project root in $rootFile`: $configuredRoot"
        exit 2
    }

    $dir = (Resolve-Path -LiteralPath $StartDir).Path
    while ($dir) {
        if (Test-RecordWorkRoot $dir) {
            return $dir
        }

        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }

    Write-Error "Cannot locate record_work project root from $StartDir. Set RECORD_WORK_ROOT or create .record-work-root in the skill directory."
    exit 2
}

$RecordWork = Resolve-RecordWorkRoot $ScriptDir
Write-Host "[work-log] Project root: $RecordWork"

# Read credentials and IP from .env
$envFile = Join-Path $RecordWork ".env"
$envVars = @{}
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match "^(\w+)=(.+)$") { $envVars[$Matches[1]] = $Matches[2] }
    }
}

# Skip VPN bat if internal host is already reachable on port 80
$VpnTarget = $envVars["internal_ip"]
if (-not $VpnTarget) {
    Write-Error ".env 缺少 internal_ip 設定"
    exit 2
}

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
# Track whether THIS script started the VPN; only auto-close in that case
# so we don't yank a VPN the user opened for other reasons.
$WeStartedVpn = $false

if ($VpnReachable) {
    Write-Host "[work-log] VPN already connected ($VpnTarget reachable). Skipping VPN bat."
} else {
    $WeStartedVpn = $true
    Write-Host "[work-log] $VpnTarget unreachable, starting VPN..."
    # Locate VPN .bat by wildcard (avoid hard-coding the Chinese filename in this .ps1,
    # because PS 5.1 cannot read non-BOM UTF-8 source files reliably).
    $VpnBat = Get-ChildItem -Path $RecordWork -Filter "*VPN*.bat" -File -ErrorAction SilentlyContinue |
              Select-Object -First 1 -ExpandProperty FullName

    if (-not $VpnBat -or -not (Test-Path -LiteralPath $VpnBat)) {
        Write-Error "VPN .bat not found in $RecordWork (looked for *VPN*.bat)"
        exit 2
    }
    Write-Host "[work-log] Using VPN bat: $VpnBat (fire-and-forget; bat self-elevates)"
    # Fire-and-forget: the bat triggers a UAC self-elevation and then exits.
    # Don't wait — instead poll for the internal host to become reachable.
    Start-Process -FilePath $VpnBat -WorkingDirectory $RecordWork -WindowStyle Hidden | Out-Null

    Write-Host "[work-log] Polling $VpnTarget`:80 for up to 60s..."
    $deadline = (Get-Date).AddSeconds(60)
    $vpnUp = $false
    while ((Get-Date) -lt $deadline) {
        if (Test-TcpPort $VpnTarget 80) {
            Write-Host "[work-log] VPN up ($VpnTarget`:80 reachable)."
            $vpnUp = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $vpnUp) {
        Write-Error "VPN did not come up within 60s ($VpnTarget`:80 still unreachable)"
        exit 3
    }
}

Write-Host "[work-log] Running Playwright script..."
$nodeArgs = @($NodeScript, "--content", $Content)
if ($Content2 -and $Content2.Trim() -ne "") {
    $nodeArgs += @("--content2", $Content2)
}

$nodeExit = 0
try {
    & node @nodeArgs
    $nodeExit = $LASTEXITCODE

    if ($nodeExit -eq 0 -and $Verify) {
        Write-Host "[work-log] Running read-only verification before closing VPN..."
        & node $ReadNodeScript
        $verifyExit = $LASTEXITCODE
        if ($verifyExit -ne 0) {
            Write-Warning "[work-log] Verification failed (exit=$verifyExit)."
            $nodeExit = $verifyExit
        }
    } elseif ($Verify) {
        Write-Warning "[work-log] Skipping verification because write failed (exit=$nodeExit)."
    }
} finally {
    if ($WeStartedVpn) {
        Write-Host "[work-log] Closing VPN (this script started it)..."
        # openconnect runs elevated, so kill via elevated taskkill.
        # -Verb RunAs triggers UAC; -Wait blocks until the kill completes (~1s after approval).
        try {
            Start-Process -FilePath "taskkill.exe" `
                          -ArgumentList "/F /IM openconnect.exe" `
                          -Verb RunAs -Wait -WindowStyle Hidden -ErrorAction Stop
            Start-Sleep -Seconds 1
            $still = Get-Process -Name openconnect -ErrorAction SilentlyContinue
            if ($still) {
                Write-Warning "[work-log] openconnect still running after taskkill"
            } else {
                Write-Host "[work-log] VPN closed."
            }
        } catch {
            Write-Warning "[work-log] Failed to close VPN: $($_.Exception.Message)"
        }
    } else {
        Write-Host "[work-log] Leaving VPN as-is (was already up before this script)."
    }
}

Write-Host "[work-log] Done (exit=$nodeExit)"
exit $nodeExit
