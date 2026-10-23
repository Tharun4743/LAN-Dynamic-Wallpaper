@echo off
setlocal EnableDelayedExpansion
title LAN Dynamic Wallpaper - Client Workstation Slideshow Agent

:: ==============================================================================
:: 1. STRICT RELATIVE PATH RESOLUTION
:: ==============================================================================
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: Support execution from parent folder (e.g. IT\Start-Client.bat targeting LAN-Dynamic-Wallpaper)
if exist "%SCRIPT_DIR%\LAN-Dynamic-Wallpaper\Client\Client.ps1" (
    set "APP_DIR=%SCRIPT_DIR%\LAN-Dynamic-Wallpaper"
) else (
    set "APP_DIR=%SCRIPT_DIR%"
)
cd /d "%APP_DIR%"

cls
echo ==============================================================================
echo  LAN DYNAMIC WALLPAPER SLIDESHOW - CLIENT WORKSTATION (Windows 11 / 10)
echo ==============================================================================
echo.

:: ==============================================================================
:: 2. ENVIRONMENT & SCRIPT VALIDATION
:: ==============================================================================
if not exist "%APP_DIR%\Client\Client.ps1" (
    echo [ERROR] Required script missing: %APP_DIR%\Client\Client.ps1
    echo Please ensure the repository files are intact.
    pause
    exit /b 1
)

if not exist "%APP_DIR%\Client\Wallpaper.ps1" (
    echo [ERROR] Required script missing: %APP_DIR%\Client\Wallpaper.ps1
    echo Please ensure the repository files are intact.
    pause
    exit /b 1
)

:: Validate PowerShell 5.1+
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "if ($PSVersionTable.PSVersion.Major -lt 5) { exit 1 } else { exit 0 }"
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Windows PowerShell 5.1 or newer is required to run the Client Workstation Agent.
    pause
    exit /b 1
)

:: ==============================================================================
:: 3. LAUNCH CLIENT SLIDESHOW AGENT IN INTERACTIVE DESKTOP SESSION
:: ==============================================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%APP_DIR%\Client\Client.ps1"

set CLIENT_EXIT_CODE=%ERRORLEVEL%
if %CLIENT_EXIT_CODE% neq 0 (
    echo.
    echo ==============================================================================
    echo  [NOTICE] Client agent stopped with code %CLIENT_EXIT_CODE%.
    echo  Please inspect the log files in %APP_DIR%\Logs\ for troubleshooting details.
    echo ==============================================================================
    echo.
    pause
)
exit /b %CLIENT_EXIT_CODE%
