@echo off
title LAN Dynamic Wallpaper - Client Installer
cd /d "%~dp0"

echo ==============================================================================
echo  LAN DYNAMIC WALLPAPER SLIDESHOW - CLIENT INSTALLER
echo ==============================================================================
echo  Setting up Client Agent, downloading initial wallpapers, and configuring startup...
echo ==============================================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Client.ps1"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Installation failed with exit code %ERRORLEVEL%.
    pause
) else (
    echo.
    echo [SUCCESS] Client installation completed.
    timeout /t 5
)
