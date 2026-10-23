@echo off
setlocal EnableDelayedExpansion
title LAN Dynamic Wallpaper - Host Server & Slideshow Manager

:: ==============================================================================
:: 1. STRICT RELATIVE PATH RESOLUTION
:: ==============================================================================
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: Support execution from parent folder (e.g. IT\Start-Host.bat targeting LAN-Dynamic-Wallpaper)
if exist "%SCRIPT_DIR%\LAN-Dynamic-Wallpaper\Host\Host.ps1" (
    set "APP_DIR=%SCRIPT_DIR%\LAN-Dynamic-Wallpaper"
) else (
    set "APP_DIR=%SCRIPT_DIR%"
)
cd /d "%APP_DIR%"

:: ==============================================================================
:: 2. UAC ELEVATION DETECTION (NO RECURSIVE ELEVATION LOOP)
:: ==============================================================================
net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ==============================================================================
    echo  LAN DYNAMIC WALLPAPER - HOST CONTROLLER (ADMINISTRATOR SETUP)
    echo ==============================================================================
    echo  [INFO] Requesting Administrator elevation to bind LAN ports and configure firewall...
    echo.
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

cls
echo ==============================================================================
echo  LAN DYNAMIC WALLPAPER SLIDESHOW - HOST CONTROLLER (Windows 11 / 10)
echo ==============================================================================
echo.

:: ==============================================================================
:: 3. ENVIRONMENT & SCRIPT VALIDATION
:: ==============================================================================
if not exist "%APP_DIR%\Host\Host.ps1" (
    echo [ERROR] Required script missing: %APP_DIR%\Host\Host.ps1
    echo Please ensure the repository files are intact.
    pause
    exit /b 1
)

if not exist "%APP_DIR%\Host\Publisher.ps1" (
    echo [ERROR] Required script missing: %APP_DIR%\Host\Publisher.ps1
    echo Please ensure the repository files are intact.
    pause
    exit /b 1
)

:: Validate PowerShell 5.1+
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "if ($PSVersionTable.PSVersion.Major -lt 5) { exit 1 } else { exit 0 }"
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Windows PowerShell 5.1 or newer is required to run the Host Server.
    pause
    exit /b 1
)

:: ==============================================================================
:: 4. WALLPAPERS FOLDER PREPARATION & EXPLORER OPEN
:: ==============================================================================
if not exist "%APP_DIR%\Wallpapers" mkdir "%APP_DIR%\Wallpapers"
start "" explorer.exe "%APP_DIR%\Wallpapers"

:: ==============================================================================
:: 5. IDEMPOTENT FIREWALL & HTTP.SYS URL ACL CONFIGURATION
:: ==============================================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$tcp = Get-NetFirewallRule -DisplayName 'LAN-Dynamic-Wallpaper-Host-HTTP' -ErrorAction SilentlyContinue; " ^
  "if (-not $tcp) { " ^
  "  New-NetFirewallRule -DisplayName 'LAN-Dynamic-Wallpaper-Host-HTTP' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8765 -Profile 'Private,Domain' -Description 'Inbound HTTP access for LAN dynamic wallpaper clients' -ErrorAction SilentlyContinue | Out-Null; " ^
  "  Write-Host '  [FIREWALL] Created inbound rule for TCP 8765 (Private/Domain)' -ForegroundColor Green " ^
  "}; " ^
  "$udp = Get-NetFirewallRule -DisplayName 'LAN-Dynamic-Wallpaper-Host-Discovery' -ErrorAction SilentlyContinue; " ^
  "if (-not $udp) { " ^
  "  New-NetFirewallRule -DisplayName 'LAN-Dynamic-Wallpaper-Host-Discovery' -Direction Inbound -Action Allow -Protocol UDP -LocalPort 8766 -Profile 'Private,Domain' -Description 'Inbound UDP discovery for LAN dynamic wallpaper clients' -ErrorAction SilentlyContinue | Out-Null; " ^
  "  Write-Host '  [FIREWALL] Created inbound rule for UDP 8766 (Private/Domain)' -ForegroundColor Green " ^
  "}; " ^
  "$acl = (netsh http show urlacl url=http://+:8765/ 2>&1) -join ' '; " ^
  "if ($acl -notlike '*http://+:8765/*') { " ^
  "  netsh http add urlacl url=http://+:8765/ user=Everyone 2>&1 | Out-Null; " ^
  "  Write-Host '  [NETWORK] Reserved HTTP.sys URL ACL http://+:8765/' -ForegroundColor Green " ^
  "}"

:: ==============================================================================
:: 6. LAUNCH HOST SERVER & SLIDESHOW ENGINE
:: ==============================================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%APP_DIR%\Host\Host.ps1"

set HOST_EXIT_CODE=%ERRORLEVEL%
if %HOST_EXIT_CODE% neq 0 (
    echo.
    echo ==============================================================================
    echo  [ERROR] Host server process exited unexpectedly with code %HOST_EXIT_CODE%.
    echo  Please inspect the log files in %APP_DIR%\Logs\ for detailed error tracing.
    echo ==============================================================================
    echo.
    pause
)
exit /b %HOST_EXIT_CODE%
