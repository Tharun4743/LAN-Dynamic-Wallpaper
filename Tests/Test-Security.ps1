# ==============================================================================
# Tests/Test-Security.ps1
# Security Penetration & Vulnerability Verification Test Suite
# Tests path traversal, auth evasion, role escalation & malformed payloads
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$TestPort = 8797
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " RUNNING SECURITY PENETRATION SUITE: Test-Security.ps1 (Port $TestPort)" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan

$testSandbox = Join-Path $PSScriptRoot "Test-Sandbox-Security"
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

if (Test-Path -LiteralPath $testSandbox) {
    Remove-Item -LiteralPath $testSandbox -Recurse -Force -ErrorAction SilentlyContinue
}
foreach ($d in @($testWallpapers, $testPublished, $testLogs)) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}

# Create a sample valid image
$sampleImgPath = Join-Path $testWallpapers "secure_sample.png"
$pngHeader = [byte[]]@(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D)
[System.IO.File]::WriteAllBytes($sampleImgPath, $pngHeader)

$authSecret = "client_secret_64_bit_secure_token_12345"
$adminSecret = "admin_super_secret_64_bit_key_987654321"

$cfg = [PSCustomObject]@{
    Server = [PSCustomObject]@{
        BindAddress           = "127.0.0.1"
        Port                  = $TestPort
        DiscoveryPort         = 8798
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

# Start Host Process
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

    Assert-Condition "Security Test Host Instance Initialized" ($isReady -eq $true)
    if (-not $isReady) { throw "Security test host failed to bind." }

    # ==========================================================================
    # TEST SECTION 1: Path Traversal Vulnerability Testing
    # ==========================================================================
    Write-Host "`n-- Section 1: Path Traversal Attacks --" -ForegroundColor White
    $traversalPayloads = @(
        "..%2f..%2fwindows%2fsystem32%2fcalc.exe",
        "..%5c..%5cwindows%5cwin.ini",
        "....//....//windows/system32/cmd.exe",
        "%2e%2e%2f%2e%2e%2fetc%2fpasswd",
        "secure_sample.png/../../../boot.ini"
    )

    foreach ($payload in $traversalPayloads) {
        $attackUri = "$baseUrl/api/v1/wallpaper/$payload"
        $statusCode = 0
        try {
            $req = [System.Net.HttpWebRequest]::Create($attackUri)
            $req.Headers.Add("X-Auth-Token", $authSecret)
            $resp = $req.GetResponse()
            $statusCode = [int]$resp.StatusCode
            $resp.Close()
        }
        catch [System.Net.WebException] {
            if ($null -ne $_.Exception.Response) {
                $statusCode = [int]($_.Exception.Response.StatusCode)
            }
        }

        # Successful security protection returns 400 Bad Request or 403 Forbidden or 404
        $blocked = ($statusCode -in @(400, 403, 404))
        Assert-Condition "Path Traversal Blocked for: $payload (HTTP $statusCode)" $blocked
    }

    # ==========================================================================
    # TEST SECTION 2: Authentication & Header Evasion
    # ==========================================================================
    Write-Host "`n-- Section 2: Authentication Bypass Attempts --" -ForegroundColor White

    # 1. Manifest without token
    $statusNoToken = 0
    try {
        Invoke-RestMethod -Uri "$baseUrl/api/v1/manifest" -ErrorAction Stop
    } catch {
        $statusNoToken = $_.Exception.Response.StatusCode.value__
    }
    Assert-Condition "Manifest request without authentication rejected (HTTP 401)" ($statusNoToken -eq 401)

    # 2. Manifest with spoofed token
    $statusForged = 0
    try {
        Invoke-RestMethod -Uri "$baseUrl/api/v1/manifest" -Headers @{ "X-Auth-Token" = "forged_random_key_00000" } -ErrorAction Stop
    } catch {
        $statusForged = $_.Exception.Response.StatusCode.value__
    }
    Assert-Condition "Manifest request with invalid token rejected (HTTP 401)" ($statusForged -eq 401)

    # 3. Wallpaper stream without token
    $statusWpNoToken = 0
    try {
        $req = [System.Net.HttpWebRequest]::Create("$baseUrl/api/v1/wallpaper/secure_sample.png")
        $resp = $req.GetResponse()
        $resp.Close()
    } catch [System.Net.WebException] {
        if ($null -ne $_.Exception.Response) {
            $statusWpNoToken = [int]($_.Exception.Response.StatusCode)
        }
    }
    Assert-Condition "Asset stream request without token rejected (HTTP 401)" ($statusWpNoToken -eq 401)

    # ==========================================================================
    # TEST SECTION 3: Role-Based Access Control (RBAC) Escalation
    # ==========================================================================
    Write-Host "`n-- Section 3: RBAC Privilege Escalation Testing --" -ForegroundColor White

    # 1. Client Token attempting to access Admin Client Roster
    $statusAdminClients = 0
    try {
        Invoke-RestMethod -Uri "$baseUrl/api/v1/admin/clients" -Headers @{ "X-Auth-Token" = $authSecret } -ErrorAction Stop
    } catch {
        $statusAdminClients = $_.Exception.Response.StatusCode.value__
    }
    Assert-Condition "Client role accessing /api/v1/admin/clients forbidden (HTTP 403)" ($statusAdminClients -eq 403)

    # 2. Client Token attempting to trigger Admin Force Sync
    $statusAdminSync = 0
    try {
        Invoke-RestMethod -Uri "$baseUrl/api/v1/admin/sync" -Method Post -Headers @{ "X-Auth-Token" = $authSecret } -ErrorAction Stop
    } catch {
        $statusAdminSync = $_.Exception.Response.StatusCode.value__
    }
    Assert-Condition "Client role triggering /api/v1/admin/sync forbidden (HTTP 403)" ($statusAdminSync -eq 403)

    # 3. Valid Admin Token on Admin Endpoints
    $adminClientsResp = Invoke-RestMethod -Uri "$baseUrl/api/v1/admin/clients" -Headers @{ "Authorization" = "Bearer $adminSecret" }
    Assert-Condition "Admin role accessing /api/v1/admin/clients permitted (HTTP 200)" ($adminClientsResp.totalClients -ge 0)

    # ==========================================================================
    # TEST SECTION 4: Zero Information & Secret Leakage Verification
    # ==========================================================================
    Write-Host "`n-- Section 4: Information Leakage & Secret Exposure Defense --" -ForegroundColor White

    # 1. Health Probe Must Not Leak Filesystem Paths
    $healthProbe = Invoke-RestMethod -Uri "$baseUrl/api/v1/health"
    $hasConfigPathLeak = ($null -ne $healthProbe.PSObject.Properties['loadedConfigPath'])
    $hasPublishedDirLeak = ($null -ne $healthProbe.PSObject.Properties['publishedDir'])
    Assert-Condition "Health endpoint does not expose loadedConfigPath" (-not $hasConfigPathLeak)
    Assert-Condition "Health endpoint does not expose publishedDir" (-not $hasPublishedDirLeak)

    # 2. Registration Endpoint Must Never Return AuthSecret
    $regBody = @{ hostname = "TEST-PC-SEC"; clientVersion = "1.0.0" } | ConvertTo-Json
    $regResp = Invoke-RestMethod -Uri "$baseUrl/api/v1/auth/register" -Method Post -Headers @{ "X-Auth-Token" = $authSecret } -Body $regBody -ContentType "application/json"
    $hasTokenLeak = ($null -ne $regResp.PSObject.Properties['token'])
    Assert-Condition "Registration response does NOT leak auth token" (-not $hasTokenLeak)
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
Write-Host " SECURITY TESTS COMPLETE: $passCount Passed, $failCount Failed" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Red" })
Write-Host "==============================================================================" -ForegroundColor Cyan

if ($failCount -gt 0) { exit 1 } else { exit 0 }
