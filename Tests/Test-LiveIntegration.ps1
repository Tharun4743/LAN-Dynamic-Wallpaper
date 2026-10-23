# ==============================================================================
# Tests/Test-LiveIntegration.ps1
# Comprehensive End-to-End Live Calling & Logic Verification
# Pure Windows PowerShell 5.1+ - Tests full caller flow and dynamic reload
# ==============================================================================

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$testPort = 8793
$discPort = 8794
$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $testRoot ".."))
$sandbox = Join-Path $testRoot "Test-Sandbox-Live"
$wallpapersDir = Join-Path $sandbox "Wallpapers"
$logsDir = Join-Path $sandbox "Logs"
$cfgPath = Join-Path $sandbox "HostConfig.json"

if (Test-Path -LiteralPath $sandbox) {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
foreach ($d in @($sandbox, $wallpapersDir, $logsDir)) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}

$testPassed = 0
$testFailed = 0

function Assert-Live {
    param([string]$Name, [bool]$Condition, [string]$Details = "")
    if ($Condition) {
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $script:testPassed++
    } else {
        Write-Host "  [FAIL] $Name - $Details" -ForegroundColor Red
        $script:testFailed++
    }
}

# Create dummy test image
$sampleImg = Join-Path $wallpapersDir "live_sample.bmp"
$bmpHeader = New-Object byte[] 58
$bmpHeader[0] = 0x42; $bmpHeader[1] = 0x4D # BM
$bmpHeader[2] = 58; $bmpHeader[10] = 54; $bmpHeader[14] = 40
$bmpHeader[18] = 1; $bmpHeader[22] = 1; $bmpHeader[26] = 1; $bmpHeader[28] = 24
[System.IO.File]::WriteAllBytes($sampleImg, $bmpHeader)

