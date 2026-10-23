# ==============================================================================
# Tools/Diagnose.ps1
# LAN Dynamic Wallpaper - Comprehensive System Diagnostic Suite
# ==============================================================================

[CmdletBinding()]
param()

Set-StrictMode -Version Latest

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " LAN DYNAMIC WALLPAPER - SYSTEM DIAGNOSTIC REPORT" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan

# 1. Environment Info
$psVer = $PSVersionTable.PSVersion
$os = Get-CimInstance Win32_OperatingSystem
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host "[1] Operating System & Environment" -ForegroundColor White
Write-Host "  OS Caption         : $($os.Caption)" -ForegroundColor Gray
Write-Host "  OS Version         : $($os.Version)" -ForegroundColor Gray
Write-Host "  PowerShell Version : $psVer" -ForegroundColor Gray
Write-Host "  Current User       : $currentUser" -ForegroundColor Gray
Write-Host "  Process Elevated   : $(if ($isAdmin) { 'YES (Administrator)' } else { 'NO (Standard User)' })" -ForegroundColor Gray
Write-Host ""

# 2. Network Interfaces
Write-Host "[2] Network Adapters & IPv4 Configuration" -ForegroundColor White
$adapters = Get-NetIPAddress -AddressFamily IPv4 -InterfaceOperationalStatus Up -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike "127.*" }

foreach ($ad in $adapters) {
    $alias = (Get-NetAdapter -InterfaceIndex $ad.InterfaceIndex -ErrorAction SilentlyContinue).InterfaceAlias
    Write-Host "  Adapter: $alias ($($ad.InterfaceAlias))" -ForegroundColor Yellow
    Write-Host "    IPv4 Address    : $($ad.IPAddress)/$($ad.PrefixLength)" -ForegroundColor Gray
    Write-Host "    Interface Index : $($ad.InterfaceIndex)" -ForegroundColor Gray
}
Write-Host ""

# 3. Windows Firewall Rules
Write-Host "[3] Windows Defender Firewall Status" -ForegroundColor White
$rules = Get-NetFirewallRule -DisplayName "LAN-Dynamic-Wallpaper-*" -ErrorAction SilentlyContinue
if ($rules) {
    foreach ($r in $rules) {
        Write-Host "  Firewall Rule : $($r.DisplayName) | Enabled: $($r.Enabled) | Action: $($r.Action)" -ForegroundColor Green
    }
} else {
    Write-Host "  No application firewall rules found. Run Start-Host.bat as Administrator on Host PC to configure automatically." -ForegroundColor Yellow
}
Write-Host ""

# 4. Port Listening Checks
Write-Host "[4] Local Port Binding Verification" -ForegroundColor White
$tcp8765 = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
if ($tcp8765) {
    Write-Host "  TCP Port 8765 : LISTENING (PID $($tcp8765.OwningProcess))" -ForegroundColor Green
} else {
    Write-Host "  TCP Port 8765 : NOT LISTENING" -ForegroundColor Gray
}
Write-Host ""

# 5. Scheduled Tasks
Write-Host "[5] Windows Task Scheduler Registration" -ForegroundColor White
$tasks = @("LAN-Dynamic-Wallpaper-Host", "LAN-Dynamic-Wallpaper-Client")
foreach ($t in $tasks) {
    $taskObj = Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
    if ($taskObj) {
        Write-Host "  Scheduled Task '$t' : PRESENT | State: $($taskObj.State)" -ForegroundColor Green
    } else {
        Write-Host "  Scheduled Task '$t' : NOT REGISTERED" -ForegroundColor Gray
    }
}
Write-Host ""

# 6. Active Application Processes
Write-Host "[6] Running Processes" -ForegroundColor White
$procs = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*Host.ps1*" -or $_.CommandLine -like "*Client.ps1*" }
if ($procs) {
    foreach ($p in $procs) {
        Write-Host "  Process PID $($p.ProcessId) : $($p.Name) | Command: $($p.CommandLine)" -ForegroundColor Green
    }
} else {
    Write-Host "  No active Host.ps1 or Client.ps1 processes currently running." -ForegroundColor Gray
}
Write-Host ""

# 7. Desktop Registry Configuration
Write-Host "[7] Current User Desktop Settings" -ForegroundColor White
try {
    $curWp = (Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'Wallpaper' -ErrorAction SilentlyContinue).Wallpaper
    $wpStyle = (Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallpaperStyle' -ErrorAction SilentlyContinue).WallpaperStyle
    Write-Host "  Active Wallpaper Path : $curWp" -ForegroundColor Gray
    Write-Host "  WallpaperStyle (Fill) : $wpStyle" -ForegroundColor Gray
} catch {
    Write-Host "  Could not read desktop wallpaper registry keys." -ForegroundColor Yellow
}
Write-Host ""

# 8. Recent Log Tails
Write-Host "[8] Recent Diagnostic Log Entries" -ForegroundColor White
$logDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\Logs"))
if (Test-Path -LiteralPath $logDir) {
    $latestLogs = Get-ChildItem -LiteralPath $logDir -File -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 2
    foreach ($lf in $latestLogs) {
        Write-Host "  Log File: $($lf.Name)" -ForegroundColor Cyan
        Get-Content -LiteralPath $lf.FullName -Tail 5 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    }
} else {
    Write-Host "  Logs directory does not exist yet." -ForegroundColor Gray
}

Write-Host "==============================================================================" -ForegroundColor Cyan
