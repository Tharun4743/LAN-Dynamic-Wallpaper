# ==============================================================================
# Tools/Deployment-Report.ps1
# LAN Dynamic Wallpaper - Fleet Telemetry & Deployment Status Reporter
# Monitored fleet management for 30-100 client computers
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$HostAddress,

    [Parameter(Mandatory = $false)]
    [int]$Port = 8765,

    [Parameter(Mandatory = $false)]
    [string]$AdminSecret,

    [Parameter(Mandatory = $false)]
    [string]$ExportCsv,

    [Parameter(Mandatory = $false)]
    [string]$ExportJson
)

Set-StrictMode -Version Latest

# Load AdminSecret from HostConfig.json if not specified
if ([string]::IsNullOrWhiteSpace($AdminSecret)) {
    $cfgPath = Join-Path $PSScriptRoot "..\Host\HostConfig.json"
    if (Test-Path -LiteralPath $cfgPath) {
        try {
            $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
            $AdminSecret = $cfg.Security.AdminSecret
            if ([string]::IsNullOrWhiteSpace($HostAddress)) {
                $HostAddress = "127.0.0.1"
            }
            if ($cfg.Server.Port) { $Port = $cfg.Server.Port }
        } catch {}
    }
}

if ([string]::IsNullOrWhiteSpace($HostAddress)) { $HostAddress = "127.0.0.1" }

if ([string]::IsNullOrWhiteSpace($AdminSecret)) {
    throw "AdminSecret is required to query the fleet management endpoint. Supply -AdminSecret or run on Host PC."
}

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " LAN DYNAMIC WALLPAPER - FLEET DEPLOYMENT REPORT (30-100 PCs)" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " Host Server: http://$HostAddress`:$Port" -ForegroundColor Gray
Write-Host " Generated  : $([DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) UTC" -ForegroundColor Gray
Write-Host ""

$endpoint = "http://$HostAddress`:$Port/api/v1/admin/clients"
$headers = @{ "Authorization" = "Bearer $AdminSecret" }

try {
    $response = Invoke-RestMethod -Uri $endpoint -Headers $headers -TimeoutSec 10 -ErrorAction Stop
}
catch {
    Write-Error "Failed to fetch deployment report: $($_.Exception.Message)"
    if ($_.Exception.Response.StatusCode.value__ -eq 403) {
        Write-Host "Error 403: Provided token does not have Administrator privileges." -ForegroundColor Red
    }
    return
}

$clients = $response.clients
$total = $response.totalClients
$onlineCount = ($clients | Where-Object { $_.status -eq "ONLINE" }).Count
$staleCount  = ($clients | Where-Object { $_.status -eq "STALE" }).Count
$offlineCount = ($clients | Where-Object { $_.status -eq "OFFLINE" }).Count

Write-Host " FLEET SUMMARY METRICS" -ForegroundColor White
Write-Host " ------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  Total Registered Clients : $total" -ForegroundColor White
Write-Host "  Active / Online ( <45s ) : $onlineCount" -ForegroundColor Green
Write-Host "  Stale Telemetry ( <180s) : $staleCount" -ForegroundColor Yellow
Write-Host "  Offline Clients          : $offlineCount" -ForegroundColor Red
Write-Host ""

if ($total -gt 0) {
    Write-Host " CLIENT ROSTER MATRIX" -ForegroundColor White
    Write-Host " ------------------------------------------------------------" -ForegroundColor DarkGray
    
    $displayRows = @()
    foreach ($c in $clients) {
        $hashSnippet = if ($c.currentHash) { $c.currentHash.Substring(0, [Math]::Min(10, $c.currentHash.Length)) + "..." } else { "[SYNCING]" }
        $displayRows += [PSCustomObject]@{
            "Client ID"   = $c.clientId
            "Hostname"    = $c.hostname
            "IP Address"  = $c.ipAddress
            "Status"      = $c.status
            "Last Seen"   = "$($c.secondsAgo)s ago"
            "Active Hash" = $hashSnippet
        }
    }

    $displayRows | Format-Table -AutoSize
} else {
    Write-Host "  No client nodes currently registered in Host fleet database." -ForegroundColor Yellow
}

# Optional Exports
if (-not [string]::IsNullOrWhiteSpace($ExportCsv)) {
    $clients | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Report exported to CSV: $ExportCsv" -ForegroundColor Green
}
if (-not [string]::IsNullOrWhiteSpace($ExportJson)) {
    $clients | ConvertTo-Json -Depth 4 | Out-File -FilePath $ExportJson -Encoding UTF8
    Write-Host "Report exported to JSON: $ExportJson" -ForegroundColor Green
}

Write-Host "==============================================================================" -ForegroundColor Cyan
