@echo off
setlocal EnableDelayedExpansion

:: ============================================================================
:: LAN Dynamic Wallpaper - Step 1: Host Network Share
:: ============================================================================
:: Creates a read-only SMB share of Client\ folder only.
:: Auto-writes host IP to Client\_HOSTINFO.txt for client discovery.
:: Enables Network Discovery so other PCs can see this host on LAN.
:: Share stays open until you run 4-Host-Network-Stop.bat.
:: Wallpaper service is completely independent.
:: ============================================================================

:: ── Privilege check ──────────────────────────────────────────────────────────
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo  ====================================================================
    echo   LAN DYNAMIC WALLPAPER  -  HOST NETWORK SHARE
    echo   Administrator privileges required. Relaunching with UAC...
    echo  ====================================================================
    echo.
    powershell.exe -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b 0
)

:: ── Fix CWD after UAC elevation (elevated CMD starts in System32) ────────────
cd /d "%~dp0"

:: ── Resolve paths ─────────────────────────────────────────────────────────────
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "CLIENT_PKG_PATH=%SCRIPT_DIR%\Client"
set "SHARE_NAME=LAN-WP-ClientPkg"
set "OLD_SHARE_NAME=LAN-Dynamic-Wallpaper"

:: ── Sanity check ──────────────────────────────────────────────────────────────
if not exist "%CLIENT_PKG_PATH%\" (
    echo.
    echo [ERROR] Client package directory not found: %CLIENT_PKG_PATH%
    echo         Run this from the LAN-Dynamic-Wallpaper project root.
    echo.
    pause
    exit /b 1
)

:: ── Ensure single client launcher batch file is in shared Client folder ───────
if exist "%SCRIPT_DIR%\3-Client-Download-Start.bat" (
    copy /y "%SCRIPT_DIR%\3-Client-Download-Start.bat" "%CLIENT_PKG_PATH%\3-Client-Download-Start.bat" >nul 2>&1
)

:: ── Clean up stale old share from previous architecture ───────────────────────
powershell.exe -NoProfile -Command "if (Get-SmbShare -Name '%OLD_SHARE_NAME%' -ErrorAction SilentlyContinue) { Remove-SmbShare -Name '%OLD_SHARE_NAME%' -Force -ErrorAction SilentlyContinue; Write-Host '  [INFO] Removed stale old share: %OLD_SHARE_NAME%' -ForegroundColor Yellow } else { Write-Host '  [OK]   No stale old share found' -ForegroundColor Green }"

:: ── Check if our share is already running ─────────────────────────────────────
powershell.exe -NoProfile -Command "if (Get-SmbShare -Name '%SHARE_NAME%' -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
if %errorLevel% equ 0 (
    echo.
    echo  ====================================================================
    echo   SHARE ALREADY ACTIVE: \\%COMPUTERNAME%\%SHARE_NAME%
    echo   Opening shared folder in File Explorer...
    echo   To stop it run: 4-Host-Network-Stop.bat
    echo  ====================================================================
    echo.
    start "" explorer.exe "\\%COMPUTERNAME%"
    pause
    exit /b 0
)

:: ── Start LanmanServer and Network Discovery services ─────────────────────────
sc query LanmanServer | find "RUNNING" >nul 2>&1
if %errorLevel% neq 0 (
    echo  [INFO] Starting Windows File Sharing service...
    net start LanmanServer >nul 2>&1
    if !errorLevel! neq 0 (
        echo [ERROR] Could not start LanmanServer. Error: !errorLevel!
        pause
        exit /b 1
    )
)

:: Ensure Function Discovery services are active (makes PC visible in "Network")
powershell.exe -NoProfile -Command ^
    "Get-Service FDResPub, fdPHost -ErrorAction SilentlyContinue | ForEach-Object { if ($_.StartType -ne 'Automatic') { Set-Service -Name $_.Name -StartupType Automatic -ErrorAction SilentlyContinue }; if ($_.Status -ne 'Running') { Start-Service -Name $_.Name -ErrorAction SilentlyContinue } }" >nul 2>&1
echo  [OK]   Network Discovery services (FDResPub, fdPHost) active.

:: ── Discover host LAN IP (using PowerShell to avoid goto-in-for-block bug) ───
for /f "delims=" %%I in ('powershell.exe -NoProfile -Command "$ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.*' -and $_.PrefixOrigin -ne 'WellKnown' }; if ($ips) { ($ips | Select-Object -First 1).IPAddress } else { 'UNKNOWN' }"') do set "HOST_IP=%%I"

:: ── Read wallpaper port from HostConfig.json ──────────────────────────────────
set "HOST_PORT=8765"
set "HOST_CONFIG=%SCRIPT_DIR%\Host\HostConfig.json"
if exist "%HOST_CONFIG%" (
    for /f "delims=" %%P in ('powershell.exe -NoProfile -Command "try { $c = Get-Content -LiteralPath '%HOST_CONFIG%' -Raw | ConvertFrom-Json; $c.Server.Port } catch { '8765' }"') do set "HOST_PORT=%%P"
)

