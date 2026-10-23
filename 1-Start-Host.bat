@echo off
setlocal EnableDelayedExpansion
title LAN Dynamic Wallpaper - Host PC & Slideshow Controller

:: 1. Verify and request Administrator elevation if needed
net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ==============================================================================
    echo  LAN DYNAMIC WALLPAPER - HOST MANAGER
    echo ==============================================================================
    echo  [INFO] Requesting Administrator privileges to bind LAN port and configure firewall...
    echo.
    powershell.exe -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

:: 2. Locate project root (supports running from outer IT directory or inside repo root)
if exist "%~dp0LAN-Dynamic-Wallpaper\Host\Host.ps1" (
    set "APP_DIR=%~dp0LAN-Dynamic-Wallpaper"
) else (
    set "APP_DIR=%~dp0"
)
cd /d "!APP_DIR!"

cls
echo ==============================================================================
echo  LAN DYNAMIC WALLPAPER SLIDESHOW - HOST MANAGER (Windows 11 / 10)
echo ==============================================================================
echo.

:: 3. Automatically ensure Wallpapers drop folder exists and open in Windows Explorer
if not exist "!APP_DIR!\Wallpapers" mkdir "!APP_DIR!\Wallpapers"
start "" explorer.exe "!APP_DIR!\Wallpapers"

:: 4. Idempotently ensure Windows Firewall rules & URL ACL are active on Administrator launch
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$tcp = Get-NetFirewallRule -DisplayName 'LAN-Dynamic-Wallpaper-Host-HTTP' -ErrorAction SilentlyContinue; " ^
  "if (-not $tcp) { New-NetFirewallRule -DisplayName 'LAN-Dynamic-Wallpaper-Host-HTTP' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8765 -Profile 'Private,Domain' -ErrorAction SilentlyContinue | Out-Null }; " ^
  "$udp = Get-NetFirewallRule -DisplayName 'LAN-Dynamic-Wallpaper-Host-Discovery' -ErrorAction SilentlyContinue; " ^
  "if (-not $udp) { New-NetFirewallRule -DisplayName 'LAN-Dynamic-Wallpaper-Host-Discovery' -Direction Inbound -Action Allow -Protocol UDP -LocalPort 8766 -Profile 'Private,Domain' -ErrorAction SilentlyContinue | Out-Null }; " ^
  "$acl = (netsh http show urlacl url=http://+:8765/ 2>&1) -join ' '; " ^
  "if ($acl -notlike '*http://+:8765/*') { netsh http add urlacl url=http://+:8765/ user=Everyone 2>&1 | Out-Null }"

:: 5. Launch Host Server in interactive console
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!APP_DIR!\Host\Host.ps1"

if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] Host process exited with error code %ERRORLEVEL%.
    pause
)
exit /b %ERRORLEVEL%
