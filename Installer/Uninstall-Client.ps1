# ==============================================================================
# Installer/Uninstall-Client.ps1
# LAN Dynamic Wallpaper - Clean Client Uninstaller
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$PurgeCache
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "==============================================================================" -ForegroundColor Yellow
Write-Host " LAN DYNAMIC WALLPAPER SLIDESHOW - CLIENT UNINSTALLER" -ForegroundColor Yellow
Write-Host "==============================================================================" -ForegroundColor Yellow

# 1. Stop Client Agent Process
Write-Host "[1/3] Terminating Client Agent process..." -ForegroundColor Cyan
$procs = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*Client.ps1*" }
foreach ($p in $procs) {
    try {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "  Terminated Client Agent PID $($p.ProcessId)" -ForegroundColor Gray
    } catch {}
}

# 2. Unregister Client Task
Write-Host "[2/3] Removing Client Scheduled Task..." -ForegroundColor Cyan
$startupScript = Join-Path $PSScriptRoot "Configure-Startup.ps1"
if (Test-Path -LiteralPath $startupScript) {
    & $startupScript -Role "Client" -Remove
} else {
    Unregister-ScheduledTask -TaskName "LAN-Dynamic-Wallpaper-Client" -Confirm:$false -ErrorAction SilentlyContinue
}

# 3. Optional Cache Purge
if ($PurgeCache) {
    Write-Host "[3/3] Purging client cache directory..." -ForegroundColor Cyan
    $appRoot = Split-Path $PSScriptRoot -Parent
    $cacheDir = Join-Path $appRoot "Cache"
    if (Test-Path -LiteralPath $cacheDir) {
        Remove-Item -LiteralPath $cacheDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Cache directory purged." -ForegroundColor Gray
    }
} else {
    Write-Host "[3/3] Preserving downloaded wallpaper cache (use -PurgeCache to erase)." -ForegroundColor Gray
}

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host " CLIENT REMOVED SUCCESSFULLY" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green
