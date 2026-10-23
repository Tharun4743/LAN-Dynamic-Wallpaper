@echo off
setlocal EnableDelayedExpansion

set "DIR=%~dp0"
set "HOST_SCRIPT=%DIR%Host\Host.ps1"

if not exist "%HOST_SCRIPT%" (
    echo [ERROR] Host\Host.ps1 not found in %DIR%
    pause
    exit /b 1
)

echo.
echo  Starting LAN Dynamic Wallpaper HOST SERVER...
echo  Drop images into the Wallpapers\ folder to sync to all clients.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HOST_SCRIPT%"

if %errorLevel% neq 0 (
    echo.
    echo [ERROR] Host process exited with error code %errorLevel%.
    pause
)
