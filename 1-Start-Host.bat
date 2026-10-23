@echo off
setlocal EnableDelayedExpansion

:: LAN Dynamic Wallpaper - Central Host Server Launcher
:: Requests Admin elevation so HTTP.sys can bind port 8765 to all LAN adapters
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [INFO] Elevating Host Server to bind LAN HTTP port 8765...
    powershell.exe -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

set "DIR=%~dp0"
set "HOST_SCRIPT=%DIR%Host\Host.ps1"

if not exist "%HOST_SCRIPT%" (
    echo [ERROR] Host\Host.ps1 not found in %DIR%
    pause
    exit /b 1
)

echo.
echo  ====================================================================
echo   LAN Dynamic Wallpaper - HOST SERVER
echo   Drop images into the Wallpapers\ folder to sync to all clients.
echo  ====================================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HOST_SCRIPT%"

if %errorLevel% neq 0 (
    echo.
    echo [ERROR] Host process exited with error code %errorLevel%.
    pause
)
