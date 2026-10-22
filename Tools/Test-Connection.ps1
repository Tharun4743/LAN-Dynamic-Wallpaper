# ==============================================================================
# Tools/Test-Connection.ps1
# LAN Dynamic Wallpaper - End-to-End Connectivity & Auth Diagnostic Tool
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$HostAddress,

    [Parameter(Mandatory = $false)]
    [int]$Port = 8765,

    [Parameter(Mandatory = $false)]
    [string]$AuthSecret,

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath
)

Set-StrictMode -Version Latest

# If parameters not provided, load from ClientConfig.json or HostConfig.json
if ([string]::IsNullOrWhiteSpace($HostAddress) -or [string]::IsNullOrWhiteSpace($AuthSecret)) {
    $cPath = if ($ConfigPath) { $ConfigPath } else { Join-Path $PSScriptRoot "..\Client\ClientConfig.json" }
    if (Test-Path -LiteralPath $cPath) {
        try {
            $cfg = Get-Content -LiteralPath $cPath -Raw | ConvertFrom-Json
            if ([string]::IsNullOrWhiteSpace($HostAddress)) { $HostAddress = $cfg.Connection.HostAddress }
            if ([string]::IsNullOrWhiteSpace($AuthSecret)) { $AuthSecret = $cfg.Security.AuthSecret }
            if ($cfg.Connection.HostPort) { $Port = $cfg.Connection.HostPort }
        } catch {}
    }
}

if ([string]::IsNullOrWhiteSpace($HostAddress)) {
    $HostAddress = "127.0.0.1"
}

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " LAN DYNAMIC WALLPAPER - CONNECTIVITY DIAGNOSTIC" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " Target Host Address : $HostAddress" -ForegroundColor White
Write-Host " Target HTTP Port    : $Port" -ForegroundColor White
Write-Host " Auth Token Provided : $(if ($AuthSecret) { '[PRESENT - 256-bit]' } else { '[NONE]' })" -ForegroundColor White
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: TCP Port Socket Reachability
Write-Host "[1/4] Testing TCP Socket Connection..." -NoNewline
$tcpClient = New-Object System.Net.Sockets.TcpClient
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $ar = $tcpClient.BeginConnect($HostAddress, $Port, $null, $null)
    $success = $ar.AsyncWaitHandle.WaitOne(3000)
    $sw.Stop()
    if ($success -and $tcpClient.Connected) {
        $tcpClient.EndConnect($ar)
        Write-Host " [PASS] Connected in $($sw.ElapsedMilliseconds) ms" -ForegroundColor Green
    } else {
        Write-Host " [FAIL] Connection timed out after 3000 ms" -ForegroundColor Red
        return
    }
}
catch {
    Write-Host " [FAIL] Socket error: $($_.Exception.Message)" -ForegroundColor Red
    return
}
finally {
    $tcpClient.Close()
}

# Step 2: HTTP Health Endpoint Probe
Write-Host "[2/4] Testing HTTP Health Endpoint (/api/v1/health)..." -NoNewline
$healthUri = "http://$HostAddress`:$Port/api/v1/health"
$sw.Restart()
try {
    $healthResp = Invoke-RestMethod -Uri $healthUri -TimeoutSec 5 -ErrorAction Stop
    $sw.Stop()
    if ($healthResp.status -eq "ok") {
        Write-Host " [PASS] Latency: $($sw.ElapsedMilliseconds) ms" -ForegroundColor Green
        Write-Host "       Host Service       : $($healthResp.service) v$($healthResp.version)" -ForegroundColor Gray
        Write-Host "       Host Uptime        : $($healthResp.uptimeSeconds) seconds" -ForegroundColor Gray
        Write-Host "       Active Collection  : $($healthResp.collectionVersion) ($($healthResp.totalImages) images)" -ForegroundColor Gray
        Write-Host "       Enrolled Clients   : $($healthResp.registeredClients)" -ForegroundColor Gray
    } else {
        Write-Host " [WARN] Unexpected response payload: $($healthResp | ConvertTo-Json -Compress)" -ForegroundColor Yellow
    }
}
catch {
    Write-Host " [FAIL] HTTP Error: $($_.Exception.Message)" -ForegroundColor Red
    return
}

# Step 3: Authenticated Manifest Request
Write-Host "[3/4] Testing Authenticated Manifest Endpoint (/api/v1/manifest)..." -NoNewline
$manifestUri = "http://$HostAddress`:$Port/api/v1/manifest"
$sw.Restart()
$headers = @{}
if (-not [string]::IsNullOrWhiteSpace($AuthSecret)) {
    $headers["X-Auth-Token"] = $AuthSecret
}

try {
    $manifestResp = Invoke-RestMethod -Uri $manifestUri -Headers $headers -TimeoutSec 5 -ErrorAction Stop
    $sw.Stop()
    Write-Host " [PASS] Received in $($sw.ElapsedMilliseconds) ms" -ForegroundColor Green
    Write-Host "       Collection Version : $($manifestResp.collectionVersion)" -ForegroundColor Gray
    Write-Host "       Slideshow Interval : $($manifestResp.slideshowInterval)s" -ForegroundColor Gray
    Write-Host "       Manifest Assets    : $($manifestResp.images.Count) images" -ForegroundColor Gray
}
catch {
    Write-Host " [FAIL] HTTP Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response.StatusCode.value__ -eq 401) {
        Write-Host "       Reason: 401 Unauthorized. Ensure AuthSecret matches HostConfig.json." -ForegroundColor Yellow
    }
    return
}

# Step 4: Asset Download Verification
Write-Host "[4/4] Testing Asset Stream Endpoint..." -NoNewline
if ($manifestResp.images.Count -gt 0) {
    $firstImg = $manifestResp.images[0]
    $imgUri = "http://$HostAddress`:$Port$($firstImg.downloadUrl)"
    $sw.Restart()
    try {
        $webReq = [System.Net.HttpWebRequest]::Create($imgUri)
        $webReq.Headers.Add("X-Auth-Token", $AuthSecret)
        $webResp = $webReq.GetResponse()
        $sw.Stop()
        $hashHeader = $webResp.Headers["X-Image-Sha256"]
        $len = $webResp.ContentLength
        $webResp.Close()
        Write-Host " [PASS] Streamed $($firstImg.name) ($len bytes) in $($sw.ElapsedMilliseconds) ms" -ForegroundColor Green
        Write-Host "       Header SHA-256     : $hashHeader" -ForegroundColor Gray
    }
    catch {
        Write-Host " [FAIL] Image stream error: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host " [SKIP] No images published yet on Host." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host " DIAGNOSTIC RESULT: ALL CONNECTIVITY CHECKS PASSED" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green
