@echo off
setlocal EnableDelayedExpansion

:: ============================================================================
:: LAN Dynamic Wallpaper - Step 3: Client Download and Start
:: ============================================================================
:: PURPOSE:  Download the wallpaper client package from the host share and
::           start the wallpaper agent. NO manual configuration needed.
::
:: HOST AUTO-DISCOVERY (tried in this order, fully automatic):
::   Method 1 - UNC launch path     : Run directly from \\HOST\LAN-WP-ClientPkg\
::   Method 2 - UDP broadcast (8766): Host wallpaper service broadcasts IP
::   Method 3 - Subnet & ARP probe  : Checks active LAN IPs for the share
::   Method 4 - Net view fallback   : Legacy workgroup network enumeration
::   Method 5 - Interactive prompt  : Friendly fallback if all auto-methods fail
::
:: RUNTIME: cmd.exe + powershell.exe only (standard Windows components)
:: ADMIN:   NOT required - runs as standard user
:: ============================================================================

:: ── Destination paths ─────────────────────────────────────────────────────────
set "DEST_DIR=%USERPROFILE%\Downloads\LAN-Dynamic-Wallpaper"
set "SHARE_NAME=LAN-WP-ClientPkg"
set "HOST_PORT=8765"

set "HOST_IP="
set "DISCOVERY_METHOD="

echo.
echo  ====================================================================
echo   LAN DYNAMIC WALLPAPER  -  CLIENT SETUP (Zero Manual Config)
echo  ====================================================================
echo.
echo  Discovering wallpaper host automatically...

:: ============================================================
:: METHOD 1: Detect from UNC launch path
:: If this file was run from \\HOST\Share\... %~dp0 is a UNC path
:: ============================================================
set "LAUNCHER_DIR=%~dp0"
if "%LAUNCHER_DIR:~-1%"=="\" set "LAUNCHER_DIR=%LAUNCHER_DIR:~0,-1%"

if "%LAUNCHER_DIR:~0,2%"=="\\" (
    echo  [Method 1] Checking UNC launch path...
    set "UNC_TEMP=%LAUNCHER_DIR:~2%"
    for /f "tokens=1 delims=\" %%S in ("!UNC_TEMP!") do (
        set "HOST_NAME_OR_IP=%%S"
    )
    if defined HOST_NAME_OR_IP (
        for /f "tokens=3" %%I in ('ping -n 1 -4 "!HOST_NAME_OR_IP!" 2^>nul ^| findstr /C:"Reply from"') do (
            set "CANDIDATE=%%I"
            set "CANDIDATE=!CANDIDATE::=!"
            echo !CANDIDATE! | findstr /R "^[0-9][0-9]*\." >nul 2>&1
            if !errorLevel! equ 0 (
                if not defined HOST_IP (
                    set "HOST_IP=!CANDIDATE!"
                    set "DISCOVERY_METHOD=UNC launch path (\\!HOST_NAME_OR_IP!\%SHARE_NAME%)"
                )
            )
        )
        if not defined HOST_IP (
            set "HOST_IP=!HOST_NAME_OR_IP!"
            set "DISCOVERY_METHOD=UNC launch path (\\!HOST_NAME_OR_IP!\%SHARE_NAME%)"
        )
        if defined HOST_IP goto :discovery_done
    )
)

:: ============================================================
:: METHOD 2: Fast UDP broadcast discovery (port 8766)
:: Responded to by Host.ps1 when 2-Host-Wallpaper-Start.bat runs
:: ============================================================
if not defined HOST_IP (
    echo  [Method 2] Probing via UDP broadcast (port 8766)...
    for /f "tokens=1,2 delims=," %%A in ('powershell.exe -NoProfile -Command ^
        "$udp = New-Object System.Net.Sockets.UdpClient; $udp.EnableBroadcast = $true; $udp.Client.ReceiveTimeout = 2500; try { $req = [System.Text.Encoding]::UTF8.GetBytes('LAN_WALLPAPER_DISCOVER_REQ'); $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Broadcast, 8766); [void]$udp.Send($req, $req.Length, $ep); $rep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0); $data = $udp.Receive([ref]$rep); $json = [System.Text.Encoding]::UTF8.GetString($data) | ConvertFrom-Json; if ($json.ip) { Write-Output ($json.ip + ',' + $json.port) } } catch {} finally { $udp.Close() }" 2^>nul') do (
        set "HOST_IP=%%A"
        if not "%%B"=="" set "HOST_PORT=%%B"
        set "DISCOVERY_METHOD=UDP broadcast discovery (port 8766)"
        goto :discovery_done
    )
)

