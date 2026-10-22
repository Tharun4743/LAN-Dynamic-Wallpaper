# ==============================================================================
# Tests/Run-All-Tests.ps1
# Master Automated Test Harness for LAN Dynamic Wallpaper Slideshow System
# Pure Windows PowerShell 5.1+ - Executes all suites and generates audit matrix
# ==============================================================================

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " LAN DYNAMIC WALLPAPER - MASTER VERIFICATION HARNESS" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " Environment: Windows $([System.Environment]::OSVersion.Version)" -ForegroundColor Gray
Write-Host " PowerShell : $($PSVersionTable.PSVersion)" -ForegroundColor Gray
Write-Host " Test Dir   : $testRoot" -ForegroundColor Gray
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

$suites = @(
    @{ Name = "Publisher Engine (Validation & Atomic Sync)"; File = "Test-Publisher.ps1" },
    @{ Name = "Client Engine (Win32 API & Local Cache)";     File = "Test-Client.ps1" },
    @{ Name = "Host Server (Routes, Tokens & RBAC)";         File = "Test-Host.ps1" },
    @{ Name = "Security Penetration (Traversal & Bypass)";   File = "Test-Security.ps1" },
    @{ Name = "100-Client Concurrency Load Benchmark";       File = "Test-100Clients.ps1" }
)

$summary = @()
$masterPassed = 0
$masterFailed = 0
$masterSw = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($s in $suites) {
    $scriptPath = Join-Path $testRoot $s.File
    Write-Host ">>> STARTING SUITE: $($s.Name)..." -ForegroundColor White
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    $exitCode = 0
    try {
        $proc = Start-Process powershell.exe -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath) -PassThru -Wait -NoNewWindow
        $exitCode = $proc.ExitCode
    }
    catch {
        $exitCode = 1
    }
    $sw.Stop()

    $duration = [Math]::Round($sw.Elapsed.TotalSeconds, 2)
    if ($exitCode -eq 0) {
        $masterPassed++
        Write-Host ">>> SUITE COMPLETED: $($s.Name) [PASSED] ($duration s)`n" -ForegroundColor Green
        $summary += [PSCustomObject]@{
            Suite    = $s.Name
            File     = $s.File
            Status   = "PASSED"
            Duration = "$duration s"
        }
    } else {
        $masterFailed++
        Write-Host ">>> SUITE FAILED: $($s.Name) [FAILED] (Exit Code: $exitCode, $duration s)`n" -ForegroundColor Red
        $summary += [PSCustomObject]@{
            Suite    = $s.Name
            File     = $s.File
            Status   = "FAILED"
            Duration = "$duration s"
        }
    }
}

$masterSw.Stop()
$totalSec = [Math]::Round($masterSw.Elapsed.TotalSeconds, 2)

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " MASTER VERIFICATION SUMMARY SCORECARD" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
$summary | Format-Table -Property Suite, Status, Duration -AutoSize

Write-Host "Total Suites Run     : $($suites.Count)" -ForegroundColor White
Write-Host "Total Suites Passed  : $masterPassed" -ForegroundColor Green
Write-Host "Total Suites Failed  : $masterFailed" -ForegroundColor $(if ($masterFailed -eq 0) { "Green" } else { "Red" })
Write-Host "Total Execution Time : $totalSec seconds" -ForegroundColor White
Write-Host "==============================================================================" -ForegroundColor Cyan

if ($masterFailed -gt 0) {
    Write-Host "FINAL VERDICT: FAIL - Regressions detected in test execution." -ForegroundColor Red
    exit 1
} else {
    Write-Host "FINAL VERDICT: PASS - 100% of test suites verified successfully." -ForegroundColor Green
    exit 0
}
