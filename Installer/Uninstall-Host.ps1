# ==============================================================================
# Installer/Uninstall-Host.ps1
# LAN Dynamic Wallpaper - Clean Host Decommissioning Script
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$PurgeData
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Elevation required to uninstall host components. Relaunching as Administrator..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit 0
}

Write-Host "==============================================================================" -ForegroundColor Yellow
Write-Host " LAN DYNAMIC WALLPAPER SLIDESHOW - HOST UNINSTALLER" -ForegroundColor Yellow
Write-Host "==============================================================================" -ForegroundColor Yellow

# 1. Stop Running Host Processes
Write-Host "[1/4] Terminating Host server processes..." -ForegroundColor Cyan
$procs = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*Host.ps1*" }
foreach ($p in $procs) {
    try {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "  Terminated Host process PID $($p.ProcessId)" -ForegroundColor Gray
    } catch {}
}

# 2. Unregister Scheduled Task
Write-Host "[2/4] Removing Host Scheduled Task..." -ForegroundColor Cyan
$startupScript = Join-Path $PSScriptRoot "Configure-Startup.ps1"
if (Test-Path -LiteralPath $startupScript) {
    & $startupScript -Role "Host" -Remove
} else {
    Unregister-ScheduledTask -TaskName "LAN-Dynamic-Wallpaper-Host" -Confirm:$false -ErrorAction SilentlyContinue
}

# 3. Remove Firewall Rules & URL ACL
Write-Host "[3/4] Removing Firewall Rules & URL ACL..." -ForegroundColor Cyan
$firewallScript = Join-Path $PSScriptRoot "Configure-Firewall.ps1"
if (Test-Path -LiteralPath $firewallScript) {
    & $firewallScript -Remove
}

try {
    netsh http delete urlacl url="http://+:8765/" 2>&1 | Out-Null
    Write-Host "  [OK] Removed URL ACL reservation for port 8765" -ForegroundColor Green
} catch {}

# 4. Optional Data Purge
if ($PurgeData) {
    Write-Host "[4/4] Purging published images and client registry..." -ForegroundColor Cyan
    $appRoot = Split-Path $PSScriptRoot -Parent
    $pubDir = Join-Path $appRoot "Published"
    $clientsJson = Join-Path $appRoot "Host\clients.json"
    if (Test-Path -LiteralPath $pubDir) { Remove-Item -LiteralPath $pubDir -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $clientsJson) { Remove-Item -LiteralPath $clientsJson -Force -ErrorAction SilentlyContinue }
    Write-Host "  Data directories purged." -ForegroundColor Gray
} else {
    Write-Host "[4/4] Preserving Wallpapers directory and configuration (use -PurgeData to erase)." -ForegroundColor Gray
}

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host " HOST DECOMMISSIONED SUCCESSFULLY" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green