:: ============================================================
:: METHOD 3: ARP & LAN Neighbor probe for share \\IP\LAN-WP-ClientPkg
:: ============================================================
if not defined HOST_IP (
    echo  [Method 3] Probing LAN neighbors for share "%SHARE_NAME%"...
    for /f "tokens=1,2 delims=," %%A in ('powershell.exe -NoProfile -Command ^
        "$foundIp = ''; $foundPort = '8765';" ^
        "$neighbors = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -notlike '224.*' -and $_.IPAddress -notlike '255.*' } | Select-Object -ExpandProperty IPAddress -Unique;" ^
        "foreach ($ip in $neighbors) {" ^
        "  $infoPath = '\\' + $ip + '\%SHARE_NAME%\_HOSTINFO.txt';" ^
        "  if (Test-Path -LiteralPath $infoPath -ErrorAction SilentlyContinue) {" ^
        "    $foundIp = $ip;" ^
        "    try {" ^
        "      Get-Content -LiteralPath $infoPath -ErrorAction SilentlyContinue | ForEach-Object {" ^
        "        if ($_ -match '^HOST_PORT=(.+)$') { $foundPort = $matches[1].Trim() }" ^
        "      }" ^
        "    } catch {}" ^
        "    break;" ^
        "  }" ^
        "}" ^
        "if ($foundIp) { Write-Output ($foundIp + ',' + $foundPort) }" 2^>nul') do (
        set "HOST_IP=%%A"
        if not "%%B"=="" set "HOST_PORT=%%B"
        set "DISCOVERY_METHOD=LAN neighbor probe (\\%%A\%SHARE_NAME%)"
        goto :discovery_done
    )
)

:: ============================================================
:: METHOD 4: Net view scan - legacy workgroup enumeration
:: ============================================================
if not defined HOST_IP (
    echo  [Method 4] Scanning workgroup for "%SHARE_NAME%"...
    for /f "skip=3 tokens=1" %%C in ('net view 2^>nul ^| findstr "^\\\\"') do (
        net view "%%C" 2>nul | findstr /I "%SHARE_NAME%" >nul 2>&1
        if !errorLevel! equ 0 (
            set "RAW_NAME=%%C"
            set "RAW_NAME=!RAW_NAME:~2!"
            for /f "tokens=3" %%I in ('ping -n 1 -4 "!RAW_NAME!" 2^>nul ^| findstr /C:"Reply from"') do (
                set "CAND=%%I"
                set "CAND=!CAND::=!"
                echo !CAND! | findstr /R "^[0-9][0-9]*\." >nul 2>&1
                if !errorLevel! equ 0 ( set "HOST_IP=!CAND!" )
            )
            if not defined HOST_IP set "HOST_IP=!RAW_NAME!"
            set "DISCOVERY_METHOD=Net view scan (found %%C\%SHARE_NAME%)"
            goto :discovery_done
        )
    )
)

:: ============================================================
:: METHOD 5: Interactive fallback prompt
:: ============================================================
if not defined HOST_IP (
    echo.
    echo  --------------------------------------------------------------------
    echo   Automatic discovery did not detect the host computer.
    echo  --------------------------------------------------------------------
    echo   Please verify on the HOST computer:
    echo     1. 1-Host-Network-Start.bat is running (creates the share)
    echo     2. 2-Host-Wallpaper-Start.bat is running (wallpaper service)
    echo     3. Both computers are connected to the same Wi-Fi / LAN
    echo.
    set /p "USER_HOST_INPUT=  Enter Host IP or Hostname (or press Enter to exit): "
    if defined USER_HOST_INPUT (
        set "USER_HOST_INPUT=!USER_HOST_INPUT: =!"
        if not "!USER_HOST_INPUT!"=="" (
            set "HOST_IP=!USER_HOST_INPUT!"
            set "DISCOVERY_METHOD=User manual input"
        )
    )
)

:discovery_done

:: ── Fail if nothing found ─────────────────────────────────────────────────────
if not defined HOST_IP (
    echo.
    echo [ERROR] No host specified. Exiting setup.
    echo.
    pause
    exit /b 1
)

set "SHARE_UNC=\\%HOST_IP%\%SHARE_NAME%"

echo.
echo   Host IP     : %HOST_IP%
echo   Found via   : %DISCOVERY_METHOD%
echo   Share       : %SHARE_UNC%
echo   Destination : %DEST_DIR%
echo.

:: ── Step 1: Verify share is reachable ────────────────────────────────────────
echo  [1/6] Verifying share access (%SHARE_UNC%)...
dir "%SHARE_UNC%" >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo [ERROR] Cannot access share: %SHARE_UNC%
    echo         The share may have been stopped or blocked by firewall.
    echo         Ask host operator to ensure 1-Host-Network-Start.bat is running.
    echo.
    pause
    exit /b 1
)
echo         Share accessible.

