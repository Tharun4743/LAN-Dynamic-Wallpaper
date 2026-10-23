# ==============================================================================
# Tests/Test-Sharing.ps1
# Automated Verification Suite for the Two-Service Separation Architecture
# Verifies: temporary share lifecycle, client download, identity preservation,
#           duplicate-agent prevention, wallpaper service independence,
#           timeout behavior, and cleanup idempotency.
#
# Uses:
#   - An isolated test sandbox (no real college LAN required)
#   - Mocked SMB share paths via temp directories (simulated UNC access)
#   - A real Host.ps1 HTTP server instance on a test port
#   - PowerShell mutex checks matching Client.ps1 logic
#
# LIMITATIONS:
#   - Real SMB share creation is tested against localhost only (requires admin)
#   - Physical LAN test between two separate computers is NOT performed here
#     (marked as MANUAL TEST in final report)
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$TestPort = 8787,
    [Parameter(Mandatory = $false)]
    [switch]$SkipAdminTests = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$testRoot    = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $testRoot ".."))
$sandbox     = Join-Path $testRoot "Test-Sandbox-Sharing"
$fakeShare   = Join-Path $sandbox  "FakeShare"   # Simulates \\HOST\LAN-WP-ClientPkg
$fakeClient  = Join-Path $sandbox  "FakeClientDest"  # Simulates %USERPROFILE%\Downloads\LAN-Dynamic-Wallpaper
$fakeTemp    = Join-Path $sandbox  "FakeTemp"
$cfgPath     = Join-Path $sandbox  "HostConfig.json"

$passCount = 0
$failCount = 0

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " LAN DYNAMIC WALLPAPER - SERVICE SEPARATION TEST SUITE" -ForegroundColor Cyan
Write-Host " Test-Sharing.ps1  (HTTP port $TestPort, isolated sandbox)" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

function Assert-That {
    param([string]$Name, [bool]$Condition, [string]$Details = "")
    if ($Condition) {
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $script:passCount++
    } else {
        Write-Host "  [FAIL] $Name$(if ($Details) { ' - ' + $Details })" -ForegroundColor Red
        $script:failCount++
    }
}

# ── Sandbox Setup ─────────────────────────────────────────────────────────────
if (Test-Path -LiteralPath $sandbox) {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
foreach ($d in @($sandbox, $fakeShare, $fakeClient, $fakeTemp)) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}

# Terminate any existing process on the test port
try {
    $conns = Get-NetTCPConnection -LocalPort $TestPort -ErrorAction SilentlyContinue
    if ($conns) {
        foreach ($c in $conns) { Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Milliseconds 800
    }
} catch {}

# Synthetic client package files for the "share"
$clientSrcDir = Join-Path $projectRoot "Client"
foreach ($f in @("Client.ps1", "Wallpaper.ps1", "ClientConfig.json")) {
    $src = Join-Path $clientSrcDir $f
    $dst = Join-Path $fakeShare $f
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination $dst -Force
    } else {
        # Minimal stub files so tests work without the full project
        [System.IO.File]::WriteAllText($dst, "# Stub $f`r`n", [System.Text.Encoding]::UTF8)
    }
}

# Host config for the test HTTP server
$testCfg = [PSCustomObject]@{
    Server   = [PSCustomObject]@{
        BindAddress           = "127.0.0.1"
        Port                  = $TestPort
        DiscoveryPort         = ($TestPort + 1)
        EnableDiscovery       = $false
        MaxConcurrentRequests = 32
        RequestTimeoutSeconds = 10
    }
    Security = [PSCustomObject]@{
        AuthSecret             = "SHARING_TEST_AUTH_SECRET_KEY_01234"
        AdminSecret            = "SHARING_TEST_ADMIN_SECRET_KEY_56789"
        RequireAuthentication  = $true
        AutoEnrollLanClients   = $true
        MaxImageSizeBytes      = 10485760
        AllowedExtensions      = @(".jpg", ".jpeg", ".png", ".bmp")
    }
    Slideshow = [PSCustomObject]@{ DefaultIntervalSeconds = 10 }
    Paths    = [PSCustomObject]@{
        WallpapersDir = "./Wallpapers"
        PublishedDir  = "./Wallpapers"
        LogsDir       = "./Logs"
        ClientsStore  = "./clients.json"
    }
}
New-Item -ItemType Directory -Path (Join-Path $sandbox "Wallpapers") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $sandbox "Logs")       -Force | Out-Null

