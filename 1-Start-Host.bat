@echo off
setlocal EnableDelayedExpansion

:: LAN Dynamic Wallpaper - Host Server Launcher
:: Run as Administrator for full LAN binding support

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [INFO] Requesting Administrator privileges for LAN port binding...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "DIR=%~dp0"
set "HOST_SCRIPT=%DIR%Host\Host.ps1"

if not exist "%HOST_SCRIPT%" (
    echo [ERROR] Host\Host.ps1 not found in %DIR%
    echo [ERROR] Please ensure the LAN-Dynamic-Wallpaper folder is intact.
    pause
    exit /b 1
)

echo.
echo  Starting LAN Dynamic Wallpaper HOST SERVER...
echo  Drop your images into the Wallpapers\ folder and they will sync to all clients.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HOST_SCRIPT%"

if %errorLevel% neq 0 (
    echo.
    echo [ERROR] Host process exited with error code %errorLevel%.
    pause
)
