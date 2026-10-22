@echo off
setlocal EnableDelayedExpansion
title LAN Dynamic Wallpaper - Client Slideshow Agent
cd /d "%~dp0"

cls
echo ==============================================================================
echo  LAN DYNAMIC WALLPAPER SLIDESHOW - CLIENT WORKSTATION (Windows 11 / 10)
echo ==============================================================================
echo.

:: Dynamically detect client LAN IP
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1).IPAddress; " ^
  "Write-Host ' ==============================================================================' -ForegroundColor Cyan; " ^
  "Write-Host '  💻 CLIENT WORKSTATION STATUS:' -ForegroundColor White; " ^
  "Write-Host '  🌐 Local Client IPv4 : ' -NoNewline -ForegroundColor Gray; Write-Host $ip -ForegroundColor Cyan; " ^
  "Write-Host '  ⏱️ Slideshow Timer   : 5 SECONDS' -ForegroundColor Yellow; " ^
  "Write-Host '  🔍 Auto-Discovery    : Scanning LAN for Host PC (UDP + Subnet Probe)...' -ForegroundColor Gray; " ^
  "Write-Host ' ==============================================================================' -ForegroundColor Cyan"

echo.
echo  ------------------------------------------------------------------------------
echo   Connecting to Host PC, Downloading Photos & Starting 5s Slideshow...
echo  ------------------------------------------------------------------------------
echo.

:: Launch Client Slideshow Agent
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Client\Client.ps1"

if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] Client agent exited with error code %ERRORLEVEL%.
    pause
)
exit /b %ERRORLEVEL%

