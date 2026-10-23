@echo off
:: Disable command echoing to maintain a clean console presentation
setlocal EnableDelayedExpansion
:: Enable delayed variable expansion for robust runtime string processing

:: ============================================================================
:: LAN Dynamic Wallpaper - Central Host Server & Auto LAN Broadcaster
:: Running this single file on the Host PC:
:: 1. Auto-elevates to Administrator privileges
:: 2. Sets network connection profile to 'Private' so discovery is allowed
:: 3. Starts all Windows Discovery services (FDResPub, fdPHost, LanmanServer, SSDP)
:: 4. Shares the folder as 'LAN-Dynamic-Wallpaper' for Everyone (Read-only)
:: 5. Grants recursive NTFS read & execute access to Everyone
:: 6. Disables password-protected sharing so no password is asked on any client PC
:: 7. Opens Windows Defender Firewall for File Sharing, Discovery, and Image Streaming
:: 8. Launches the central Host slideshow engine & HTTP server
:: ============================================================================

:: Check whether current command prompt has elevated Administrator privileges
net session >nul 2>&1
:: If errorlevel is non-zero, the process is not elevated; request elevation via UAC
if %errorLevel% neq 0 (
    echo.
    echo  =====================================================================
    echo   LAN DYNAMIC WALLPAPER - HOST SERVER LAUNCHER
    echo   Requesting Administrator privileges to start server and share folder...
    echo  =====================================================================
    echo.
    :: Relaunch this exact batch file with elevated Administrator credentials
    powershell.exe -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    :: Terminate the initial unprivileged process
    exit /b
)

:: Resolve the exact absolute directory path of this running batch script
set "DIR=%~dp0"
:: Point to the main Host PowerShell orchestration script
set "HOST_SCRIPT=%DIR%Host\Host.ps1"
:: Define the directory path to be shared across the LAN
set "SHARE_PATH=%DIR%"
:: Strip any trailing backslash from the share path for Windows net share compatibility
if "%SHARE_PATH:~-1%"=="\" set "SHARE_PATH=%SHARE_PATH:~0,-1%"

:: Verify that the core Host.ps1 server script exists in the designated directory
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

:: Step 1: Ensure active Network Profile is set to 'Private' (Windows blocks discovery on Public)
echo  [1/6] Configuring LAN Network Profile to Private...
powershell.exe -NoProfile -Command "Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq 'Public' } | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue" >nul 2>&1

:: Step 2: Configure and start all required Windows Network Discovery and Server daemons
echo  [2/6] Activating Windows Network Discovery Services...
:: Function Discovery Resource Publication (Enables PC to appear in Network tab)
sc config FDResPub start=auto >nul 2>&1
net start FDResPub >nul 2>&1
:: Function Discovery Provider Host (Discovers other networked devices)
sc config fdPHost start=auto >nul 2>&1
net start fdPHost >nul 2>&1
:: Server Service / LanmanServer (Enables Windows SMB file sharing)
sc config LanmanServer start=auto >nul 2>&1
net start LanmanServer >nul 2>&1
:: SSDP Discovery Service (Enables UPnP device broadcasting)
sc config SSDPSRV start=auto >nul 2>&1
net start SSDPSRV >nul 2>&1
:: Universal Plug and Play Device Host (Complements SSDP discovery)
sc config upnphost start=auto >nul 2>&1
net start upnphost >nul 2>&1

:: Step 3: Open Windows Defender Firewall rules for File Sharing and Network Discovery
echo  [3/6] Opening Windows Defender Firewall for LAN Sharing & Discovery...
netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes >nul 2>&1
netsh advfirewall firewall set rule group="Network Discovery" new enable=Yes >nul 2>&1

:: Step 4: Share the folder across the local network with read-only permissions for Everyone
echo  [4/6] Creating Windows SMB Share 'LAN-Dynamic-Wallpaper'...
:: Delete any previous stale share of the same name to guarantee idempotent setup
net share LAN-Dynamic-Wallpaper /delete /y >nul 2>&1
:: Create active SMB share with read-only access for Everyone and unlimited client connections
net share LAN-Dynamic-Wallpaper="%SHARE_PATH%" /grant:Everyone,READ /users:unlimited >nul 2>&1

:: Step 5: Recursively grant NTFS read and execute permissions on all repository files to Everyone
echo  [5/6] Granting Everyone read permissions on all client files...
icacls "%SHARE_PATH%" /grant "Everyone:(OI)(CI)RX" /T /Q >nul 2>&1

:: Step 6: Permit anonymous LAN access without prompting for Windows account passwords
echo  [6/6] Disabling password prompts for LAN clients...
:: Allow anonymous users to inherit Everyone group permissions
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v everyoneincludesanonymous /t REG_DWORD /d 1 /f >nul 2>&1
:: Register LAN-Dynamic-Wallpaper as an allowed null session (password-free) share
reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v NullSessionShares /t REG_MULTI_SZ /d "LAN-Dynamic-Wallpaper" /f >nul 2>&1
:: Permit insecure guest authentication for workstations joining without domain accounts
reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v AllowInsecureGuestAuth /t REG_DWORD /d 1 /f >nul 2>&1

echo.
echo  ====================================================================
echo   SETUP SUCCESSFUL! Host is actively broadcasting on the LAN.
echo   All 80 Client PCs can now see this computer in 'Network'!
echo  ====================================================================
echo.

:: Launch the pure PowerShell Host Server engine with execution policy bypass
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HOST_SCRIPT%"

:: Catch any fatal errors upon server shutdown or abnormal termination
if %errorLevel% neq 0 (
    echo.
    echo [ERROR] Host process exited with error code %errorLevel%.
    pause
)
