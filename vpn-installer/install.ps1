# VPN 安裝腳本
# 執行方式：在此資料夾內，右鍵 install.ps1 → 以系統管理員身分執行

$ErrorActionPreference = "Stop"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "需要管理員權限，正在重新啟動..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Wait
    exit
}

$installDir = "C:\VPN"
$scriptDir  = Split-Path -Parent $PSCommandPath

Write-Host "正在安裝 VPN 工具到 $installDir ..." -ForegroundColor Cyan

# 建立安裝目錄
New-Item -ItemType Directory -Force -Path $installDir | Out-Null

# 複製所有執行檔與 DLL
Copy-Item "$scriptDir\bin\*" $installDir -Force
Write-Host "  ✓ 複製執行檔完成"

# 建立連線腳本
$connectScript = @'
# VPN 連線腳本 - 右鍵「以系統管理員身分執行」
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Wait
    exit
}

$installDir = "C:\VPN"
$env:PATH   = "$installDir;" + $env:PATH

$user    = "你的員編"
$pass    = "你的密碼"
$gateway = "你的VPN網址"
$cert    = "你的VPN憑證"
$script  = "$installDir\vpnc-script.js"

Write-Host "正在連線到 $gateway ..." -ForegroundColor Cyan
Write-Host "關閉此視窗即可斷線。" -ForegroundColor Gray

$pinfo = New-Object System.Diagnostics.ProcessStartInfo
$pinfo.FileName  = "$installDir\openconnect.exe"
$pinfo.Arguments = "--protocol=fortinet --user=$user --passwd-on-stdin --no-dtls --servercert `"$cert`" --script `"$script`" $gateway"
$pinfo.RedirectStandardInput = $true
$pinfo.UseShellExecute = $false
$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $pinfo
$proc.Start() | Out-Null
$proc.StandardInput.WriteLine($pass)
$proc.StandardInput.Close()
$proc.WaitForExit()
'@
$connectScript | Set-Content "$installDir\vpn-connect.ps1" -Encoding utf8
Write-Host "  ✓ 建立連線腳本完成"

# 建立桌面捷徑
$desktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut("$desktop\連線 VPN.lnk")
$shortcut.TargetPath     = "powershell.exe"
$shortcut.Arguments      = "-NoProfile -ExecutionPolicy Bypass -File `"$installDir\vpn-connect.ps1`""
$shortcut.WorkingDirectory = $installDir
$shortcut.Description    = "連線公司 VPN"
$shortcut.Save()
Write-Host "  ✓ 建立桌面捷徑完成"

Write-Host ""
Write-Host "安裝完成！" -ForegroundColor Green
Write-Host "之後只要雙擊桌面上的「連線 VPN」即可使用。" -ForegroundColor Green
Write-Host ""
pause
