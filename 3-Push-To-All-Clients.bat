@echo off
setlocal EnableDelayedExpansion

:: ============================================================================
:: LAN Dynamic Wallpaper - Remote Fleet Push Launcher
:: Pushes the wallpaper client to all 80 lab PCs from the Host in 15 seconds
:: ============================================================================

set "DIR=%~dp0"
set "DEPLOY_SCRIPT=%DIR%Tools\Deploy-Fleet-Remote.ps1"

if not exist "%DEPLOY_SCRIPT%" (
    echo [ERROR] Tools\Deploy-Fleet-Remote.ps1 not found in %DIR%
    pause
    exit /b 1
)

echo.
echo ====================================================================
echo  LAN DYNAMIC WALLPAPER - 80-PC FLEET REMOTE PUSH
echo ====================================================================
echo  This tool sends the wallpaper client to all computers on your LAN
echo  simultaneously without having to walk to each desk.
echo ====================================================================
echo.

set /p IPRANGE="Enter Lab IP range (e.g. 192.168.1.1-100) or press Enter to auto-sweep: "

if "%IPRANGE%"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { $ip = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' | ForEach-Object { Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 } | Where-Object { $_.IPAddress -notlike '127.*' } | Select-Object -First 1).IPAddress; $sub = $ip.Substring(0, $ip.LastIndexOf('.')); & '%DEPLOY_SCRIPT%' -IpRange \"$sub.1-100\" }"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DEPLOY_SCRIPT%" -IpRange "%IPRANGE%"
)

echo.
echo ====================================================================
echo  Push operation finished. Check the summary above.
echo ====================================================================
pause
