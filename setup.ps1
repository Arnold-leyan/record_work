param(
    [switch]$SkipBrowserInstall,
    [string]$SkillDir,
    [switch]$SyncExternalSkills
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Root = Split-Path -Parent $PSCommandPath
$RepoSkillDir = Join-Path $Root ".agents\skills\work-log"
$EnvPath = Join-Path $Root ".env"
$EnvExamplePath = Join-Path $Root ".env.example"

function Fail([string]$Message) {
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit 1
}

Write-Host "== work-log setup =="
Write-Host "Project root: $Root"

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Fail "Node.js is not installed. Install the LTS version from https://nodejs.org/ and run setup again."
}
if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
    Fail "npm.cmd is not available. Reinstall Node.js LTS and run setup again."
}
if (-not (Test-Path -LiteralPath $RepoSkillDir)) {
    Fail "Repo skill directory not found: $RepoSkillDir"
}

$vpnBat = Get-ChildItem -LiteralPath $Root -Filter "*VPN*.bat" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $vpnBat) {
    Fail "VPN launcher not found in project root. Expected a file matching *VPN*.bat next to setup.ps1."
}
if (-not (Test-Path -LiteralPath (Join-Path $Root "vpn-connect.ps1"))) {
    Fail "vpn-connect.ps1 not found in project root."
}
if (-not (Test-Path -LiteralPath (Join-Path $Root "vpn-installer\bin\openconnect.exe"))) {
    Fail "openconnect.exe not found under vpn-installer\bin. Check that the vpn-installer folder is complete."
}

if (-not (Test-Path -LiteralPath $EnvPath)) {
    if (-not (Test-Path -LiteralPath $EnvExamplePath)) {
        Fail ".env.example not found; cannot create .env."
    }
    Copy-Item -LiteralPath $EnvExamplePath -Destination $EnvPath
    Write-Host "Created .env from .env.example."
}

$envVars = @{}
Get-Content -LiteralPath $EnvPath -Encoding UTF8 | ForEach-Object {
    if ($_ -match "^(\w+)=(.*)$") { $envVars[$Matches[1]] = $Matches[2].Trim() }
}

$required = @("account", "password", "VPN_account", "VPN_password", "VPN_gateway", "VPN_cert", "internal_ip", "department")
$missing = @()
foreach ($key in $required) {
    if (-not $envVars.ContainsKey($key) -or
        [string]::IsNullOrWhiteSpace($envVars[$key]) -or
        $envVars[$key] -match "^你的|^vpn\.your-company|^pin-sha256:your-cert|^192\.168\.x\.x$") {
        $missing += $key
    }
}

if ($missing.Count -gt 0) {
    Write-Host "Please fill these keys in .env: $($missing -join ', ')" -ForegroundColor Yellow
    Start-Process notepad.exe -ArgumentList "`"$EnvPath`""
    Write-Host "After saving .env, run setup again."
    exit 2
}

Write-Host "Installing npm dependencies..."
function Sync-SkillDir([string]$TargetDir) {
    $resolvedRepo = (Resolve-Path -LiteralPath $RepoSkillDir).Path
    if ((Test-Path -LiteralPath $TargetDir) -and ((Resolve-Path -LiteralPath $TargetDir).Path -eq $resolvedRepo)) {
        return
    }

    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    $items = @("SKILL.md", "package.json", "package-lock.json", "run.ps1", "work-log.js")
    foreach ($item in $items) {
        Copy-Item -LiteralPath (Join-Path $RepoSkillDir $item) -Destination (Join-Path $TargetDir $item) -Force
    }
    Set-Content -LiteralPath (Join-Path $TargetDir ".record-work-root") -Value $Root -Encoding UTF8
    Write-Host "Synced external skill: $TargetDir"
}

function Install-SkillDependencies([string]$TargetDir) {
    Write-Host "Installing npm dependencies in $TargetDir..."
    Push-Location $TargetDir
    try {
        & npm.cmd install --quiet
        if ($LASTEXITCODE -ne 0) { Fail "npm install failed in $TargetDir." }

        if (-not $SkipBrowserInstall) {
            Write-Host "Installing Playwright Chromium..."
            & npx.cmd playwright install chromium
            if ($LASTEXITCODE -ne 0) { Fail "Playwright Chromium install failed." }
        }
    } finally {
        Pop-Location
    }
}

$skillDirs = New-Object System.Collections.Generic.List[string]
$skillDirs.Add($RepoSkillDir)

if ($SkillDir) {
    Sync-SkillDir $SkillDir
    $skillDirs.Add($SkillDir)
}

if ($SyncExternalSkills) {
    $externalCandidates = @(
        (Join-Path $env:USERPROFILE ".codex\skills\work-log"),
        (Join-Path $env:USERPROFILE ".claude\skills\work-log")
    )
    foreach ($candidate in $externalCandidates) {
        if (Test-Path -LiteralPath (Split-Path -Parent $candidate)) {
            Sync-SkillDir $candidate
            $skillDirs.Add($candidate)
        }
    }
}

$uniqueSkillDirs = $skillDirs | Select-Object -Unique
foreach ($dir in $uniqueSkillDirs) {
    Install-SkillDependencies $dir
}

Write-Host "Setup complete."
Write-Host "VPN launcher: $($vpnBat.FullName)"
Write-Host "Run test: powershell.exe -ExecutionPolicy Bypass -File `"$RepoSkillDir\run.ps1`" -Content `"setup-test`""
