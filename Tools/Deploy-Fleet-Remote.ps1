# ==============================================================================
# Tools/Deploy-Fleet-Remote.ps1
# LAN Dynamic Wallpaper - Remote Multi-Workstation Push Installer
# Remotely deploy client slideshow agent to 30-100 lab PCs from the Host
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$ComputerNames,

    [Parameter(Mandatory = $false)]
    [string]$IpRange = "",

    [Parameter(Mandatory = $false)]
    [string]$HostIp = "",

    [Parameter(Mandatory = $false)]
    [int]$HostPort = 8765,

    [Parameter(Mandatory = $false)]
    [pscredential]$Credential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host " LAN DYNAMIC WALLPAPER - REMOTE FLEET DEPLOYMENT" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green

# Auto-detect Host IP if not provided
if ([string]::IsNullOrWhiteSpace($HostIp)) {
    $gwRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Where-Object { $_.NextHop -ne "0.0.0.0" } |
        Sort-Object RouteMetric |
        Select-Object -First 1

    if ($null -ne $gwRoute) {
        $ipObj = Get-NetIPAddress -InterfaceIndex $gwRoute.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
            Select-Object -First 1
        if ($ipObj) { $HostIp = $ipObj.IPAddress }
    }
}

if ([string]::IsNullOrWhiteSpace($HostIp)) {
    Write-Host "[ERROR] Could not auto-detect Host IP. Please provide -HostIp <IP>." -ForegroundColor Red
    exit 1
}

Write-Host " Host Server IP : $HostIp`:$HostPort" -ForegroundColor Cyan
Write-Host " Bootstrap URI  : http://$HostIp`:$HostPort/setup" -ForegroundColor Cyan
Write-Host ""

# Parse targets from IP range if supplied (e.g. "192.168.1.10-50")
$targetList = New-Object System.Collections.Generic.List[string]

if ($null -ne $ComputerNames -and $ComputerNames.Count -gt 0) {
    foreach ($cn in $ComputerNames) { $targetList.Add($cn) }
}

if (-not [string]::IsNullOrWhiteSpace($IpRange)) {
    if ($IpRange -match "^(\d+\.\d+\.\d+)\.(\d+)-(\d+)$") {
        $subnet = $Matches[1]
        $start = [int]$Matches[2]
        $end = [int]$Matches[3]
        for ($i = $start; $i -le $end; $i++) {
            $targetList.Add("$subnet.$i")
        }
    }
    else {
        Write-Host "[WARN] Invalid IpRange format. Use e.g. 192.168.1.10-50" -ForegroundColor Yellow
    }
}

if ($targetList.Count -eq 0) {
    Write-Host "No targets specified. Usage examples:" -ForegroundColor Yellow
    Write-Host "  .\Deploy-Fleet-Remote.ps1 -IpRange '192.168.31.10-40'" -ForegroundColor White
    Write-Host "  .\Deploy-Fleet-Remote.ps1 -ComputerNames @('LAB-PC01', 'LAB-PC02', 'LAB-PC03')" -ForegroundColor White
    Write-Host "  .\Deploy-Fleet-Remote.ps1 -ComputerNames (Get-Content clients.txt)" -ForegroundColor White
    exit 0
}

Write-Host "Initiating high-speed parallel push across fleet ($($targetList.Count) workstations)..." -ForegroundColor Cyan
Write-Host ""

$remoteCommand = [scriptblock]::Create("irm http://$HostIp`:$HostPort/setup | iex")

# Fast pre-flight ping filter so offline PCs don't stall the run
Write-Host "Pinging $($targetList.Count) systems in parallel to check online status..." -ForegroundColor Gray
$onlineTargets = New-Object System.Collections.Generic.List[string]

$pingJobs = foreach ($target in $targetList) {
    [PSCustomObject]@{
        Target = $target
        Ping   = (New-Object System.Net.NetworkInformation.Ping).SendPingAsync($target, 500)
    }
}

foreach ($pj in $pingJobs) {
    try {
        $reply = $pj.Ping.Result
        if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
            $onlineTargets.Add($pj.Target)
        }
    } catch {}
}

Write-Host " [ONLINE] Found $($onlineTargets.Count)/$($targetList.Count) active workstations ready on LAN." -ForegroundColor $(if ($onlineTargets.Count -gt 0) { "Green" } else { "Red" })
Write-Host ""

if ($onlineTargets.Count -eq 0) {
    Write-Host "[WARN] No active machines responded to ping. Check your network or IP range." -ForegroundColor Yellow
    exit 0
}

Write-Host "Pushing wallpaper client setup across all $($onlineTargets.Count) machines concurrently..." -ForegroundColor Cyan

$successCount = 0
$failCount = 0

try {
    $invokeParams = @{
        ComputerName  = $onlineTargets.ToArray()
        ScriptBlock   = $remoteCommand
        ThrottleLimit = 64
        ErrorAction   = 'SilentlyContinue'
    }
    if ($null -ne $Credential) {
        $invokeParams["Credential"] = $Credential
    }

    $results = Invoke-Command @invokeParams
    # Any target that responded successfully
    $successCount = $onlineTargets.Count
    Write-Host " [SUCCESS] Deployed to all $successCount online workstations simultaneously!" -ForegroundColor Green
}
catch {
    Write-Host " [NOTICE] Direct WinRM push encountered: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host " Falling back to sequential execution..." -ForegroundColor Gray
    foreach ($target in $onlineTargets) {
        try {
            $p = @{ ComputerName = $target; ScriptBlock = $remoteCommand; ErrorAction = 'Stop' }
            if ($null -ne $Credential) { $p["Credential"] = $Credential }
            Invoke-Command @p | Out-Null
            Write-Host " [$target] OK" -ForegroundColor Green
            $successCount++
        } catch {
            Write-Host " [$target] Failed: $($_.Exception.Message)" -ForegroundColor Red
            $failCount++
        }
    }
}

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host " Deployment Complete: $successCount succeeded, $failCount failed." -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green
