@echo off
setlocal EnableDelayedExpansion

:: ============================================================================
:: LAN Dynamic Wallpaper - Step 5: Stop Everything
:: ============================================================================
:: PURPOSE:  Stops ALL project services in one click:
::             1. Removes the SMB client-package share (LAN-WP-ClientPkg & stale shares)
::             2. Kills the wallpaper host process (Host.ps1 on port 8765)
::             3. Removes all project firewall rules
::
:: USE WHEN: You are done with the wallpaper session entirely and want to
::           clean up everything in one step.
::
:: DOES NOT:
::           - Affect other Windows shares or services
::           - Remove the Wallpapers\ folder or any image files
::           - Uninstall anything permanently - just stops running services
:: ============================================================================

:: ── Privilege check ──────────────────────────────────────────────────────────
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo  ====================================================================
    echo   LAN DYNAMIC WALLPAPER  -  STOP ALL SERVICES
    echo   Administrator privileges are required.
    echo   Relaunching with UAC elevation...
    echo  ====================================================================
    echo.
    powershell.exe -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b 0
)

:: ── Fix CWD after UAC elevation ──────────────────────────────────────────────
cd /d "%~dp0"

:: ── Resolve config ────────────────────────────────────────────────────────────
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "HOST_CONFIG=%SCRIPT_DIR%\Host\HostConfig.json"
set "HOST_PORT=8765"

if exist "%HOST_CONFIG%" (
    for /f "delims=" %%P in ('powershell.exe -NoProfile -Command "try { $c = Get-Content -LiteralPath '%HOST_CONFIG%' -Raw | ConvertFrom-Json; $c.Server.Port } catch { '8765' }"') do (
        set "HOST_PORT=%%P"
    )
)

echo.
echo  ====================================================================
echo   LAN DYNAMIC WALLPAPER  -  STOPPING ALL SERVICES
echo  ====================================================================
echo.

:: ============================================================
:: STEP 1  -  Stop SMB shares
:: ============================================================
echo  [1/3] Stopping SMB shares ("LAN-WP-ClientPkg" and any stale shares)...

powershell.exe -NoProfile -Command ^
    "$shares = @('LAN-WP-ClientPkg', 'LAN-Dynamic-Wallpaper');" ^
    "foreach ($s in $shares) {" ^
    "  if (Get-SmbShare -Name $s -ErrorAction SilentlyContinue) {" ^
    "    try {" ^
    "      Remove-SmbShare -Name $s -Force -ErrorAction Stop;" ^
    "      Write-Host ('        Share ' + $s + ' removed.') -ForegroundColor Green" ^
    "    } catch {" ^
    "      Write-Host ('        [WARN] Failed to remove share ' + $s + ': ' + $_.Exception.Message) -ForegroundColor Yellow" ^
    "    }" ^
    "  }" ^
    "}"

:: Fallback check via net share
net share "LAN-WP-ClientPkg" >nul 2>&1
if %errorLevel% equ 0 net share "LAN-WP-ClientPkg" /delete /y >nul 2>&1
net share "LAN-Dynamic-Wallpaper" >nul 2>&1
if %errorLevel% equ 0 net share "LAN-Dynamic-Wallpaper" /delete /y >nul 2>&1
echo         Share cleanup completed.

:: ============================================================
:: STEP 2  -  Kill the wallpaper host process (Host.ps1)
:: ============================================================
echo  [2/3] Stopping wallpaper host service (port %HOST_PORT%)...

:: Method A: kill by port owner
set "KILLED_BY_PORT=0"
for /f "tokens=5" %%P in ('netstat -ano 2^>nul ^| findstr ":%HOST_PORT% " ^| findstr "LISTENING"') do (
    if not "%%P"=="0" (
        taskkill /PID %%P /F >nul 2>&1
        if !errorLevel! equ 0 (
            echo         Stopped process PID %%P listening on port %HOST_PORT%.
            set "KILLED_BY_PORT=1"
        )
    )
)

:: Method B: also kill by command line pattern (catches background/hidden instances)
powershell.exe -NoProfile -Command ^
    "$procs = Get-CimInstance Win32_Process -Filter \"CommandLine LIKE '%%Host.ps1%%'\" -ErrorAction SilentlyContinue;" ^
    "if ($procs) { foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue; Write-Host ('        Stopped Host.ps1 process PID ' + $p.ProcessId + '.') } }" 2>nul

if %KILLED_BY_PORT% equ 0 (
    netstat -ano 2>nul | findstr ":%HOST_PORT% " | findstr "LISTENING" >nul 2>&1
    if !errorLevel! neq 0 (
        echo         Wallpaper service was not running on port %HOST_PORT%.
    )
)

:: Verify port is now free
powershell.exe -NoProfile -Command "Start-Sleep -Milliseconds 500"
netstat -ano 2>nul | findstr ":%HOST_PORT% " | findstr "LISTENING" >nul 2>&1
if %errorLevel% neq 0 (
    echo         Port %HOST_PORT% is now free.
) else (
    echo  [WARN] Port %HOST_PORT% still in use. Close any remaining host console windows.
)

:: ============================================================
:: STEP 3  -  Remove all project firewall rules
:: ============================================================
echo  [3/3] Removing project firewall rules...
set "RULES_REMOVED=0"

for %%R in ("LAN-WP-ClientPkg-Share" "LAN-WP-WallpaperService" "LAN-WP-UdpDiscovery") do (
    netsh advfirewall firewall show rule name=%%R >nul 2>&1
    if !errorLevel! equ 0 (
        netsh advfirewall firewall delete rule name=%%R >nul 2>&1
        echo         Removed rule: %%~R
        set /a RULES_REMOVED+=1
    )
)
if %RULES_REMOVED% equ 0 (
    echo         No project firewall rules were present.
)

:: ============================================================
:: SUMMARY
:: ============================================================
echo.
echo  ====================================================================
echo   ALL LAN DYNAMIC WALLPAPER SERVICES STOPPED.
echo.
echo   What was cleaned up:
echo     - SMB share   : LAN-WP-ClientPkg & stale shares
echo     - HTTP service: port %HOST_PORT%  (wallpaper delivery)
echo     - Firewall    : all LAN-WP-* rules removed
echo.
echo   What was NOT changed:
echo     - Wallpapers\ folder and your image files
echo     - Client installations on student PCs
echo     - Other Windows shares and services
echo.
echo   To start again:
echo     1-Host-Network-Start.bat   (open share)
echo     2-Host-Wallpaper-Start.bat (start wallpaper service)
echo  ====================================================================
echo.
pause
