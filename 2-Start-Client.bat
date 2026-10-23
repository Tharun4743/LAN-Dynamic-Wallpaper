@echo off
setlocal EnableDelayedExpansion

:: LAN Dynamic Wallpaper - Client Workstation Launcher
:: No Administrator privileges required for client

set "DIR=%~dp0"
set "CLIENT_SCRIPT=%DIR%Client\Client.ps1"

if not exist "%CLIENT_SCRIPT%" (
    echo [ERROR] Client\Client.ps1 not found in %DIR%
    echo [ERROR] Please ensure the LAN-Dynamic-Wallpaper folder is intact.
    pause
    exit /b 1
)

echo.
echo  Starting LAN Dynamic Wallpaper CLIENT...
echo  This will auto-discover the Host on your LAN and sync wallpapers.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CLIENT_SCRIPT%"

if %errorLevel% neq 0 (
    echo.
    echo [ERROR] Client process exited with error code %errorLevel%.
    pause
)
