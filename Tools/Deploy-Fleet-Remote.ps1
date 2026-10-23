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

Write-Host "Initiating remote push to $($targetList.Count) client workstations..." -ForegroundColor Cyan
Write-Host ""

$remoteCommand = [scriptblock]::Create("irm http://$HostIp`:$HostPort/setup | iex")

$successCount = 0
$failCount = 0

foreach ($target in $targetList) {
    Write-Host "[$target] Connecting via PowerShell Remoting..." -NoNewline
    try {
        $pParams = @{
            ComputerName = $target
            ScriptBlock  = $remoteCommand
            ErrorAction  = 'Stop'
        }
        if ($null -ne $Credential) {
            $pParams["Credential"] = $Credential
        }
        Invoke-Command @pParams | Out-Null
        Write-Host " [SUCCESS]" -ForegroundColor Green
        $successCount++
    }
    catch {
        Write-Host " [FAILED: $($_.Exception.Message)]" -ForegroundColor Red
        $failCount++
    }
}

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host " Deployment Complete: $successCount succeeded, $failCount failed." -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green
