@echo off
setlocal EnableDelayedExpansion

:: LAN Dynamic Wallpaper - Client Workstation Launcher
:: STRICTLY NO ADMINISTRATOR PRIVILEGES REQUIRED - Runs as normal user

set "DIR=%~dp0"
set "CLIENT_SCRIPT=%DIR%Client\Client.ps1"

if not exist "%CLIENT_SCRIPT%" (
    echo [ERROR] Client\Client.ps1 not found in %DIR%
    pause
    exit /b 1
)

echo.
echo  ====================================================================
echo   LAN Dynamic Wallpaper - CLIENT WORKSTATION
echo   Auto-discovering Host on LAN and syncing wallpapers...
echo   (Running as standard user - No administrator privileges needed)
echo  ====================================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CLIENT_SCRIPT%"

if %errorLevel% neq 0 (
    echo.
    echo [ERROR] Client process exited with error code %errorLevel%.
    pause
)
