@echo off
setlocal EnableDelayedExpansion

:: ============================================================================
:: LAN Dynamic Wallpaper - Central Host Server & Auto LAN Share
:: Running this single file on the Host PC:
:: 1. Binds HTTP server (Port 8765) and UDP Discovery (Port 8766)
:: 2. Automatically shares this folder across LAN via Windows File Sharing (SMB)
:: 3. Sets permissions for 'Everyone' so NO PASSWORD is asked on client PCs
:: 4. Opens Windows Defender Firewall for LAN access
:: ============================================================================

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo =====================================================================
    echo  LAN DYNAMIC WALLPAPER - HOST SERVER LAUNCHER
    echo  Requesting Administrator privileges to start server and share folder...
    echo =====================================================================
    echo.
    powershell.exe -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

set "DIR=%~dp0"
set "HOST_SCRIPT=%DIR%Host\Host.ps1"
set "SHARE_PATH=%DIR%"
if "%SHARE_PATH:~-1%"=="\" set "SHARE_PATH=%SHARE_PATH:~0,-1%"

if not exist "%HOST_SCRIPT%" (
    echo [ERROR] Host\Host.ps1 not found in %DIR%
    pause
    exit /b 1
)

echo.
echo  ====================================================================
echo   LAN DYNAMIC WALLPAPER - ALL-IN-ONE HOST MANAGER
echo  ====================================================================
echo.

:: 1. Share folder on LAN with Read permissions for Everyone
echo  [1/4] Configuring Windows Network Folder Share...
net share LAN-Dynamic-Wallpaper="%SHARE_PATH%" /grant:Everyone,READ /users:100 >nul 2>&1

:: 2. Grant NTFS permissions to Everyone
echo  [2/4] Setting folder security access for Everyone (Read & Execute)...
icacls "%SHARE_PATH%" /grant "Everyone:(OI)(CI)RX" /Q >nul 2>&1

:: 3. Open Windows Firewall for File Sharing & Network Discovery
echo  [3/5] Enabling File Sharing and Network Discovery in Firewall...
netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes >nul 2>&1
netsh advfirewall firewall set rule group="Network Discovery" new enable=Yes >nul 2>&1

:: 4. Ensure Host PC publishes itself so it appears under 'Network' in File Explorer
echo  [4/5] Activating Network Discovery Service (FDResPub)...
sc config FDResPub start=auto >nul 2>&1
net start FDResPub >nul 2>&1

:: 5. Disable password protected sharing for zero-password LAN access
echo  [5/5] Permitting password-free LAN access...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v everyoneincludesanonymous /t REG_DWORD /d 1 /f >nul 2>&1

echo.
echo  Host PC will appear automatically under 'Network' in File Explorer!
echo  Starting Host Slideshow Server...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HOST_SCRIPT%"

if %errorLevel% neq 0 (
    echo.
    echo [ERROR] Host process exited with error code %errorLevel%.
    pause
)
