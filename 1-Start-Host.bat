@echo off
setlocal EnableDelayedExpansion

:: ============================================================================
:: LAN Dynamic Wallpaper - Central Host Server & Auto LAN Broadcaster
:: Running this single file on the Host PC:
:: 1. Auto-elevates to Administrator
:: 2. Sets network to 'Private' so Windows permits Network Discovery
:: 3. Starts all Windows Discovery services (FDResPub, fdPHost, LanmanServer, SSDP)
:: 4. Shares the folder as 'LAN-Dynamic-Wallpaper' for Everyone (Read-only)
:: 5. Grants recursive NTFS read & execute access to Everyone
:: 6. Disables password-protected sharing so no password is asked on any client PC
:: 7. Opens Windows Firewall for File Sharing, Discovery, and Image Streaming
:: 8. Launches the central Host slideshow engine
:: ============================================================================

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo  =====================================================================
    echo   LAN DYNAMIC WALLPAPER - HOST SERVER LAUNCHER
    echo   Requesting Administrator privileges to start server and share folder...
    echo  =====================================================================
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

:: 1. Ensure Network Profile is 'Private' so discovery is allowed
echo  [1/6] Configuring LAN Network Profile to Private...
powershell.exe -NoProfile -Command "Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq 'Public' } | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue" >nul 2>&1

:: 2. Activate all Windows Network Discovery and Server Services
echo  [2/6] Activating Windows Network Discovery Services...
sc config FDResPub start=auto >nul 2>&1
net start FDResPub >nul 2>&1
sc config fdPHost start=auto >nul 2>&1
net start fdPHost >nul 2>&1
sc config LanmanServer start=auto >nul 2>&1
net start LanmanServer >nul 2>&1
sc config SSDPSRV start=auto >nul 2>&1
net start SSDPSRV >nul 2>&1
sc config upnphost start=auto >nul 2>&1
net start upnphost >nul 2>&1

:: 3. Open Windows Firewall for File Sharing and Discovery
echo  [3/6] Opening Windows Defender Firewall for LAN Sharing & Discovery...
netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes >nul 2>&1
netsh advfirewall firewall set rule group="Network Discovery" new enable=Yes >nul 2>&1

:: 4. Share folder across LAN for Everyone (Idempotent cleanup)
echo  [4/6] Creating Windows SMB Share 'LAN-Dynamic-Wallpaper'...
net share LAN-Dynamic-Wallpaper /delete /y >nul 2>&1
net share LAN-Dynamic-Wallpaper="%SHARE_PATH%" /grant:Everyone,READ /users:unlimited >nul 2>&1

:: 5. Recursively grant NTFS read & execute permissions to Everyone
echo  [5/6] Granting Everyone read permissions on all client files...
icacls "%SHARE_PATH%" /grant "Everyone:(OI)(CI)RX" /T /Q >nul 2>&1

:: 6. Permit password-free anonymous LAN access
echo  [6/6] Disabling password prompts for LAN clients...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v everyoneincludesanonymous /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v NullSessionShares /t REG_MULTI_SZ /d "LAN-Dynamic-Wallpaper" /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v AllowInsecureGuestAuth /t REG_DWORD /d 1 /f >nul 2>&1

echo.
echo  ====================================================================
echo   SETUP SUCCESSFUL! Host is actively broadcasting on the LAN.
echo   All 80 Client PCs can now see this computer in 'Network'!
echo  ====================================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HOST_SCRIPT%"

if %errorLevel% neq 0 (
    echo.
    echo [ERROR] Host process exited with error code %errorLevel%.
    pause
)
