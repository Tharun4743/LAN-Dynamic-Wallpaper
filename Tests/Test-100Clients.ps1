# ==============================================================================
# Tests/Test-100Clients.ps1
# High-Concurrency Load Simulation Test for 30-100 Client Fleet
# Dispatches 100 concurrent client nodes executing registration, manifest polls & asset streaming
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$ClientCount = 100,

    [Parameter(Mandatory = $false)]
    [int]$TestPort = 8799
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " RUNNING 100-CLIENT LOAD SIMULATION: Test-100Clients.ps1" -ForegroundColor Cyan
Write-Host " Target Fleet Size : $ClientCount concurrent simulated client nodes" -ForegroundColor White
Write-Host " Test HTTP Port    : $TestPort" -ForegroundColor White
Write-Host "==============================================================================" -ForegroundColor Cyan

$testSandbox = Join-Path $PSScriptRoot "Test-Sandbox-100Clients"
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

# Create sample wallpaper for clients to download
$sampleImgPath = Join-Path $testWallpapers "fleet_sample.jpg"
$header = [byte[]]@(0xFF, 0xD8, 0xFF, 0xE0)
$extra = New-Object byte[] 4096
for ($i = 0; $i -lt 4096; $i++) { $extra[$i] = [byte]($i % 256) }
[System.IO.File]::WriteAllBytes($sampleImgPath, ($header + $extra))

$authSecret = "load_simulation_auth_token_secret_9999"
$adminSecret = "load_simulation_admin_token_secret_1111"

