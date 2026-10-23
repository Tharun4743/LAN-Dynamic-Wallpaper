@echo off
setlocal EnableDelayedExpansion

set "DIR=%~dp0"
set "CLIENT_SCRIPT=%DIR%Client\Client.ps1"

if not exist "%CLIENT_SCRIPT%" (
    echo [ERROR] Client\Client.ps1 not found in %DIR%
    pause
    exit /b 1
)

echo.
echo  Starting LAN Dynamic Wallpaper CLIENT...
echo  Auto-discovering Host on LAN and syncing wallpapers...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CLIENT_SCRIPT%"

if %errorLevel% neq 0 (
    echo.
    echo [ERROR] Client process exited with error code %errorLevel%.
    pause
)
