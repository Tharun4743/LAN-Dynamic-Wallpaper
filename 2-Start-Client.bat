@echo off
:: Disable command echoing for a clean, professional console output
setlocal EnableDelayedExpansion
:: Enable delayed variable expansion for runtime string tokenization

:: ============================================================================
:: LAN Dynamic Wallpaper - Client Workstation Launcher
:: STRICTLY NO ADMINISTRATOR PRIVILEGES REQUIRED - Runs as standard unprivileged user
:: Compatible with: Local Drive, USB Storage, or Windows Network Share (\\Host\Share)
:: ============================================================================

:: Store the directory from which this batch script was initiated
set "SOURCE_DIR=%~dp0"
:: Define isolated local directory in user AppData to store cached wallpapers and scripts
set "LOCAL_CLIENT=%LOCALAPPDATA%\LAN-Dynamic-Wallpaper-Client"
:: Initialize server override variable as empty
set "SERVER_OVERRIDE="

:: Check if launched from a UNC network share path (starts with double backslash \\)
if "%SOURCE_DIR:~0,2%"=="\\" (
    :: Extract the Host Computer Name dynamically from the UNC path (e.g., \\HOST-PC\...)
    for /f "tokens=1 delims=\" %%A in ("%SOURCE_DIR:~2%") do set "SERVER_OVERRIDE=%%A"
)

echo.
echo  ====================================================================
echo   LAN DYNAMIC WALLPAPER - CLIENT WORKSTATION
echo   Connecting to Host and synchronizing desktop wallpaper...
echo   (Running as standard user - No administrator privileges needed)
echo  ====================================================================
echo.

:: Ensure the local client application directory exists on the workstation
if not exist "%LOCAL_CLIENT%" mkdir "%LOCAL_CLIENT%" >nul 2>&1
:: Ensure the local wallpaper cache folder exists on the workstation
if not exist "%LOCAL_CLIENT%\Cache" mkdir "%LOCAL_CLIENT%\Cache" >nul 2>&1

:: Copy client scripts to local machine for maximum execution speed and reliability
if exist "%SOURCE_DIR%Client\Client.ps1" (
    :: Copy primary client agent script to local AppData directory
    copy /y "%SOURCE_DIR%Client\Client.ps1" "%LOCAL_CLIENT%\Client.ps1" >nul 2>&1
    :: Copy Win32 wallpaper engine script to local AppData directory
    copy /y "%SOURCE_DIR%Client\Wallpaper.ps1" "%LOCAL_CLIENT%\Wallpaper.ps1" >nul 2>&1
    :: Copy client configuration file if not already present locally
    if not exist "%LOCAL_CLIENT%\ClientConfig.json" (
        copy /y "%SOURCE_DIR%Client\ClientConfig.json" "%LOCAL_CLIENT%\ClientConfig.json" >nul 2>&1
    )
    :: Set script target to the local AppData copy
    set "RUN_SCRIPT=%LOCAL_CLIENT%\Client.ps1"
) else if exist "%SOURCE_DIR%Client.ps1" (
    :: Fallback: If launched directly inside the Client folder
    copy /y "%SOURCE_DIR%Client.ps1" "%LOCAL_CLIENT%\Client.ps1" >nul 2>&1
    copy /y "%SOURCE_DIR%Wallpaper.ps1" "%LOCAL_CLIENT%\Wallpaper.ps1" >nul 2>&1
    if not exist "%LOCAL_CLIENT%\ClientConfig.json" (
        copy /y "%SOURCE_DIR%ClientConfig.json" "%LOCAL_CLIENT%\ClientConfig.json" >nul 2>&1
    )
    set "RUN_SCRIPT=%LOCAL_CLIENT%\Client.ps1"
) else (
    :: Default fallback to local AppData script path
    set "RUN_SCRIPT=%LOCAL_CLIENT%\Client.ps1"
)

:: Execute the Client Agent in PowerShell with ExecutionPolicy Bypass
if not "%SERVER_OVERRIDE%"=="" (
    :: If running from a network share, pass the dynamically extracted Host name directly
    echo  Connected via Network Share from Host: %SERVER_OVERRIDE%
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%RUN_SCRIPT%" -HostAddress "%SERVER_OVERRIDE%"
) else (
    :: If running from a local drive, let UDP beacon and subnet sweep find the Host dynamically
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%RUN_SCRIPT%"
)

:: Display error message and pause only if the PowerShell process terminates unexpectedly
if %errorLevel% neq 0 (
    echo.
    echo [ERROR] Client process exited with error code %errorLevel%.
    pause
)