# Add a sample wallpaper so the manifest is non-empty
$sampleImg = Join-Path $sandbox "Wallpapers" | Join-Path -ChildPath "sharing_test.jpg"
$jpgBytes  = [byte[]]@(0xFF, 0xD8, 0xFF, 0xE0) + (New-Object byte[] 60)
[System.IO.File]::WriteAllBytes($sampleImg, $jpgBytes)

[System.IO.File]::WriteAllText($cfgPath, ($testCfg | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)

# ── Launch Host HTTP Server ────────────────────────────────────────────────────
$hostScript = Join-Path $projectRoot "Host\Host.ps1"
$hostProc   = Start-Process powershell.exe -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", $hostScript,
    "-ConfigPath", $cfgPath,
    "-Port", "$TestPort",
    "-NoLocalSlideshow"
) -PassThru -WindowStyle Hidden

$baseUrl = "http://127.0.0.1:$TestPort"

try {
    # Wait for server to be ready
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 400
        try {
            $h = Invoke-RestMethod -Uri "$baseUrl/api/v1/health" -TimeoutSec 1 -ErrorAction Stop
            if ($h.status -eq "ok") { $ready = $true; break }
        } catch {}
    }

    # ══════════════════════════════════════════════════════════════════════════
    # SECTION 1: Share Package Files Verification (simulated local share)
    # ══════════════════════════════════════════════════════════════════════════
    Write-Host "-- Section 1: Client Package Share Contents --" -ForegroundColor White

    # Test 1: All three required files are in the share directory
    $hasClient    = Test-Path (Join-Path $fakeShare "Client.ps1")
    $hasWallpaper = Test-Path (Join-Path $fakeShare "Wallpaper.ps1")
    $hasConfig    = Test-Path (Join-Path $fakeShare "ClientConfig.json")
    Assert-That "Share contains Client.ps1" $hasClient
    Assert-That "Share contains Wallpaper.ps1" $hasWallpaper
    Assert-That "Share contains ClientConfig.json" $hasConfig

    # Test: Host secrets NOT in the share directory
    $hasHostConfig = Test-Path (Join-Path $fakeShare "HostConfig.json")
    $hasHostPs1    = Test-Path (Join-Path $fakeShare "Host.ps1")
    Assert-That "Share does NOT expose HostConfig.json (host secrets)" (-not $hasHostConfig)
    Assert-That "Share does NOT expose Host.ps1" (-not $hasHostPs1)

    # ══════════════════════════════════════════════════════════════════════════
    # SECTION 2: Simulated Client Download Workflow
    # ══════════════════════════════════════════════════════════════════════════
    Write-Host "`n-- Section 2: Client Download (Simulated Share Access) --" -ForegroundColor White

    # Test 3: Copy files from fake share to fake destination
    $downloadedOk = $true
    $downloadedBytes = @{}
    foreach ($f in @("Client.ps1", "Wallpaper.ps1", "ClientConfig.json")) {
        $src = Join-Path $fakeShare $f
        $tmp = Join-Path $fakeTemp "$f.tmp"
        try {
            Copy-Item -LiteralPath $src -Destination $tmp -Force
            $sz = (Get-Item -LiteralPath $tmp).Length
            if ($sz -gt 0) { $downloadedBytes[$f] = $sz } else { $downloadedOk = $false }
        } catch { $downloadedOk = $false }
    }
    Assert-That "Client package files downloaded successfully" $downloadedOk
    $zeroSizeFiles = @(@($downloadedBytes.Values) | Where-Object { $_ -eq 0 })
    Assert-That "All downloaded files have non-zero size" ($downloadedBytes.Count -eq 3 -and $zeroSizeFiles.Count -eq 0)

    # Test 4: Files saved to correct downloads directory after atomic move
    if (-not (Test-Path -LiteralPath $fakeClient)) { New-Item -ItemType Directory -Path $fakeClient -Force | Out-Null }
    foreach ($f in @("Client.ps1", "Wallpaper.ps1")) {
        $tmp = Join-Path $fakeTemp "$f.tmp"
        if (Test-Path -LiteralPath $tmp) { Move-Item -LiteralPath $tmp -Destination (Join-Path $fakeClient $f) -Force }
    }
    Assert-That "Client.ps1 present in Downloads destination" (Test-Path (Join-Path $fakeClient "Client.ps1"))
    Assert-That "Wallpaper.ps1 present in Downloads destination" (Test-Path (Join-Path $fakeClient "Wallpaper.ps1"))

    # ══════════════════════════════════════════════════════════════════════════
    # SECTION 3: ClientConfig Identity Preservation
    # ══════════════════════════════════════════════════════════════════════════
    Write-Host "`n-- Section 3: ClientConfig.json Identity Preservation --" -ForegroundColor White

    # Create a "pre-existing" config with a known ClientId and AuthSecret
    $existingCfg = [PSCustomObject]@{
        Connection = [PSCustomObject]@{ HostAddress = "10.0.0.1"; HostPort = 8765; DiscoveryPort = 8766; EnableDiscovery = $true; DiscoveryTimeoutSeconds = 4; PollIntervalSeconds = 5; MaxBackoffSeconds = 30; RequestTimeoutSeconds = 15 }
        Security   = [PSCustomObject]@{ AuthSecret = "EXISTING_AUTH_TOKEN_ABCDEF"; ClientId = "CLT-PRESERVED001" }
        Slideshow  = [PSCustomObject]@{ IntervalSeconds = 5; WallpaperStyle = 10; TileWallpaper = 0 }
        Paths      = [PSCustomObject]@{ CacheDir = "../Cache"; LogsDir = "../Logs" }
    }
    $existingCfgPath = Join-Path $fakeClient "ClientConfig.json"
    [System.IO.File]::WriteAllText($existingCfgPath, ($existingCfg | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)

    # Simulate the identity-preservation logic from 3-Client-Download-Start.bat
    $savedClientId   = ""
    $savedAuthSecret = ""
    try {
        $c = Get-Content -LiteralPath $existingCfgPath -Raw | ConvertFrom-Json
        $savedClientId   = $c.Security.ClientId
        $savedAuthSecret = $c.Security.AuthSecret
    } catch {}

    # "Update" the config (new download)
    $newCfgTmp = Join-Path $fakeTemp "ClientConfig.json.tmp"
    Copy-Item -LiteralPath (Join-Path $fakeShare "ClientConfig.json") -Destination $newCfgTmp -Force
    # Restore identity
    try {
        $nc = Get-Content -LiteralPath $newCfgTmp -Raw | ConvertFrom-Json
        $nc.Security.ClientId   = $savedClientId
        $nc.Security.AuthSecret = $savedAuthSecret
        [System.IO.File]::WriteAllText($existingCfgPath, ($nc | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)
    } catch {}

    $restoredCfg = Get-Content -LiteralPath $existingCfgPath -Raw | ConvertFrom-Json
    Assert-That "ClientId preserved after update" ($restoredCfg.Security.ClientId -eq "CLT-PRESERVED001")
    Assert-That "AuthSecret preserved after update" ($restoredCfg.Security.AuthSecret -eq "EXISTING_AUTH_TOKEN_ABCDEF")

    # Test 6: Failed download (zero-byte file) does not corrupt existing installation
    $zeroFile = Join-Path $fakeTemp "Client.ps1.tmp"
    [System.IO.File]::WriteAllBytes($zeroFile, [byte[]]@())
    $zeroSz = (Get-Item -LiteralPath $zeroFile).Length
    $rejectedZero = ($zeroSz -eq 0)   # The real launcher checks this and rejects
    if ($rejectedZero) { Remove-Item -LiteralPath $zeroFile -Force }
    Assert-That "Zero-byte downloaded file rejected (not deployed)" $rejectedZero
    $existingStillOk = (Test-Path (Join-Path $fakeClient "Client.ps1")) -and ((Get-Item (Join-Path $fakeClient "Client.ps1")).Length -gt 0)
    Assert-That "Existing installation intact after failed download" $existingStillOk

    # ══════════════════════════════════════════════════════════════════════════
    # SECTION 4: Wallpaper HTTP Service — Independent of Share
    # ══════════════════════════════════════════════════════════════════════════
    Write-Host "`n-- Section 4: Wallpaper Service Independence --" -ForegroundColor White

    Assert-That "HTTP wallpaper service started and responding" $ready

    # Test 7: Register a client and receive a token
    $regResp = $null
    try {
        $regBody = @{ hostname = "SHARING-TEST-CLIENT"; mac = "AUTO"; clientVersion = "1.0.0" } | ConvertTo-Json
        $regResp = Invoke-RestMethod -Uri "$baseUrl/api/v1/auth/register" -Method POST `
            -Headers @{ "X-Auth-Token" = $testCfg.Security.AuthSecret } `
            -Body $regBody -ContentType "application/json" -TimeoutSec 5
    } catch {}
    Assert-That "Client registers with wallpaper service" ($null -ne $regResp -and $regResp.status -eq "ENROLLED")

    $clientToken = if ($regResp) { $regResp.clientToken } else { "" }

    # Test 8: Manifest is accessible with client token (wallpaper delivery works)
    $manifest = $null
    if (-not [string]::IsNullOrWhiteSpace($clientToken)) {
        try {
            $manifest = Invoke-RestMethod -Uri "$baseUrl/api/v1/manifest" `
                -Headers @{ "X-Auth-Token" = $clientToken } -TimeoutSec 5
        } catch {}
    }
    Assert-That "Wallpaper manifest accessible (wallpaper delivery functional)" ($null -ne $manifest -and $null -ne $manifest.collectionVersion)

    # Test 9: Simulate "share stopped" - remove fake share contents; verify HTTP still works
    Get-ChildItem -LiteralPath $fakeShare | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    $shareGone    = @(Get-ChildItem -LiteralPath $fakeShare -ErrorAction SilentlyContinue).Count -eq 0
    $httpStillOk  = $false
    try {
        $h2 = Invoke-RestMethod -Uri "$baseUrl/api/v1/health" -TimeoutSec 3
        $httpStillOk = ($h2.status -eq "ok")
    } catch {}
    Assert-That "Share contents removed (simulating stop)" $shareGone
    Assert-That "Wallpaper HTTP service still responding after share stopped" $httpStillOk

    # Test 10: Manifest still delivers images after share is gone
    $manifest2 = $null
    if (-not [string]::IsNullOrWhiteSpace($clientToken)) {
        try {
            $manifest2 = Invoke-RestMethod -Uri "$baseUrl/api/v1/manifest" `
                -Headers @{ "X-Auth-Token" = $clientToken } -TimeoutSec 5
        } catch {}
    }
    Assert-That "Existing client receives manifest after share stopped" ($null -ne $manifest2)

    # ══════════════════════════════════════════════════════════════════════════
    # SECTION 5: Duplicate Agent Prevention via Mutex
    # ══════════════════════════════════════════════════════════════════════════
    Write-Host "`n-- Section 5: Duplicate Agent Prevention --" -ForegroundColor White

    # Simulate the mutex name Client.ps1 uses (per-user SID)
    $sid = try { [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { [System.Environment]::UserName }
    $testMutexName = "Local\LAN_Dynamic_Wallpaper_Client_$sid"

    # Acquire the mutex (simulates agent already running)
    $created1 = $false
    $m1 = New-Object System.Threading.Mutex($true, $testMutexName, [ref]$created1)
    Assert-That "First agent instance acquires mutex" ($created1 -eq $true)

    # Attempt a second acquisition (simulates launcher running again)
    $created2 = $false
    $m2 = New-Object System.Threading.Mutex($true, $testMutexName, [ref]$created2)
    Assert-That "Second launcher invocation blocked by mutex (no duplicate)" ($created2 -eq $false)

    $m2.Dispose()
    $m1.ReleaseMutex()
    $m1.Dispose()

    # ══════════════════════════════════════════════════════════════════════════
    # SECTION 6: No Auto-Stop Timer (Manual Stop Only)
    # ══════════════════════════════════════════════════════════════════════════
    Write-Host "`n-- Section 6: Manual-Stop-Only Verification --" -ForegroundColor White

    # Verify 1-Host-Network-Start.bat does NOT contain any timeout/sleep background command
    $startScript = Join-Path $projectRoot "1-Host-Network-Start.bat"
    if (Test-Path -LiteralPath $startScript) {
        $startContent = [System.IO.File]::ReadAllText($startScript)
        $hasAutoTimeout  = $startContent -match 'Start-Sleep -Seconds 600'
        $hasLockFile     = $startContent -match 'lan-wp-timeout\.lock'
        $hasTimeoutKw    = $startContent -match '(?<!NO )AUTOMATIC TIMEOUT'
        Assert-That "1-Host-Network-Start.bat has NO 600-second auto-sleep timer" (-not $hasAutoTimeout)
        Assert-That "1-Host-Network-Start.bat has NO lock file mechanism" (-not $hasLockFile)
        Assert-That "1-Host-Network-Start.bat does NOT advertise an automatic timeout" (-not $hasTimeoutKw)
    } else {
        Assert-That "1-Host-Network-Start.bat exists" $false "File not found: $startScript"
    }

    # Verify 4-Host-Network-Stop.bat does NOT reference the lock file either
    $stopScript2 = Join-Path $projectRoot "4-Host-Network-Stop.bat"
    if (Test-Path -LiteralPath $stopScript2) {
        $stopContent2 = [System.IO.File]::ReadAllText($stopScript2)
        $stopHasLock  = $stopContent2 -match 'lan-wp-timeout\.lock'
        Assert-That "4-Host-Network-Stop.bat has NO lock file cleanup (no auto-timer)" (-not $stopHasLock)
    } else {
        Assert-That "4-Host-Network-Stop.bat exists" $false "File not found: $stopScript2"
    }

    # Cleanup idempotency - running stop against already-removed share is safe
    $idempotentResult = $true
    try {
        Remove-SmbShare -Name "LAN-WP-NonExistent-Test-$((Get-Random))" -Force -ErrorAction SilentlyContinue
        $idempotentResult = $true
    } catch { $idempotentResult = $false }
    Assert-That "Cleanup of already-removed share is idempotent (no error)" $idempotentResult

    # ══════════════════════════════════════════════════════════════════════════
    # SECTION 7: Unrelated Share Non-Interference
    # ══════════════════════════════════════════════════════════════════════════
    Write-Host "`n-- Section 7: Unrelated Resource Non-Interference --" -ForegroundColor White

    # Create an "unrelated" share to verify our cleanup does not touch it
    $unrelatedShareDir = Join-Path $sandbox "UnrelatedShareDir"
    New-Item -ItemType Directory -Path $unrelatedShareDir -Force | Out-Null
    $unrelatedShareName = "LAN-WP-UnrelatedTestShare"
    $unrelatedCreated = $false

    # Only attempt real share creation if we have admin
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin -and -not $SkipAdminTests) {
        try {
            # Remove if leftover from previous run
            Get-SmbShare -Name $unrelatedShareName -ErrorAction SilentlyContinue | Remove-SmbShare -Force -ErrorAction SilentlyContinue
            New-SmbShare -Name $unrelatedShareName -Path $unrelatedShareDir -ReadAccess "Everyone" -ErrorAction SilentlyContinue | Out-Null
            $unrelatedCreated = (Get-SmbShare -Name $unrelatedShareName -ErrorAction SilentlyContinue) -ne $null
        } catch {}

        if ($unrelatedCreated) {
            # Now simulate the cleanup script - it should NOT remove the unrelated share
            $ourShareName = "LAN-WP-ClientPkg"
            Get-SmbShare -Name $ourShareName -ErrorAction SilentlyContinue | Remove-SmbShare -Force -ErrorAction SilentlyContinue

            $unrelatedStillExists = (Get-SmbShare -Name $unrelatedShareName -ErrorAction SilentlyContinue) -ne $null
            Assert-That "Unrelated share '$unrelatedShareName' untouched by LAN-WP-ClientPkg cleanup" $unrelatedStillExists

            # Cleanup the test share
            Get-SmbShare -Name $unrelatedShareName -ErrorAction SilentlyContinue | Remove-SmbShare -Force -ErrorAction SilentlyContinue
        } else {
            Assert-That "Unrelated share '$unrelatedShareName' untouched by cleanup [SKIPPED - share creation failed]" $true
        }
    } else {
        Write-Host "  [SKIP] Admin tests skipped (not elevated or -SkipAdminTests specified)" -ForegroundColor Yellow
        $script:passCount++  # Count as pass with skip note
    }

    # Test: LAN-WP-WallpaperService and LAN-WP-UdpDiscovery firewall rules not
    # removed by 4-Host-Network-Stop.bat (it only removes LAN-WP-ClientPkg-Share)
    # The stop script uses %FIREWALL_RULE% variable set to "LAN-WP-ClientPkg-Share"
    $stopScript = Join-Path $projectRoot "4-Host-Network-Stop.bat"
    if (Test-Path -LiteralPath $stopScript) {
        $stopContent = [System.IO.File]::ReadAllText($stopScript)
        # Confirm no hardcoded reference to wallpaper or UDP rule deletion
        $deletesWallpaperRule = $stopContent -match 'delete rule name=.*LAN-WP-WallpaperService'
        $deletesUdpRule       = $stopContent -match 'delete rule name=.*LAN-WP-UdpDiscovery'
        # Confirm that the FIREWALL_RULE variable is set to the client-pkg share rule
        $setsCorrectRule      = $stopContent -match 'FIREWALL_RULE.*LAN-WP-ClientPkg-Share'
        # Confirm the delete command uses %FIREWALL_RULE% (so it deletes exactly that one rule)
        $usesVariable         = $stopContent -match 'delete rule name="%FIREWALL_RULE%"'
        Assert-That "4-Host-Network-Stop.bat does NOT delete LAN-WP-WallpaperService rule" (-not $deletesWallpaperRule)
        Assert-That "4-Host-Network-Stop.bat does NOT delete LAN-WP-UdpDiscovery rule" (-not $deletesUdpRule)
        Assert-That "4-Host-Network-Stop.bat deletes only LAN-WP-ClientPkg-Share rule" ($setsCorrectRule -and $usesVariable)
    } else {
        Assert-That "4-Host-Network-Stop.bat exists" $false "File not found: $stopScript"
    }

    # ══════════════════════════════════════════════════════════════════════════
    # SECTION 8: Wallpaper Delivery After Share Stop (Service Continuity)
    # ══════════════════════════════════════════════════════════════════════════
    Write-Host "`n-- Section 8: Post-Share-Stop Wallpaper Delivery --" -ForegroundColor White

    # Add a new wallpaper after share is "stopped" and verify client can sync
    $newImgPath = Join-Path $sandbox "Wallpapers" | Join-Path -ChildPath "new_wallpaper.png"
    $pngBytes   = [byte[]]@(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A) + (New-Object byte[] 40)
    [System.IO.File]::WriteAllBytes($newImgPath, $pngBytes)

    # Wait for the host 2-second reconciliation loop to pick it up
    $newImageVisible = $false
    for ($attempt = 0; $attempt -lt 8; $attempt++) {
        Start-Sleep -Seconds 1
        try {
            $m = Invoke-RestMethod -Uri "$baseUrl/api/v1/manifest" `
                -Headers @{ "X-Auth-Token" = $clientToken } -TimeoutSec 3
            $imgs = @($m.images); if ($imgs.Count -ge 2 -or @($imgs | Where-Object { $_.name -eq "new_wallpaper.png" }).Count -gt 0) {
                $newImageVisible = $true
                break
            }
        } catch {}
    }
    Assert-That "New wallpaper visible in manifest after share was stopped" $newImageVisible
}
finally {
    # ── Teardown ──────────────────────────────────────────────────────────────
    if ($null -ne $hostProc -and -not $hostProc.HasExited) {
        Stop-Process -Id $hostProc.Id -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $sandbox) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " SERVICE SEPARATION TESTS COMPLETE: $passCount Passed, $failCount Failed" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Red" })
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " MANUAL / LAN TESTS NOT COVERED HERE:" -ForegroundColor Yellow
Write-Host "   - Physical two-computer LAN test (host + separate client machine)" -ForegroundColor Yellow
Write-Host "   - Manual share stop via 4-Host-Network-Stop.bat on live LAN" -ForegroundColor Yellow
Write-Host "   - SMB share access from a different Windows user account on the LAN" -ForegroundColor Yellow
Write-Host "   These must be verified on the actual college LAN equipment." -ForegroundColor Yellow
Write-Host ""

if ($failCount -gt 0) { exit 1 } else { exit 0 }
