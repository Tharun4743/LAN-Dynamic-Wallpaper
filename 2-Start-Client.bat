@echo off
setlocal EnableDelayedExpansion

:: ============================================================================
:: LAN Dynamic Wallpaper - Client Workstation Launcher
:: STRICTLY NO ADMINISTRATOR PRIVILEGES REQUIRED - Runs as normal standard user
:: Works from Local Drive, USB Stick, or Windows Network Share (\\Host\Share)
:: ============================================================================

set "SOURCE_DIR=%~dp0"
set "LOCAL_CLIENT=%LOCALAPPDATA%\LAN-Dynamic-Wallpaper-Client"
set "SERVER_OVERRIDE="

:: Detect if launched from a network share (e.g. \\HOST-PC\LAN-Dynamic-Wallpaper\)
if "%SOURCE_DIR:~0,2%"=="\\" (
    for /f "tokens=1 delims=\" %%A in ("%SOURCE_DIR:~2%") do set "SERVER_OVERRIDE=%%A"
)

echo.
echo  ====================================================================
echo   LAN DYNAMIC WALLPAPER - CLIENT WORKSTATION
echo   Connecting to Host and synchronizing desktop wallpaper...
echo   (Running as standard user - No administrator privileges needed)
echo  ====================================================================
echo.

:: Ensure local client working directory exists
if not exist "%LOCAL_CLIENT%" mkdir "%LOCAL_CLIENT%" >nul 2>&1
if not exist "%LOCAL_CLIENT%\Cache" mkdir "%LOCAL_CLIENT%\Cache" >nul 2>&1

:: Copy client scripts to local machine for maximum reliability
if exist "%SOURCE_DIR%Client\Client.ps1" (
    copy /y "%SOURCE_DIR%Client\Client.ps1" "%LOCAL_CLIENT%\Client.ps1" >nul 2>&1
    copy /y "%SOURCE_DIR%Client\Wallpaper.ps1" "%LOCAL_CLIENT%\Wallpaper.ps1" >nul 2>&1
    if not exist "%LOCAL_CLIENT%\ClientConfig.json" (
        copy /y "%SOURCE_DIR%Client\ClientConfig.json" "%LOCAL_CLIENT%\ClientConfig.json" >nul 2>&1
    )
    set "RUN_SCRIPT=%LOCAL_CLIENT%\Client.ps1"
) else if exist "%SOURCE_DIR%Client.ps1" (
    copy /y "%SOURCE_DIR%Client.ps1" "%LOCAL_CLIENT%\Client.ps1" >nul 2>&1
    copy /y "%SOURCE_DIR%Wallpaper.ps1" "%LOCAL_CLIENT%\Wallpaper.ps1" >nul 2>&1
    if not exist "%LOCAL_CLIENT%\ClientConfig.json" (
        copy /y "%SOURCE_DIR%ClientConfig.json" "%LOCAL_CLIENT%\ClientConfig.json" >nul 2>&1
    )
    set "RUN_SCRIPT=%LOCAL_CLIENT%\Client.ps1"
) else (
    set "RUN_SCRIPT=%LOCAL_CLIENT%\Client.ps1"
)

:: Run Client Agent (with Host override if opened from network share)
if not "%SERVER_OVERRIDE%"=="" (
    echo  Connected via Network Share from Host: %SERVER_OVERRIDE%
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%RUN_SCRIPT%" -HostAddress "%SERVER_OVERRIDE%"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%RUN_SCRIPT%"
)

if %errorLevel% neq 0 (
    echo.
    echo [ERROR] Client process exited with error code %errorLevel%.
    pause
)