:: ── Create the share using PowerShell (more reliable than net share) ──────────
echo  [INFO] Creating share "%SHARE_NAME%" pointing to "%CLIENT_PKG_PATH%"...
powershell.exe -NoProfile -Command ^
    "try {" ^
    "  New-SmbShare -Name '%SHARE_NAME%' -Path '%CLIENT_PKG_PATH%' -ReadAccess 'Everyone' -FullAccess 'Administrators' -ErrorAction Stop | Out-Null;" ^
    "  Write-Host '  [OK]   Share created successfully via New-SmbShare' -ForegroundColor Green;" ^
    "  exit 0" ^
    "} catch {" ^
    "  Write-Host ('  [WARN] New-SmbShare failed: ' + $_.Exception.Message) -ForegroundColor Yellow;" ^
    "  exit 1" ^
    "}"
if %errorLevel% neq 0 (
    echo  [INFO] Trying net share fallback...
    net share "%SHARE_NAME%"="%CLIENT_PKG_PATH%" /grant:Everyone,READ /unlimited >nul 2>&1
    if !errorLevel! neq 0 (
        echo.
        echo [ERROR] Failed to create SMB share "%SHARE_NAME%".
        echo         Both New-SmbShare and net share failed.
        echo.
        pause
        exit /b 1
    )
    echo  [OK]   Share created via net share fallback.
)

:: ── Verify the share is accessible ───────────────────────────────────────────
powershell.exe -NoProfile -Command ^
    "Start-Sleep -Milliseconds 500;" ^
    "$share = Get-SmbShare -Name '%SHARE_NAME%' -ErrorAction SilentlyContinue;" ^
    "if ($share) { Write-Host '  [OK]   Share verified: ' $share.Path -ForegroundColor Green; exit 0 }" ^
    "else { Write-Host '  [WARN] Share verification failed' -ForegroundColor Red; exit 1 }"

:: ── Write _HOSTINFO.txt AFTER share confirmed ────────────────────────────────
set "HOSTINFO_FILE=%CLIENT_PKG_PATH%\_HOSTINFO.txt"
(
    echo HOST_IP=%HOST_IP%
    echo HOST_PORT=%HOST_PORT%
    echo HOST_NAME=%COMPUTERNAME%
    echo SHARE_NAME=%SHARE_NAME%
) > "%HOSTINFO_FILE%"
echo  [OK]   _HOSTINFO.txt written (IP: %HOST_IP%:%HOST_PORT%)

:: ── Firewall rules (port 445 + Network Discovery + File Sharing) ──────────────
netsh advfirewall firewall show rule name="LAN-WP-ClientPkg-Share" >nul 2>&1
if %errorLevel% neq 0 (
    netsh advfirewall firewall add rule name="LAN-WP-ClientPkg-Share" dir=in action=allow protocol=TCP localport=445 profile=private,domain >nul 2>&1
    echo  [OK]   Firewall rule added for port 445
) else (
    echo  [OK]   Firewall rule already exists for port 445
)

powershell.exe -NoProfile -Command ^
    "Set-NetFirewallRule -DisplayGroup 'Network Discovery' -Enabled True -Profile Private -ErrorAction SilentlyContinue;" ^
    "Set-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -Enabled True -Profile Private -ErrorAction SilentlyContinue" >nul 2>&1
echo  [OK]   Network Discovery & File Sharing firewall rules enabled.

:: ── Open the shared folder automatically in File Explorer ─────────────────────
echo  [INFO] Opening network share in File Explorer...
start "" explorer.exe "\\%COMPUTERNAME%"

echo.
echo  ====================================================================
echo   LAN DYNAMIC WALLPAPER  -  CLIENT PACKAGE SHARE ACTIVE
echo  ====================================================================
echo.
echo   Share Name  : %SHARE_NAME%
echo   Host IP     : %HOST_IP%
echo   Computer    : %COMPUTERNAME%
echo.
echo   NETWORK SHARE ADDRESS (Type this in File Explorer or Run):
echo     \\%HOST_IP%\%SHARE_NAME%
echo     or  \\%COMPUTERNAME%\%SHARE_NAME%
echo.
echo   NOTE ABOUT WINDOWS 11 "NETWORK" TAB:
echo     Windows 11 often delays showing PCs under the left "Network" sidebar.
echo     The instant, guaranteed way to access the folder on ANY PC is:
echo       1. Press Windows Key + R
echo       2. Paste: \\%HOST_IP%\%SHARE_NAME%
echo       3. Press Enter
echo.
echo   Or have students run 3-Client-Download-Start.bat — it auto-detects
echo   this share and downloads the files with ZERO manual configuration!
echo.
echo  ====================================================================
echo   Share stays open until you run: 4-Host-Network-Stop.bat
echo   (Wallpaper service runs independently via 2-Host-Wallpaper-Start.bat)
echo  ====================================================================
echo.
pause
