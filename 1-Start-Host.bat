@echo off
setlocal EnableDelayedExpansion
title LAN Dynamic Wallpaper - Host PC & Slideshow Controller
cd /d "%~dp0"

cls
echo ==============================================================================
echo  LAN DYNAMIC WALLPAPER SLIDESHOW - HOST MANAGER (Windows 11 / 10)
echo ==============================================================================
echo.

:: Automatically open the Wallpapers drop folder in Windows Explorer
start "" explorer.exe "%~dp0Wallpapers"

:: Dynamically detect active local IPv4 address and display upload folder
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1).IPAddress; " ^
  "$adapter = (Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1).Name; " ^
  "Write-Host ' ==============================================================================' -ForegroundColor Green; " ^
  "Write-Host '  📂 UPLOAD / DROP YOUR PHOTOS & VIDEOS HERE:' -ForegroundColor Yellow; " ^
  "Write-Host ('     ' + [System.IO.Path]::GetFullPath('%~dp0Wallpapers')) -ForegroundColor Cyan; " ^
  "Write-Host '  (Folder has been opened in Windows Explorer for immediate access)' -ForegroundColor Gray; " ^
  "Write-Host ' ------------------------------------------------------------------------------' -ForegroundColor DarkGray; " ^
  "Write-Host '  ⚡ Supported Formats : JPG, JPEG, PNG, BMP, GIF, WEBP, HEIC, TIFF, MP4, MOV, WMV' -ForegroundColor White; " ^
  "Write-Host '  ⏱️ Slideshow Timer   : 5 SECONDS (Changes Host & Client desktops every 5s)' -ForegroundColor Yellow; " ^
  "Write-Host '  📊 Maximum Capacity  : Up to 10,000 photos (100 MB per file limit)' -ForegroundColor White; " ^
  "Write-Host '  🌐 Host IPv4 Address : ' -NoNewline -ForegroundColor Gray; Write-Host $ip -ForegroundColor Cyan; " ^
  "Write-Host '  🔌 Active Interface  : ' -NoNewline -ForegroundColor Gray; Write-Host $adapter -ForegroundColor Yellow; " ^
  "Write-Host ' ==============================================================================' -ForegroundColor Green"

echo.
echo  ------------------------------------------------------------------------------
echo   Starting Host Server, Dynamic Watcher & Host Desktop Slideshow (5s)...
echo  ------------------------------------------------------------------------------
echo.

:: Launch Host Server in interactive console
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Host\Host.ps1"

if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] Host process exited with error code %ERRORLEVEL%.
    pause
)
exit /b %ERRORLEVEL%

