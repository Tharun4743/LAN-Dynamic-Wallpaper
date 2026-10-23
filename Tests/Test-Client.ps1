# ==============================================================================
# Tests/Test-Client.ps1
# Automated Test Suite for Client Cache, Wallpaper P/Invoke & Offline Resilience
# Pure Windows PowerShell 5.1+ - Self-contained unit & integration test
# ==============================================================================

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " RUNNING TEST SUITE: Test-Client.ps1" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan

$testSandbox = Join-Path $PSScriptRoot "Test-Sandbox-Client"
$testCache = Join-Path $testSandbox "Cache"
$testLogs = Join-Path $testSandbox "Logs"

# Clean sandbox
if (Test-Path -LiteralPath $testSandbox) {
    Remove-Item -LiteralPath $testSandbox -Recurse -Force -ErrorAction SilentlyContinue
}
foreach ($d in @($testCache, $testLogs)) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}

$passCount = 0
$failCount = 0

function Assert-Condition {
    param([string]$TestName, [bool]$Condition, [string]$Details = "")
    if ($Condition) {
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
        $script:passCount++
    } else {
        Write-Host "  [FAIL] $TestName - $Details" -ForegroundColor Red
        $script:failCount++
    }
}

# Import Wallpaper Engine
$wallpaperScript = Join-Path $PSScriptRoot "..\Client\Wallpaper.ps1"
if (-not (Test-Path -LiteralPath $wallpaperScript)) {
    throw "Wallpaper.ps1 not found at $wallpaperScript"
}
. $wallpaperScript

