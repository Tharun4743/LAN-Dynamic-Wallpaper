# ==============================================================================
# Tests/Test-Publisher.ps1
# Automated Test Suite for Image Validation, SHA-256 Hashes & Atomic Publishing
# Pure Windows PowerShell 5.1+ - Self-contained unit & integration test
# ==============================================================================

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$publisherScript = Join-Path $PSScriptRoot "..\Host\Publisher.ps1"
if (-not (Test-Path -LiteralPath $publisherScript)) {
    throw "Publisher.ps1 not found at $publisherScript"
}
. $publisherScript

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " RUNNING TEST SUITE: Test-Publisher.ps1" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan

$testRoot = Join-Path $PSScriptRoot "Test-Sandbox-Publisher"
$testWallpapers = Join-Path $testRoot "Wallpapers"
$testPublished = Join-Path $testRoot "Published"

# Clean sandbox
if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $testWallpapers -Force | Out-Null
New-Item -ItemType Directory -Path $testPublished -Force | Out-Null

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

try {
    # Helper: Create synthetic valid PNG binary
    function New-ValidPngFile {
        param([string]$Path, [int]$ExtraBytes = 50)
        # PNG signature: 89 50 4E 47 0D 0A 1A 0A
        $header = [byte[]]@(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
        $extra = New-Object byte[] $ExtraBytes
        for ($i = 0; $i -lt $ExtraBytes; $i++) { $extra[$i] = [byte]($i % 256) }
        $all = $header + $extra
        [System.IO.File]::WriteAllBytes($Path, $all)
    }

    # Helper: Create synthetic valid JPEG binary
    function New-ValidJpgFile {
        param([string]$Path, [int]$ExtraBytes = 50)
        # JPEG signature: FF D8 FF E0
        $header = [byte[]]@(0xFF, 0xD8, 0xFF, 0xE0)
        $extra = New-Object byte[] $ExtraBytes
        for ($i = 0; $i -lt $ExtraBytes; $i++) { $extra[$i] = [byte]($i % 256) }
        $all = $header + $extra
        [System.IO.File]::WriteAllBytes($Path, $all)
    }

    # TEST 1: Binary Header Validation Tests
    Write-Host "`n-- Section 1: Binary Magic-Byte Validation --" -ForegroundColor White
    $validPngPath = Join-Path $testWallpapers "valid1.png"
    New-ValidPngFile -Path $validPngPath
    $resPng = Test-ValidImageBinary -FilePath $validPngPath
    Assert-Condition "Valid PNG Header Accepted" ($resPng.IsValid -eq $true)

    $validJpgPath = Join-Path $testWallpapers "valid2.jpg"
    New-ValidJpgFile -Path $validJpgPath
    $resJpg = Test-ValidImageBinary -FilePath $validJpgPath
    Assert-Condition "Valid JPEG Header Accepted" ($resJpg.IsValid -eq $true)

    $fakeExePath = Join-Path $testWallpapers "fake.png"
    # Write MZ executable header disguised as png
    [System.IO.File]::WriteAllBytes($fakeExePath, [byte[]]@(0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00))
    $resFake = Test-ValidImageBinary -FilePath $fakeExePath
    Assert-Condition "Spoofed Executable disguised as PNG Rejected" ($resFake.IsValid -eq $false)

    $zeroBytePath = Join-Path $testWallpapers "zero.jpg"
    [System.IO.File]::WriteAllBytes($zeroBytePath, [byte[]]@())
    $resZero = Test-ValidImageBinary -FilePath $zeroBytePath
    Assert-Condition "Zero-byte file Rejected" ($resZero.IsValid -eq $false)

    # TEST 2: Initial Publication & Atomic Manifest Generation
    Write-Host "`n-- Section 2: Collection Synchronization & Manifest Generation --" -ForegroundColor White
    $manifest1 = Sync-WallpaperCollection -SourceDir $testWallpapers -TargetDir $testPublished
    Assert-Condition "Initial Manifest Created" ($null -ne $manifest1)
    Assert-Condition "Valid Images Published Count == 2" ($manifest1.totalImages -eq 2)
    Assert-Condition "Atomic manifest.json Exists on Disk" (Test-Path (Join-Path $testPublished "manifest.json"))
    Assert-Condition "Fake files excluded from Published store" (-not (Test-Path (Join-Path $testPublished "fake.png")))

    $v1 = $manifest1.collectionVersion

    # TEST 3: Idempotency (Unchanged Collection retains Version)
    Write-Host "`n-- Section 3: Idempotency Check --" -ForegroundColor White
    $manifest2 = Sync-WallpaperCollection -SourceDir $testWallpapers -TargetDir $testPublished
    Assert-Condition "Collection Version unchanged when files unchanged" ($manifest2.collectionVersion -eq $v1)

    # TEST 4: Same-Size Content Replacement & Hash Recalculation
    Write-Host "`n-- Section 4: Same-Size Content Replacement --" -ForegroundColor White
    $prevHash = ($manifest1.images | Where-Object { $_.name -eq "valid1.png" }).hash
    
    # Overwrite valid1.png with same size but different content
    $header = [byte[]]@(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
    $modifiedExtra = New-Object byte[] 50
    for ($i = 0; $i -lt 50; $i++) { $modifiedExtra[$i] = 0xAA } # All 0xAA instead of sequence
    [System.IO.File]::WriteAllBytes($validPngPath, ($header + $modifiedExtra))

    $manifest3 = Sync-WallpaperCollection -SourceDir $testWallpapers -TargetDir $testPublished
    $newHash = ($manifest3.images | Where-Object { $_.name -eq "valid1.png" }).hash

    Assert-Condition "Same-Size Content Replacement Detected" ($manifest3.collectionVersion -ne $v1)
    Assert-Condition "SHA-256 Hash Recalculated Correctly" ($newHash -ne $prevHash)

    # TEST 5: Image Deletion & Pruning
    Write-Host "`n-- Section 5: Image Deletion & Pruning --" -ForegroundColor White
    Remove-Item -LiteralPath $validJpgPath -Force
    $manifest4 = Sync-WallpaperCollection -SourceDir $testWallpapers -TargetDir $testPublished
    Assert-Condition "Published Total Images reduced to 1" ($manifest4.totalImages -eq 1)
    Assert-Condition "Deleted file pruned from Published directory" (-not (Test-Path (Join-Path $testPublished "valid2.jpg")))
}
finally {
    # Cleanup sandbox
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " PUBLISHER TESTS COMPLETE: $passCount Passed, $failCount Failed" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Red" })
Write-Host "==============================================================================" -ForegroundColor Cyan

if ($failCount -gt 0) { exit 1 } else { exit 0 }
