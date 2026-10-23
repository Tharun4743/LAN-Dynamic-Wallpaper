@echo off
setlocal EnableDelayedExpansion
title LAN Dynamic Wallpaper - Client Slideshow Agent

:: 1. Locate project root (supports running from outer IT directory or inside repo root)
if exist "%~dp0LAN-Dynamic-Wallpaper\Client\Client.ps1" (
    set "APP_DIR=%~dp0LAN-Dynamic-Wallpaper"
) else (
    set "APP_DIR=%~dp0"
)
cd /d "!APP_DIR!"

cls
echo ==============================================================================
echo  LAN DYNAMIC WALLPAPER SLIDESHOW - CLIENT WORKSTATION (Windows 11 / 10)
echo ==============================================================================
echo.

:: 2. Launch Client Slideshow Agent in interactive console
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!APP_DIR!\Client\Client.ps1"

if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] Client agent exited with error code %ERRORLEVEL%.
    pause
)
exit /b %ERRORLEVEL%
