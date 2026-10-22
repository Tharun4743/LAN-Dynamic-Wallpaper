# ==============================================================================
# Tests/Test-Host.ps1
# Automated Test Suite for Host Server HTTP Routes, RBAC & Endpoints
# Pure Windows PowerShell 5.1+ - Self-contained integration test
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$TestPort = 8795
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " RUNNING TEST SUITE: Test-Host.ps1 (Port $TestPort)" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan

$testSandbox = Join-Path $PSScriptRoot "Test-Sandbox-Host"
$testWallpapers = Join-Path $testSandbox "Wallpapers"
$testPublished = Join-Path $testSandbox "Published"
$testLogs = Join-Path $testSandbox "Logs"
$testConfig = Join-Path $testSandbox "HostConfig.json"

# Terminate any process currently holding $TestPort
try {
    $connections = Get-NetTCPConnection -LocalPort $TestPort -ErrorAction SilentlyContinue
    if ($connections) {
        foreach ($conn in $connections) {
            Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 1000
    }
} catch {}

# Clean sandbox
if (Test-Path -LiteralPath $testSandbox) {
    Remove-Item -LiteralPath $testSandbox -Recurse -Force -ErrorAction SilentlyContinue
}
foreach ($d in @($testWallpapers, $testPublished, $testLogs)) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}

# Create synthetic sample image in Wallpapers
$sampleImgPath = Join-Path $testWallpapers "sample.jpg"
$header = [byte[]]@(0xFF, 0xD8, 0xFF, 0xE0)
$extra = New-Object byte[] 60
for ($i = 0; $i -lt 60; $i++) { $extra[$i] = [byte]($i % 256) }
[System.IO.File]::WriteAllBytes($sampleImgPath, ($header + $extra))

$authSecret = "test_auth_secret_32_characters_long_123"
$adminSecret = "test_admin_secret_32_characters_long_456"

