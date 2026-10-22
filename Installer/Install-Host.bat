@echo off
title LAN Dynamic Wallpaper - Host Installer
cd /d "%~dp0"

echo ==============================================================================
echo  LAN DYNAMIC WALLPAPER SLIDESHOW - HOST INSTALLER
echo ==============================================================================
echo  Requesting Administrator privileges and launching installer...
echo ==============================================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"\"%~dp0Install-Host.ps1\"\"' -Verb RunAs }"

echo Installer launched in elevated window.
