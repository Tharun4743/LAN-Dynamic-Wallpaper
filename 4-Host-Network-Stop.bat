@echo off
setlocal EnableDelayedExpansion

:: ============================================================================
:: LAN Dynamic Wallpaper - Step 4: Stop Client-Package Network Share
:: ============================================================================
:: PURPOSE:  Removes ONLY the "LAN-WP-ClientPkg" SMB share (and any stale
::           "LAN-Dynamic-Wallpaper" share) and its firewall rule.
::
:: SAFE TO RUN:
::   - Manually at any time
::   - Multiple times (idempotent - safe if share already gone)
::
:: DOES NOT:
::   - Stop Host.ps1 or the HTTP wallpaper service on port 8765
::   - Remove the LanmanServer service or disable SMB globally
::   - Modify unrelated shares or firewall rules
::   - Disconnect the network adapter
::   - Touch the LAN-WP-WallpaperService or LAN-WP-UdpDiscovery rules
:: ============================================================================

:: ── Privilege check ──────────────────────────────────────────────────────────
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo  ====================================================================
    echo   LAN DYNAMIC WALLPAPER  -  STOP CLIENT-PACKAGE SHARE
    echo   Administrator privileges are required to remove an SMB share.
    echo   Relaunching with UAC elevation...
    echo  ====================================================================
    echo.
    powershell.exe -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b 0
)

:: ── Fix CWD after UAC elevation ──────────────────────────────────────────────
cd /d "%~dp0"

set "SHARE_NAME=LAN-WP-ClientPkg"
set "OLD_SHARE_NAME=LAN-Dynamic-Wallpaper"
set "FIREWALL_RULE=LAN-WP-ClientPkg-Share"

echo.
echo  ====================================================================
echo   LAN DYNAMIC WALLPAPER  -  STOPPING CLIENT PACKAGE SHARE
echo  ====================================================================
echo.

:: ── Step 1: Remove the SMB share (and any stale old shares) ─────────────────
echo  [1/2] Removing SMB shares...

powershell.exe -NoProfile -Command ^
    "$shares = @('%SHARE_NAME%', '%OLD_SHARE_NAME%');" ^
    "foreach ($s in $shares) {" ^
    "  if (Get-SmbShare -Name $s -ErrorAction SilentlyContinue) {" ^
    "    try {" ^
    "      Remove-SmbShare -Name $s -Force -ErrorAction Stop;" ^
    "      Write-Host ('        Share ' + $s + ' removed successfully.') -ForegroundColor Green" ^
    "    } catch {" ^
    "      Write-Host ('        [WARN] Failed to remove share ' + $s + ': ' + $_.Exception.Message) -ForegroundColor Yellow" ^
    "    }" ^
    "  } else {" ^
    "    Write-Host ('        Share ' + $s + ' was not active.') -ForegroundColor Gray" ^
    "  }" ^
    "}"

:: Fallback check via net share
net share "%SHARE_NAME%" >nul 2>&1
if %errorLevel% equ 0 (
    net share "%SHARE_NAME%" /delete /y >nul 2>&1
)
net share "%OLD_SHARE_NAME%" >nul 2>&1
if %errorLevel% equ 0 (
    net share "%OLD_SHARE_NAME%" /delete /y >nul 2>&1
)

:: ── Step 2: Remove the project-scoped firewall rule ──────────────────────────
echo  [2/2] Removing firewall rule "%FIREWALL_RULE%"...
netsh advfirewall firewall show rule name="%FIREWALL_RULE%" >nul 2>&1
if %errorLevel% equ 0 (
    netsh advfirewall firewall delete rule name="%FIREWALL_RULE%" >nul 2>&1
    if !errorLevel! equ 0 (
        echo         Firewall rule "%FIREWALL_RULE%" removed.
    ) else (
        echo  [WARN] Could not remove firewall rule "%FIREWALL_RULE%" (error !errorLevel!).
    )
) else (
    echo         Firewall rule "%FIREWALL_RULE%" was not present. Nothing to remove.
)

:: ── Verify wallpaper service is still running ─────────────────────────────────
echo.
echo  Verifying wallpaper HTTP service is still running...

set "HOST_PORT=8765"
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "HOST_CONFIG=%SCRIPT_DIR%\Host\HostConfig.json"

if exist "%HOST_CONFIG%" (
    for /f "delims=" %%P in ('powershell.exe -NoProfile -Command "try { $c = Get-Content -LiteralPath '%HOST_CONFIG%' -Raw | ConvertFrom-Json; $c.Server.Port } catch { '8765' }"') do (
        set "HOST_PORT=%%P"
    )
)

powershell.exe -NoProfile -Command ^
    "try { $t = New-Object System.Net.Sockets.TcpClient; $t.Connect('127.0.0.1', %HOST_PORT%); $t.Close(); Write-Host '  [OK]  Wallpaper service still listening on TCP port %HOST_PORT% - unaffected.' -ForegroundColor Green } catch { Write-Host '  [INFO] Wallpaper service not detected on port %HOST_PORT%. It may not be started yet.' -ForegroundColor Yellow }"

echo.
echo  ====================================================================
echo   RESULT: Client package share is STOPPED.
echo.
echo   Unaffected by this action:
echo     - Host.ps1 wallpaper service (port %HOST_PORT%)
echo     - LAN connection and network adapter
echo     - All other Windows shares
echo     - LAN-WP-WallpaperService and LAN-WP-UdpDiscovery firewall rules
echo.
echo   To re-open the share:  1-Host-Network-Start.bat
echo  ====================================================================
echo.
pause