$cfg = [PSCustomObject]@{
    Server = [PSCustomObject]@{
        BindAddress           = "127.0.0.1"
        Port                  = $TestPort
        DiscoveryPort         = 8796
        EnableDiscovery       = $false
        MaxConcurrentRequests = 32
        RequestTimeoutSeconds = 10
    }
    Security = [PSCustomObject]@{
        AuthSecret            = $authSecret
        AdminSecret           = $adminSecret
        RequireAuthentication = $true
        MaxImageSizeBytes     = 10485760
        AllowedExtensions     = @(".jpg", ".jpeg", ".png", ".bmp")
    }
    Slideshow = [PSCustomObject]@{
        DefaultIntervalSeconds = 30
    }
    Paths = [PSCustomObject]@{
        WallpapersDir         = "Wallpapers"
        PublishedDir          = "Published"
        LogsDir               = "Logs"
        ClientsStore          = "clients.json"
    }
}
[System.IO.File]::WriteAllText($testConfig, ($cfg | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)

# Launch Host Server in Background Process
$hostScript = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\Host\Host.ps1"))
$argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $hostScript, "-ConfigPath", $testConfig, "-Port", "$TestPort")
$process = Start-Process powershell.exe -ArgumentList $argList -PassThru -WindowStyle Hidden

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
    # Wait for server to bind and respond
    $baseUrl = "http://127.0.0.1:$TestPort"
    $healthUri = "$baseUrl/api/v1/health"
    $isReady = $false
    for ($i = 0; $i -lt 25; $i++) {
        Start-Sleep -Milliseconds 500
        try {
            $h = Invoke-RestMethod -Uri $healthUri -TimeoutSec 1 -ErrorAction Stop
            if ($h.status -eq "ok") {
                $isReady = $true
                break
            }
        } catch {}
    }

    Assert-Condition "Host Server Started and Bound to Port $TestPort" ($isReady -eq $true)
    if (-not $isReady) {
        Write-Host "Process HasExited: $($process.HasExited)" -ForegroundColor Red
        throw "Host server failed to start within timeout."
    }

    # TEST 1: Public Health Endpoint
    Write-Host "`n-- Section 1: Health Probe --" -ForegroundColor White
    $health = Invoke-RestMethod -Uri $healthUri -TimeoutSec 3
    Assert-Condition "GET /api/v1/health returns status 'ok'" ($health.status -eq "ok")
    Assert-Condition "GET /api/v1/health reports 1 published image" ($health.totalImages -eq 1)

    # TEST 2: Client Registration with Valid Token
    Write-Host "`n-- Section 2: Client Registration --" -ForegroundColor White
    $regUri = "$baseUrl/api/v1/auth/register"
    $regHeaders = @{ "X-Auth-Token" = $authSecret }
    $regBody = @{ hostname = "TEST-PC-01"; clientVersion = "1.0.0" } | ConvertTo-Json
    $regResp = Invoke-RestMethod -Uri $regUri -Method Post -Headers $regHeaders -Body $regBody -ContentType "application/json"
    Assert-Condition "POST /api/v1/auth/register confirms ENROLLED" ($regResp.status -eq "ENROLLED")
    Assert-Condition "POST /api/v1/auth/register assigned Client ID" ($regResp.clientId.StartsWith("CLT-"))
    $testClientId = $regResp.clientId

    # TEST 3: Registration with Invalid Secret Rejected
    $badRegHeaders = @{ "X-Auth-Token" = "wrong_secret" }
    $badRegStatus = 0
    try {
        Invoke-RestMethod -Uri $regUri -Method Post -Headers $badRegHeaders -Body $regBody -ContentType "application/json" -ErrorAction Stop
    }
    catch {
        $badRegStatus = $_.Exception.Response.StatusCode.value__
    }
    Assert-Condition "POST /api/v1/auth/register with bad token returns HTTP 401" ($badRegStatus -eq 401)

    # TEST 4: Manifest Endpoint (Auth Guard Check)
    Write-Host "`n-- Section 3: Manifest & RBAC Route Guard --" -ForegroundColor White
    $manifestUri = "$baseUrl/api/v1/manifest"
    $unauthStatus = 0
    try {
        Invoke-RestMethod -Uri $manifestUri -ErrorAction Stop
    }
    catch {
        $unauthStatus = $_.Exception.Response.StatusCode.value__
    }
    Assert-Condition "GET /api/v1/manifest without token returns HTTP 401" ($unauthStatus -eq 401)

    $manifest = Invoke-RestMethod -Uri $manifestUri -Headers $regHeaders
    Assert-Condition "GET /api/v1/manifest with valid token returns manifest" ($null -ne $manifest.collectionVersion)
    Assert-Condition "Manifest contains sample.jpg" ($manifest.images[0].name -eq "sample.jpg")

    # TEST 5: Image Binary Download
    Write-Host "`n-- Section 4: Asset Streaming --" -ForegroundColor White
    $imgUri = "$baseUrl/api/v1/wallpaper/sample.jpg"
    $imgReq = [System.Net.HttpWebRequest]::Create($imgUri)
    $imgReq.Headers.Add("X-Auth-Token", $authSecret)
    $imgResp = $imgReq.GetResponse()
    Assert-Condition "GET /api/v1/wallpaper/sample.jpg returns HTTP 200" ($imgResp.StatusCode -eq [System.Net.HttpStatusCode]::OK)
    Assert-Condition "Asset stream Content-Type is image/jpeg" ($imgResp.ContentType -eq "image/jpeg")
    Assert-Condition "X-Image-Sha256 header present" (-not [string]::IsNullOrWhiteSpace($imgResp.Headers["X-Image-Sha256"]))
    $imgResp.Close()

    # TEST 6: Heartbeat Telemetry
    Write-Host "`n-- Section 5: Client Heartbeat --" -ForegroundColor White
    $hbUri = "$baseUrl/api/v1/heartbeat"
    $hbBody = @{ clientId = $testClientId; currentImageHash = "abc123hash" } | ConvertTo-Json
    $hbResp = Invoke-RestMethod -Uri $hbUri -Method Post -Headers $regHeaders -Body $hbBody -ContentType "application/json"
    Assert-Condition "POST /api/v1/heartbeat returns status 'ACK'" ($hbResp.status -eq "ACK")

    # TEST 7: SuperAdmin Role Protection
    Write-Host "`n-- Section 6: RBAC Administrator Authorization --" -ForegroundColor White
    $adminClientsUri = "$baseUrl/api/v1/admin/clients"
    
    # Client token trying to access admin endpoint -> must return 403 Forbidden
    $escalateStatus = 0
    try {
        Invoke-RestMethod -Uri $adminClientsUri -Headers $regHeaders -ErrorAction Stop
    }
    catch {
        $escalateStatus = $_.Exception.Response.StatusCode.value__
    }
    Assert-Condition "Client token denied on /api/v1/admin/clients (HTTP 403 Forbidden)" ($escalateStatus -eq 403)

    # Admin token accessing admin endpoint -> must return 200 OK
    $adminHeaders = @{ "Authorization" = "Bearer $adminSecret" }
    $adminClients = Invoke-RestMethod -Uri $adminClientsUri -Headers $adminHeaders
    Assert-Condition "Admin token permitted on /api/v1/admin/clients (HTTP 200)" ($adminClients.totalClients -ge 1)
    Assert-Condition "Enrolled client present in admin telemetry roster" (@($adminClients.clients | Where-Object { $_.clientId -eq $testClientId }).Count -eq 1)

    # TEST 8: Admin Force-Sync Trigger
    $adminSyncUri = "$baseUrl/api/v1/admin/sync"
    $syncResp = Invoke-RestMethod -Uri $adminSyncUri -Method Post -Headers $adminHeaders
    Assert-Condition "POST /api/v1/admin/sync succeeds with Admin token" ($syncResp.message -like "*completed*")
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $testSandbox) {
        Remove-Item -LiteralPath $testSandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " HOST SERVER TESTS COMPLETE: $passCount Passed, $failCount Failed" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Red" })
Write-Host "==============================================================================" -ForegroundColor Cyan

if ($failCount -gt 0) { exit 1 } else { exit 0 }