# Initial HostConfig
$initCfg = [PSCustomObject]@{
    Server = [PSCustomObject]@{
        BindAddress = "127.0.0.1"
        Port = $testPort
        DiscoveryPort = $discPort
        EnableDiscovery = $false
        MaxConcurrentRequests = 32
        RequestTimeoutSeconds = 10
    }
    Security = [PSCustomObject]@{
        AuthSecret = "LIVE_TEST_SECRET_KEY"
        AdminSecret = "LIVE_TEST_ADMIN_KEY"
        RequireAuthentication = $true
        AutoEnrollLanClients = $true
        MaxImageSizeBytes = 52428800
        AllowedExtensions = @(".jpg", ".jpeg", ".png", ".bmp")
    }
    Slideshow = [PSCustomObject]@{
        DefaultIntervalSeconds = 7
    }
    Paths = [PSCustomObject]@{
        WallpapersDir = "./Wallpapers"
        PublishedDir = "./Wallpapers"
        LogsDir = "./Logs"
        ClientsStore = "./clients.json"
    }
}
[System.IO.File]::WriteAllText($cfgPath, ($initCfg | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " RUNNING LIVE INTEGRATION & CALLING VERIFICATION TEST (Port $testPort)" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan

# Start Host in background process
$hostScript = Join-Path $projectRoot "Host\Host.ps1"
$proc = Start-Process powershell.exe -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $hostScript,
    "-ConfigPath", $cfgPath,
    "-Port", $testPort,
    "-NoLocalSlideshow"
) -PassThru

try {
    # 1. Wait for server readiness
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 250
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $tcp.Connect("127.0.0.1", $testPort)
            $tcp.Close()
            $ready = $true
            break
        } catch {}
    }
    Assert-Live "Live Host Server initialized and listening on port $testPort" $ready

    # 2. Test GET / (Web Setup Portal)
    Write-Host "`n-- Section 1: Web Setup Portal Calling Logic --" -ForegroundColor White
    $webResp = Invoke-WebRequest -Uri "http://127.0.0.1:$testPort/" -UseBasicParsing -TimeoutSec 5
    Assert-Live "GET / returns HTTP 200 OK" ($webResp.StatusCode -eq 200)
    Assert-Live "GET / contains HTML setup portal" ($webResp.Content -like "*<!DOCTYPE html>*" -and $webResp.Content -like "*Connect This Computer*")

    # 3. Test GET /3-Client-Download-Start.bat with dynamic IP injection
    Write-Host "`n-- Section 2: Dynamic Batch File Serving Logic --" -ForegroundColor White
    $batResp = Invoke-WebRequest -Uri "http://127.0.0.1:$testPort/3-Client-Download-Start.bat" -UseBasicParsing -TimeoutSec 5
    Assert-Live "GET /3-Client-Download-Start.bat returns HTTP 200" ($batResp.StatusCode -eq 200)
    $batText = [System.Text.Encoding]::ASCII.GetString($batResp.RawContentStream.ToArray())
    $hasInjectedIp = ($batText -match 'set "SERVER_OVERRIDE=\S+"' -or $batText -match 'HOST_IP' -or $batText -match 'SHARE_NAME')
    Assert-Live "Downloaded batch file references host discovery" $hasInjectedIp

    # 4. Test GET /setup (1-Click bootstrap script)
    Write-Host "`n-- Section 3: Client Bootstrap Calling Logic --" -ForegroundColor White
    $setupResp = Invoke-WebRequest -Uri "http://127.0.0.1:$testPort/setup" -UseBasicParsing -TimeoutSec 5
    Assert-Live "GET /setup returns HTTP 200" ($setupResp.StatusCode -eq 200)
    Assert-Live "GET /setup returns valid PowerShell bootstrap payload" ($setupResp.Content -like "*Start-Process powershell.exe*")

    # 5. Test GET /client/ClientConfig.json provisioning
    Write-Host "`n-- Section 4: Client Provisioning Assets Calling Logic --" -ForegroundColor White
    $clientCfgResp = Invoke-WebRequest -Uri "http://127.0.0.1:$testPort/client/ClientConfig.json" -UseBasicParsing -TimeoutSec 5
    Assert-Live "GET /client/ClientConfig.json returns HTTP 200" ($clientCfgResp.StatusCode -eq 200)
    $parsedClientCfg = $clientCfgResp.Content | ConvertFrom-Json
    Assert-Live "Provisioned ClientConfig reflects Host port $testPort" ($parsedClientCfg.Connection.HostPort -eq $testPort)
    Assert-Live "Provisioned ClientConfig reflects initial interval 7s" ($parsedClientCfg.Slideshow.IntervalSeconds -eq 7)

    # 6. Test Client Auto-Enrollment (Registration endpoint)
    Write-Host "`n-- Section 5: Client Enrollment & Token Calling Logic --" -ForegroundColor White
    $regBody = @{ hostname = "TEST-NODE-01"; mac = "00-11-22-33-44-55"; clientVersion = "1.0.0" } | ConvertTo-Json
    $regResp = Invoke-WebRequest -Uri "http://127.0.0.1:$testPort/api/v1/auth/register" -Method POST -Body $regBody -ContentType "application/json" -UseBasicParsing
    Assert-Live "POST /api/v1/auth/register returns HTTP 200" ($regResp.StatusCode -eq 200)
    $regData = $regResp.Content | ConvertFrom-Json
    $clientToken = $regData.clientToken
    Assert-Live "Assigned Client ID format (CLT-...)" ($regData.clientId -like "CLT-*")
    Assert-Live "Assigned Client Token format (CLTK-...)" ($clientToken -like "CLTK-*")

    # 7. Test GET /api/v1/manifest with token
    Write-Host "`n-- Section 6: Manifest & Slideshow Interval Calling Logic --" -ForegroundColor White
    $manifestResp = Invoke-WebRequest -Uri "http://127.0.0.1:$testPort/api/v1/manifest" -Headers @{ "X-Auth-Token" = $clientToken } -UseBasicParsing
    Assert-Live "GET /api/v1/manifest returns HTTP 200" ($manifestResp.StatusCode -eq 200)
    $manifestData = $manifestResp.Content | ConvertFrom-Json
    Assert-Live "Manifest contains initial 7s interval" ($manifestData.slideshowInterval -eq 7)
    Assert-Live "Manifest lists published live_sample.bmp" ($manifestData.images.Count -eq 1 -and $manifestData.images[0].name -eq "live_sample.bmp")

    # 8. Test Dynamic Interval Reload without server restart
    Write-Host "`n-- Section 7: Zero-Restart Dynamic Timer Reload Logic --" -ForegroundColor White
    $initCfg.Slideshow.DefaultIntervalSeconds = 14
    [System.IO.File]::WriteAllText($cfgPath, ($initCfg | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)

    # Wait for the Host 2-second reconciliation loop to detect the change
    $updatedIntervalFound = $false
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        Start-Sleep -Seconds 1
        $checkResp = Invoke-WebRequest -Uri "http://127.0.0.1:$testPort/api/v1/manifest" -Headers @{ "X-Auth-Token" = $clientToken } -UseBasicParsing
        $checkData = $checkResp.Content | ConvertFrom-Json
        if ($checkData.slideshowInterval -eq 14) {
            $updatedIntervalFound = $true
            break
        }
    }
    Assert-Live "Host dynamically reloaded interval from 7s to 14s WITHOUT server restart" $updatedIntervalFound

    # 9. Test Binary Asset Streaming with SHA-256 Checksum
    Write-Host "`n-- Section 8: Image Streaming & Checksum Header Logic --" -ForegroundColor White
    $imgUrl = "http://127.0.0.1:$testPort/api/v1/wallpaper/live_sample.bmp"
    $imgResp = Invoke-WebRequest -Uri $imgUrl -Headers @{ "X-Auth-Token" = $clientToken } -UseBasicParsing
    Assert-Live "GET /api/v1/wallpaper/live_sample.bmp returns HTTP 200" ($imgResp.StatusCode -eq 200)
    Assert-Live "X-Image-Sha256 header present in binary stream" (-not [string]::IsNullOrWhiteSpace($imgResp.Headers["X-Image-Sha256"]))

    # 10. Test Client Heartbeat Telemetry
    Write-Host "`n-- Section 9: Client Heartbeat Calling Logic --" -ForegroundColor White
    $hbPayload = @{ clientId = $regData.clientId; currentImageHash = "DUMMY_HASH"; hostname = "TEST-NODE-01" } | ConvertTo-Json
    $hbResp = Invoke-WebRequest -Uri "http://127.0.0.1:$testPort/api/v1/heartbeat" -Method POST -Body $hbPayload -ContentType "application/json" -Headers @{ "X-Auth-Token" = $clientToken } -UseBasicParsing
    Assert-Live "POST /api/v1/heartbeat returns HTTP 200 ACK" ($hbResp.StatusCode -eq 200)
}
finally {
    if ($null -ne $proc -and -not $proc.HasExited) {
        $proc.Kill()
        $proc.WaitForExit(3000)
    }
    if (Test-Path -LiteralPath $sandbox) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " LIVE INTEGRATION TESTS COMPLETE: $testPassed Passed, $testFailed Failed" -ForegroundColor $(if ($testFailed -eq 0) { "Green" } else { "Red" })
Write-Host "==============================================================================" -ForegroundColor Cyan

if ($testFailed -gt 0) { exit 1 } else { exit 0 }