:: ── Try to read port from _HOSTINFO.txt if not already set ───────────────────
if exist "%SHARE_UNC%\_HOSTINFO.txt" (
    for /f "tokens=1,2 delims==" %%K in ('type "%SHARE_UNC%\_HOSTINFO.txt" 2^>nul') do (
        if "%%K"=="HOST_PORT" set "HOST_PORT=%%L"
    )
)

:: ── Step 2: Verify required files ────────────────────────────────────────────
echo  [2/6] Checking required files on share...
set "MISSING=0"
for %%F in (Client.ps1 Wallpaper.ps1 ClientConfig.json) do (
    if not exist "%SHARE_UNC%\%%F" (
        echo  [WARN] Missing: %%F
        set /a MISSING+=1
    )
)
if %MISSING% gtr 0 (
    echo [ERROR] %MISSING% required file(s) missing from share.
    pause
    exit /b 1
)
echo         All required files present on share.

:: ── Step 3: Create directories ───────────────────────────────────────────────
echo  [3/6] Preparing destination directories...
if not exist "%DEST_DIR%" mkdir "%DEST_DIR%" >nul 2>&1
if not exist "%DEST_DIR%\Cache" mkdir "%DEST_DIR%\Cache" >nul 2>&1
if not exist "%DEST_DIR%\Logs"  mkdir "%DEST_DIR%\Logs"  >nul 2>&1
set "TEMP_DIR=%TEMP%\lan-wp-download-%RANDOM%"
mkdir "%TEMP_DIR%" >nul 2>&1

:: ── Step 4: Download and verify ──────────────────────────────────────────────
echo  [4/6] Downloading client files...

set "SAVED_CLIENT_ID="
set "SAVED_AUTH_SECRET="
if exist "%DEST_DIR%\ClientConfig.json" (
    for /f "delims=" %%L in ('powershell.exe -NoProfile -Command ^
        "try { $c = Get-Content -LiteralPath '%DEST_DIR%\ClientConfig.json' -Raw | ConvertFrom-Json; Write-Output ('ID:' + $c.Security.ClientId); Write-Output ('TOKEN:' + $c.Security.AuthSecret) } catch { Write-Output 'ID:'; Write-Output 'TOKEN:' }" 2^>nul') do (
        set "LINE=%%L"
        if "!LINE:~0,3!"=="ID:"    set "SAVED_CLIENT_ID=!LINE:~3!"
        if "!LINE:~0,6!"=="TOKEN:" set "SAVED_AUTH_SECRET=!LINE:~6!"
    )
    if defined SAVED_CLIENT_ID echo         Preserving client identity: !SAVED_CLIENT_ID!
)

set "DOWNLOAD_ERRORS=0"
for %%F in (Client.ps1 Wallpaper.ps1) do (
    copy /y "%SHARE_UNC%\%%F" "%TEMP_DIR%\%%F" >nul 2>&1
    if !errorLevel! neq 0 (
        echo  [WARN] Failed to download %%F
        set /a DOWNLOAD_ERRORS+=1
    ) else (
        for %%S in ("%TEMP_DIR%\%%F") do (
            if %%~zS equ 0 (
                echo  [WARN] %%F is zero bytes - rejected
                del /f /q "%TEMP_DIR%\%%F" >nul 2>&1
                set /a DOWNLOAD_ERRORS+=1
            ) else (
                echo         %%F: %%~zS bytes OK
            )
        )
    )
)

copy /y "%SHARE_UNC%\ClientConfig.json" "%TEMP_DIR%\ClientConfig.json" >nul 2>&1

if %DOWNLOAD_ERRORS% gtr 0 (
    if not exist "%DEST_DIR%\Client.ps1" (
        echo [ERROR] Download failed and no prior install found.
        if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%" >nul 2>&1
        pause
        exit /b 1
    )
    echo  [WARN] Download errors - keeping existing installation.
    goto :start_agent
)

:: ── Step 5: Deploy ────────────────────────────────────────────────────────────
echo  [5/6] Installing files...

for %%F in (Client.ps1 Wallpaper.ps1) do (
    if exist "%TEMP_DIR%\%%F" (
        move /y "%TEMP_DIR%\%%F" "%DEST_DIR%\%%F" >nul 2>&1
        if !errorLevel! neq 0 (
            echo  [WARN] Could not replace %%F ^(may be in use^).
        ) else (
            echo         Installed %%F
        )
    )
)