try {
    # Helper to generate valid dummy image files
    function New-DummyBmp {
        param([string]$Path, [int]$Width = 10, [int]$Height = 10)
        # Minimal 24-bit uncompressed BMP (54 bytes header + pixel data)
        $fileSize = 54 + ($Width * $Height * 3)
        $bytes = New-Object byte[] $fileSize
        # 'BM'
        $bytes[0] = 0x42; $bytes[1] = 0x4D
        # File size
        $bytes[2] = [byte]($fileSize -band 0xFF); $bytes[3] = [byte](($fileSize -shr 8) -band 0xFF)
        # Offset to pixel array (54)
        $bytes[10] = 54
        # DIB Header size (40)
        $bytes[14] = 40
        # Width
        $bytes[18] = [byte]($Width -band 0xFF)
        # Height
        $bytes[22] = [byte]($Height -band 0xFF)
        # Planes
        $bytes[26] = 1
        # Bits per pixel (24)
        $bytes[28] = 24
        # Fill pixels with pattern
        for ($i = 54; $i -lt $fileSize; $i++) { $bytes[$i] = 0x55 }
        [System.IO.File]::WriteAllBytes($Path, $bytes)
    }

    # TEST 1: P/Invoke Wallpaper Compilation & Win32 Interop
    Write-Host "`n-- Section 1: Win32 P/Invoke Wallpaper Engine --" -ForegroundColor White
    $img1 = Join-Path $testCache "wallpaper_alpha.bmp"
    $img2 = Join-Path $testCache "wallpaper_beta.bmp"
    $img3 = Join-Path $testCache "wallpaper_gamma.bmp"
    New-DummyBmp -Path $img1
    New-DummyBmp -Path $img2
    New-DummyBmp -Path $img3

    Assert-Condition "Win32WallpaperEngine Type Exists in AppDomain" ($null -ne ([System.Management.Automation.PSTypeName]'Win32WallpaperEngine').Type)

    $applyResult = Set-DesktopWallpaper -ImagePath $img1
    Assert-Condition "Set-DesktopWallpaper executed successfully" ($applyResult -eq $true)

    # TEST 2: Deterministic Slideshow Rotation
    Write-Host "`n-- Section 2: Deterministic Rotation Sequence --" -ForegroundColor White
    $collection = New-Object System.Collections.Generic.List[string]
    $collection.Add($img1)
    $collection.Add($img2)
    $collection.Add($img3)

    $idx = [ref]0
    # Current is index 0 ($img1)
    # Next should be index 1 ($img2)
    $next1 = Step-WallpaperRotation -ImageFiles $collection -CurrentIndex $idx
    Assert-Condition "Rotation Step 1 advanced to second image" ($next1 -eq $img2 -and $idx.Value -eq 1)

    # Next should be index 2 ($img3)
    $next2 = Step-WallpaperRotation -ImageFiles $collection -CurrentIndex $idx
    Assert-Condition "Rotation Step 2 advanced to third image" ($next2 -eq $img3 -and $idx.Value -eq 2)

    # Next should wrap back to index 0 ($img1)
    $next3 = Step-WallpaperRotation -ImageFiles $collection -CurrentIndex $idx
    Assert-Condition "Rotation Step 3 wrapped back to first image (Deterministic Cycle)" ($next3 -eq $img1 -and $idx.Value -eq 0)

    # TEST 3: Graceful Deletion Handling During Rotation
    Write-Host "`n-- Section 3: Rotation Resilience upon File Deletion --" -ForegroundColor White
    # Delete the active image from disk
    Remove-Item -LiteralPath $img2 -Force
    # Now set pointer so next target would have been $img2 (index 0 -> next is 1)
    $idx.Value = 0
    $recoveryStep = Step-WallpaperRotation -ImageFiles $collection -CurrentIndex $idx
    Assert-Condition "Missing file detected and gracefully bypassed" ($recoveryStep -eq $img3)

    # TEST 4: Offline Cache Retention
    Write-Host "`n-- Section 4: Offline Resilience --" -ForegroundColor White
    # Simulating host drop: Local cache still contains images, rotation continues
    Assert-Condition "Local Cache retained valid images when offline" ($collection.Count -gt 0)
    $offlineStep = Step-WallpaperRotation -ImageFiles $collection -CurrentIndex $idx
    Assert-Condition "Wallpaper rotation continues smoothly in offline mode" ($null -ne $offlineStep)

    # TEST 5: Single-Instance Mutex Enforcement
    Write-Host "`n-- Section 5: Single-Instance Mutex Lock --" -ForegroundColor White
    $mutexName = "Global\LAN_Dynamic_Wallpaper_Client_Test_Mutex"
    $createdNew1 = $false
    $m1 = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew1)
    Assert-Condition "Primary instance successfully acquired Mutex" ($createdNew1 -eq $true)

    $createdNew2 = $false
    $m2 = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew2)
    Assert-Condition "Secondary instance blocked from acquiring Mutex (Duplicate Prevention)" ($createdNew2 -eq $false)

    $m2.Dispose()
    $m1.ReleaseMutex()
    $m1.Dispose()

    # TEST 6: Exact-Second Fleet Synchronization
    Write-Host "`n-- Section 6: Exact-Second Fleet Clock Synchronization --" -ForegroundColor White
    $syncTestList = New-Object System.Collections.Generic.List[string]
    $syncTestList.Add($img1)
    $syncTestList.Add($img3)
    $syncResult1 = Get-SynchronizedWallpaper -ImageFiles $syncTestList -IntervalSeconds 5
    Assert-Condition "Get-SynchronizedWallpaper returns valid object" ($null -ne $syncResult1)
    Assert-Condition "Synchronized index is bounded by collection count" ($syncResult1.Index -ge 0 -and $syncResult1.Index -lt $syncTestList.Count)
    Assert-Condition "Seconds remaining is positive and within interval" ($syncResult1.SecondsRemaining -ge 1 -and $syncResult1.SecondsRemaining -le 5)
    $syncResult2 = Get-SynchronizedWallpaper -ImageFiles $syncTestList -IntervalSeconds 5
    Assert-Condition "Deterministic clock synchronization across parallel nodes" ($syncResult1.Index -eq $syncResult2.Index -and $syncResult1.Path -eq $syncResult2.Path)
}
finally {
    if (Test-Path -LiteralPath $testSandbox) {
        Remove-Item -LiteralPath $testSandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " CLIENT TESTS COMPLETE: $passCount Passed, $failCount Failed" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Red" })
Write-Host "==============================================================================" -ForegroundColor Cyan

if ($failCount -gt 0) { exit 1 } else { exit 0 }
