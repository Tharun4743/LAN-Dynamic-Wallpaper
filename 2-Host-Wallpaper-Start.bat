@echo off
setlocal EnableDelayedExpansion

:: ============================================================================
:: LAN Dynamic Wallpaper - Step 2: Start the Wallpaper Host Service
:: ============================================================================
:: PURPOSE:  Starts Host\Host.ps1 which provides:
::             - HTTP wallpaper delivery on port 8765
::             - UDP discovery beacon on port 8766
::             - Client registration, manifest, and heartbeat APIs
::           This service is INDEPENDENT of the SMB client-package share.
::           It keeps running when 4-Host-Network-Stop.bat is called.
::
:: DUPLICATE PREVENTION:
::   If Host.ps1 is already running (detected via TCP port probe and mutex),
::   this script reports the running instance and exits cleanly.
::
:: PREREQUISITES:
::   - Must run as Administrator (for HTTP listener binding on port 8765)
:: ============================================================================

:: ── Privilege check ──────────────────────────────────────────────────────────
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo  ====================================================================
    echo   LAN DYNAMIC WALLPAPER  -  HOST WALLPAPER SERVICE
    echo   Administrator privileges are required to bind the HTTP listener.
    echo   Relaunching with UAC elevation...
    echo  ====================================================================
    echo.
    powershell.exe -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b 0
)

:: ── Fix CWD after UAC elevation ──────────────────────────────────────────────
cd /d "%~dp0"

:: ── Resolve paths ─────────────────────────────────────────────────────────────
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "HOST_SCRIPT=%SCRIPT_DIR%\Host\Host.ps1"
set "HOST_CONFIG=%SCRIPT_DIR%\Host\HostConfig.json"

:: ── Sanity checks ─────────────────────────────────────────────────────────────
if not exist "%HOST_SCRIPT%" (
    echo.
    echo [ERROR] Host\Host.ps1 not found.
    echo         Expected location: %HOST_SCRIPT%
    echo         Please run this batch file from the LAN-Dynamic-Wallpaper project root.
    echo.
    pause
    exit /b 1
)

if not exist "%HOST_CONFIG%" (
    echo.
    echo [ERROR] Host\HostConfig.json not found.
    echo         Expected location: %HOST_CONFIG%
    echo.
    pause
    exit /b 1
)

:: ── Read configured ports from HostConfig.json ────────────────────────────────
set "HOST_PORT=8765"
set "DISC_PORT=8766"
for /f "delims=" %%P in ('powershell.exe -NoProfile -Command "try { $c = Get-Content -LiteralPath '%HOST_CONFIG%' -Raw | ConvertFrom-Json; $c.Server.Port } catch { '8765' }"') do set "HOST_PORT=%%P"
for /f "delims=" %%D in ('powershell.exe -NoProfile -Command "try { $c = Get-Content -LiteralPath '%HOST_CONFIG%' -Raw | ConvertFrom-Json; $c.Server.DiscoveryPort } catch { '8766' }"') do set "DISC_PORT=%%D"

:: ── Duplicate-instance detection ─────────────────────────────────────────────
powershell.exe -NoProfile -Command ^
    "try { $t = New-Object System.Net.Sockets.TcpClient; $t.Connect('127.0.0.1', %HOST_PORT%); $t.Close(); exit 0 } catch { exit 1 }" >nul 2>&1
if %errorLevel% equ 0 (
    echo.
    echo  ====================================================================
    echo   LAN DYNAMIC WALLPAPER  -  HOST ALREADY RUNNING
    echo  ====================================================================
    echo.
    echo   The wallpaper host service is already listening on port %HOST_PORT%.
    echo   A duplicate instance will NOT be launched.
    echo.
    powershell.exe -NoProfile -Command ^
        "$r = try { Invoke-RestMethod -Uri 'http://127.0.0.1:%HOST_PORT%/api/v1/health' -TimeoutSec 3 } catch { $null }; if ($r) { Write-Host '  Host IP     : ' + $r.hostIp -ForegroundColor Cyan; Write-Host '  Uptime (s)  : ' + $r.uptimeSeconds -ForegroundColor Cyan; Write-Host '  Images      : ' + $r.totalImages -ForegroundColor Cyan }"
    echo.
    echo   Wallpaper service URL: http://127.0.0.1:%HOST_PORT%
    echo.
    pause
    exit /b 0
)

:: ── Open the wallpaper service firewall rules ────────────────────────────────
netsh advfirewall firewall show rule name="LAN-WP-WallpaperService" >nul 2>&1
if %errorLevel% neq 0 (
    echo  [INFO] Adding firewall rule for wallpaper HTTP service on TCP %HOST_PORT%...
    netsh advfirewall firewall add rule name="LAN-WP-WallpaperService" dir=in action=allow protocol=TCP localport=%HOST_PORT% profile=private,domain >nul 2>&1
)

netsh advfirewall firewall show rule name="LAN-WP-UdpDiscovery" >nul 2>&1
if %errorLevel% neq 0 (
    echo  [INFO] Adding firewall rule for UDP discovery beacon on port %DISC_PORT%...
    netsh advfirewall firewall add rule name="LAN-WP-UdpDiscovery" dir=in action=allow protocol=UDP localport=%DISC_PORT% profile=private,domain >nul 2>&1
)

:: ── Discover host LAN IP for display ─────────────────────────────────────────
for /f "delims=" %%I in ('powershell.exe -NoProfile -Command "$ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.*' -and $_.PrefixOrigin -ne 'WellKnown' }; if ($ips) { ($ips | Select-Object -First 1).IPAddress } else { '127.0.0.1' }"') do set "HOST_IP=%%I"

echo.
echo  ====================================================================
echo   LAN DYNAMIC WALLPAPER  -  STARTING WALLPAPER HOST SERVICE
echo  ====================================================================
echo.
echo   Host LAN IP     : %HOST_IP%
echo   Wallpaper HTTP  : http://%HOST_IP%:%HOST_PORT%
echo   UDP Discovery   : port %DISC_PORT%
echo   Config          : %HOST_CONFIG%
echo.
echo   Clients use HTTP for wallpaper updates - NO SMB share required.
echo   To distribute the client package, run:
echo     1-Host-Network-Start.bat   (creates client-package share)
echo.
echo  ====================================================================
echo   The host server will run in this window.
echo   Close this window or run 5-Stop-All.bat to stop the service.
echo  ====================================================================
echo.

:: ── Launch Host.ps1 ──────────────────────────────────────────────────────────
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HOST_SCRIPT%"

if %errorLevel% neq 0 (
    echo.
    echo [ERROR] Wallpaper host service exited with error code %errorLevel%.
    echo.
    echo   Possible causes:
    echo     - Port %HOST_PORT% is already in use by another process
    echo     - Windows URL ACL is missing for http://+:%HOST_PORT%/
    echo     - HostConfig.json contains invalid JSON
    echo.
    pause
    exit /b %errorLevel%
)