:: ClientConfig: inject host IP/port; create if new, or update if blank
if not exist "%DEST_DIR%\ClientConfig.json" (
    if exist "%TEMP_DIR%\ClientConfig.json" (
        powershell.exe -NoProfile -Command ^
            "try { $c = Get-Content -LiteralPath '%TEMP_DIR%\ClientConfig.json' -Raw | ConvertFrom-Json; $c.Connection.HostAddress = '%HOST_IP%'; $c.Connection.HostPort = %HOST_PORT%; [System.IO.File]::WriteAllText('%DEST_DIR%\ClientConfig.json', ($c | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8); Write-Host '        Created ClientConfig.json with host %HOST_IP%:%HOST_PORT%' } catch { Write-Host '[WARN] ' + $_.Exception.Message }" 2>nul
    )
) else (
    powershell.exe -NoProfile -Command ^
        "try { $c = Get-Content -LiteralPath '%DEST_DIR%\ClientConfig.json' -Raw | ConvertFrom-Json; $changed = $false; if ([string]::IsNullOrWhiteSpace($c.Connection.HostAddress) -or $c.Connection.HostAddress -eq 'UNKNOWN') { $c.Connection.HostAddress = '%HOST_IP%'; $c.Connection.HostPort = %HOST_PORT%; $changed = $true }; if ($changed) { [System.IO.File]::WriteAllText('%DEST_DIR%\ClientConfig.json', ($c | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8); Write-Host '        Updated HostAddress to %HOST_IP%:%HOST_PORT%' } else { Write-Host '        Existing ClientConfig.json retained (identity preserved)' } } catch { Write-Host '[WARN] ' + $_.Exception.Message }" 2>nul
)

:: Restore preserved ClientId and AuthSecret
if defined SAVED_CLIENT_ID (
    if not "%SAVED_CLIENT_ID%"=="" (
        powershell.exe -NoProfile -Command ^
            "try { $c = Get-Content -LiteralPath '%DEST_DIR%\ClientConfig.json' -Raw | ConvertFrom-Json; $c.Security.ClientId = '%SAVED_CLIENT_ID%'; $c.Security.AuthSecret = '%SAVED_AUTH_SECRET%'; [System.IO.File]::WriteAllText('%DEST_DIR%\ClientConfig.json', ($c | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8) } catch {}" 2>nul
        echo         Identity restored: %SAVED_CLIENT_ID%
    )
)

if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%" >nul 2>&1

:start_agent
:: ── Step 6: Start wallpaper agent ────────────────────────────────────────────
echo  [6/6] Starting wallpaper agent...

set "CLIENT_SCRIPT=%DEST_DIR%\Client.ps1"
if not exist "%CLIENT_SCRIPT%" (
    echo [ERROR] Client.ps1 not found. Download may have failed.
    pause
    exit /b 1
)

:: Check for already-running agent via mutex (no duplicates)
set "AGENT_RUNNING=0"
powershell.exe -NoProfile -Command ^
    "$sid = try { [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { [System.Environment]::UserName }; $name = 'Local\LAN_Dynamic_Wallpaper_Client_' + $sid; try { $m = New-Object System.Threading.Mutex($false, $name); $acquired = $m.WaitOne(0); if ($acquired) { $m.ReleaseMutex() }; if ($acquired) { exit 1 } else { exit 0 } } catch { exit 0 }" >nul 2>&1
if %errorLevel% equ 0 (
    echo         Wallpaper agent is already running. No duplicate launched.
    set "AGENT_RUNNING=1"
) else (
    echo         Launching wallpaper agent...
    start "" /B powershell.exe -NoProfile -WindowStyle Normal -ExecutionPolicy Bypass -File "%CLIENT_SCRIPT%"
    timeout /t 3 /nobreak >nul 2>&1
)

:: Verify connection
echo.
echo  Verifying connection to wallpaper service...
powershell.exe -NoProfile -Command ^
    "try { $r = Invoke-RestMethod -Uri 'http://%HOST_IP%:%HOST_PORT%/api/v1/health' -TimeoutSec 5; if ($r.status -eq 'ok') { Write-Host '  [OK] Connected to wallpaper host. Images: ' + $r.totalImages -ForegroundColor Green } else { Write-Host '  [WARN] Host responded but status: ' + $r.status -ForegroundColor Yellow } } catch { Write-Host '  [INFO] Wallpaper service not yet reachable at http://%HOST_IP%:%HOST_PORT%' -ForegroundColor Yellow; Write-Host '         Ensure 2-Host-Wallpaper-Start.bat is running on the host.' -ForegroundColor Yellow }" 2>nul

echo.
if %AGENT_RUNNING% equ 0 (
    echo  ====================================================================
    echo   SUCCESS: Client installed to:
    echo     %DEST_DIR%
    echo   Wallpaper agent started. Syncing from http://%HOST_IP%:%HOST_PORT%
    echo  ====================================================================
) else (
    echo  ====================================================================
    echo   INFO: Files updated. Wallpaper agent already running.
    echo  ====================================================================
)
echo.
pause