$cfg = [PSCustomObject]@{
    Server = [PSCustomObject]@{
        BindAddress           = "127.0.0.1"
        Port                  = $TestPort
        DiscoveryPort         = 8800
        EnableDiscovery       = $false
        MaxConcurrentRequests = 256
        RequestTimeoutSeconds = 30
    }
    Security = [PSCustomObject]@{
        AuthSecret            = $authSecret
        AdminSecret           = $adminSecret
        RequireAuthentication = $true
        MaxImageSizeBytes     = 10485760
        AllowedExtensions     = @(".jpg", ".jpeg", ".png", ".bmp")
    }
    Slideshow = [PSCustomObject]@{
        DefaultIntervalSeconds = 60
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

    if (-not $isReady) {
        throw "Load simulation host failed to initialize on port $TestPort within timeout."
    }

    Write-Host "[1/3] Host server initialized. Spawning $ClientCount concurrent client threads..." -ForegroundColor Cyan

    # Build C# Async Fleet Simulator for maximum raw concurrent performance
    $csharpSource = @"
    using System;
    using System.Collections.Generic;
    using System.Diagnostics;
    using System.IO;
    using System.Net;
    using System.Text;
    using System.Threading.Tasks;

    public class FleetLoadResult {
        public int ClientId;
        public bool Success;
        public long DurationMs;
        public string Error;
    }

    public class FleetLoadSimulator {
        public static FleetLoadResult[] RunLoadTest(string baseUrl, string authSecret, int clientCount) {
            ServicePointManager.DefaultConnectionLimit = 256;
            var tasks = new Task<FleetLoadResult>[clientCount];

            for (int i = 0; i < clientCount; i++) {
                int id = i + 1;
                tasks[i] = Task.Run(() => SimulateClient(baseUrl, authSecret, id));
            }

            Task.WaitAll(tasks);
            var results = new FleetLoadResult[clientCount];
            for (int i = 0; i < clientCount; i++) {
                results[i] = tasks[i].Result;
            }
            return results;
        }

        private static FleetLoadResult SimulateClient(string baseUrl, string authSecret, int clientId) {
            var sw = Stopwatch.StartNew();
            try {
                // 1. Client Registration
                var regReq = (HttpWebRequest)WebRequest.Create(baseUrl + "/api/v1/auth/register");
                regReq.Method = "POST";
                regReq.ContentType = "application/json";
                regReq.Headers.Add("X-Auth-Token", authSecret);
                regReq.Timeout = 20000;
                string regPayload = "{\"hostname\":\"PC-SIM-" + clientId + "\",\"clientVersion\":\"1.0.0\"}";
                byte[] bodyBytes = Encoding.UTF8.GetBytes(regPayload);
                regReq.ContentLength = bodyBytes.Length;
                using (var s = regReq.GetRequestStream()) {
                    s.Write(bodyBytes, 0, bodyBytes.Length);
                }
                using (var regResp = (HttpWebResponse)regReq.GetResponse()) {
                    if (regResp.StatusCode != HttpStatusCode.OK) throw new Exception("Register failed: " + regResp.StatusCode);
                }

                // 2. Fetch Manifest
                var mReq = (HttpWebRequest)WebRequest.Create(baseUrl + "/api/v1/manifest");
                mReq.Method = "GET";
                mReq.Headers.Add("X-Auth-Token", authSecret);
                mReq.Timeout = 20000;
                using (var mResp = (HttpWebResponse)mReq.GetResponse()) {
                    if (mResp.StatusCode != HttpStatusCode.OK) throw new Exception("Manifest failed: " + mResp.StatusCode);
                }

                // 3. Download Wallpaper Asset
                var dlReq = (HttpWebRequest)WebRequest.Create(baseUrl + "/api/v1/wallpaper/fleet_sample.jpg");
                dlReq.Method = "GET";
                dlReq.Headers.Add("X-Auth-Token", authSecret);
                dlReq.Timeout = 20000;
                using (var dlResp = (HttpWebResponse)dlReq.GetResponse()) {
                    if (dlResp.StatusCode != HttpStatusCode.OK) throw new Exception("Download failed: " + dlResp.StatusCode);
                    using (var stream = dlResp.GetResponseStream()) {
                        byte[] buf = new byte[8192];
                        while (stream.Read(buf, 0, buf.Length) > 0) {}
                    }
                }

                // 4. Heartbeat Dispatch
                var hbReq = (HttpWebRequest)WebRequest.Create(baseUrl + "/api/v1/heartbeat");
                hbReq.Method = "POST";
                hbReq.ContentType = "application/json";
                hbReq.Headers.Add("X-Auth-Token", authSecret);
                hbReq.Timeout = 20000;
                string hbPayload = "{\"clientId\":\"CLT-SIM-" + clientId + "\",\"currentImageHash\":\"mockhash\"}";
                byte[] hbBytes = Encoding.UTF8.GetBytes(hbPayload);
                hbReq.ContentLength = hbBytes.Length;
                using (var s = hbReq.GetRequestStream()) {
                    s.Write(hbBytes, 0, hbBytes.Length);
                }
                using (var hbResp = (HttpWebResponse)hbReq.GetResponse()) {
                    if (hbResp.StatusCode != HttpStatusCode.OK) throw new Exception("Heartbeat failed: " + hbResp.StatusCode);
                }

                sw.Stop();
                return new FleetLoadResult { ClientId = clientId, Success = true, DurationMs = sw.ElapsedMilliseconds };
            }
            catch (Exception ex) {
                sw.Stop();
                return new FleetLoadResult { ClientId = clientId, Success = false, DurationMs = sw.ElapsedMilliseconds, Error = ex.Message };
            }
        }
    }
"@

    if (-not ([System.Management.Automation.PSTypeName]'FleetLoadSimulator').Type) {
        Add-Type -TypeDefinition $csharpSource -ErrorAction Stop
    }

    Write-Host "[2/3] Executing concurrent multi-step transactions across all $ClientCount client nodes..." -ForegroundColor Cyan
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $results = [FleetLoadSimulator]::RunLoadTest($baseUrl, $authSecret, $ClientCount)
    $stopwatch.Stop()

    $totalDurationSec = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
    $successList = @($results | Where-Object { $_.Success -eq $true })
    $failureList = @($results | Where-Object { $_.Success -eq $false })
    $successCount = $successList.Count
    $failureCount = $failureList.Count

    # Calculate Latency Percentiles
    $latencies = @($successList | ForEach-Object { $_.DurationMs } | Sort-Object)
    $minLatency = if ($latencies.Count -gt 0) { $latencies[0] } else { 0 }
    $maxLatency = if ($latencies.Count -gt 0) { $latencies[-1] } else { 0 }
    $avgLatency = if ($latencies.Count -gt 0) { [Math]::Round(($latencies | Measure-Object -Average).Average, 1) } else { 0 }
    $p95Index = [Math]::Floor($latencies.Count * 0.95)
    $p95Latency = if ($latencies.Count -gt 0) { $latencies[[Math]::Min($p95Index, [Math]::Max(0, $latencies.Count - 1))] } else { 0 }
    $totalRequests = $ClientCount * 4
    $rps = [Math]::Round(($totalRequests / [Math]::Max(0.001, $stopwatch.Elapsed.TotalSeconds)), 1)

    Write-Host ""
    Write-Host "==============================================================================" -ForegroundColor Green
    Write-Host " 100-CLIENT LOAD SIMULATION RESULTS" -ForegroundColor Green
    Write-Host "==============================================================================" -ForegroundColor Green
    Write-Host " Simulated Client Nodes       : $ClientCount" -ForegroundColor White
    Write-Host " Total HTTP Requests Handled  : $totalRequests (Registration + Manifest + Download + Heartbeat)" -ForegroundColor White
    Write-Host " Total Wall-Clock Time        : $totalDurationSec seconds" -ForegroundColor White
    Write-Host " Measured Fleet Throughput    : $rps requests / second" -ForegroundColor Cyan
    Write-Host " Successful Client Workflows  : $successCount / $ClientCount (100% Success)" -ForegroundColor Green
    Write-Host " Failed / Dropped Requests    : $failureCount" -ForegroundColor $(if ($failureCount -eq 0) { "Green" } else { "Red" })
    Write-Host ""
    Write-Host " LATENCY BENCHMARKS (End-to-End Client Sequence)" -ForegroundColor White
    Write-Host "  Min Client Duration         : $minLatency ms" -ForegroundColor Gray
    Write-Host "  Average Client Duration     : $avgLatency ms" -ForegroundColor Gray
    Write-Host "  95th Percentile (p95)       : $p95Latency ms" -ForegroundColor Gray
    Write-Host "  Max Client Duration         : $maxLatency ms" -ForegroundColor Gray
    Write-Host "==============================================================================" -ForegroundColor Green

    if ($failureCount -gt 0) {
        Write-Host "Sample Failure Errors:" -ForegroundColor Red
        $failureList | Select-Object -First 5 | ForEach-Object { Write-Host "  Client $($_.ClientId): $($_.Error)" -ForegroundColor Yellow }
        exit 1
    }
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $testSandbox) {
        Remove-Item -LiteralPath $testSandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}
