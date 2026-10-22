@echo off
setlocal EnableDelayedExpansion
title LAN Dynamic Wallpaper - Master Verification Test Harness
cd /d "%~dp0"

cls
echo ==============================================================================
echo  LAN DYNAMIC WALLPAPER - AUTOMATED TEST SUITE HARNESS
echo  Executing All 5 Enterprise Verification Suites (Pure PowerShell Engine)
echo ==============================================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Tests\Run-All-Tests.ps1"
set TEST_STATUS=%ERRORLEVEL%

echo.
if %TEST_STATUS% equ 0 (
    echo ==============================================================================
    echo  VERIFICATION RESULT: ALL TEST SUITES PASSED CLEANLY [100%% SUCCESS]
    echo ==============================================================================
) else (
    echo ==============================================================================
    echo  VERIFICATION RESULT: SOME TESTS FAILED (Error Code %TEST_STATUS%)
    echo ==============================================================================
)
echo.
pause
exit /b %TEST_STATUS%
