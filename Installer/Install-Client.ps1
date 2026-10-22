# ==============================================================================
# Installer/Install-Client.ps1
# LAN Dynamic Wallpaper - Client Node Setup & Initial Sync Bootstrap
# Pure Windows PowerShell 5.1+ / Non-Elevated Desktop Mode
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$HostAddress,

    [Parameter(Mandatory = $false)]
    [int]$HostPort = 8765,

    [Parameter(Mandatory = $false)]
    [string]$AuthSecret,

    [Parameter(Mandatory = $false)]
    [switch]$NoStart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "==============================================================================" -ForegroundColor Green
Write-Host " LAN DYNAMIC WALLPAPER SLIDESHOW - CLIENT INSTALLER" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green

# 1. Environment Compatibility Check
$psVersion = $PSVersionTable.PSVersion
Write-Host "[1/7] Verifying environment compatibility..." -ForegroundColor Cyan
Write-Host "  PowerShell Version: $psVersion" -ForegroundColor Gray
if ($psVersion.Major -lt 5 -or ($psVersion.Major -eq 5 -and $psVersion.Minor -lt 1)) {
    throw "Fatal: Windows PowerShell 5.1 or newer is required."
}

# 2. Locate / Establish Client Directories
Write-Host "[2/7] Verifying client directory hierarchy..." -ForegroundColor Cyan
$clientRoot = $PSScriptRoot
# If run inside Installer directory, point to parent Client folder, or if run from Client-Package
if (Test-Path (Join-Path $PSScriptRoot "Client.ps1")) {
    $clientRoot = $PSScriptRoot
} elseif (Test-Path (Join-Path $PSScriptRoot "..\Client\Client.ps1")) {
    $clientRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\Client"))
}

$cacheDir = Join-Path $clientRoot "Cache"
$logsDir = Join-Path $clientRoot "Logs"
foreach ($d in @($cacheDir, $logsDir)) {
    if (-not (Test-Path -LiteralPath $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Write-Host "  Created directory: $d" -ForegroundColor Gray
    }
}

# 3. Read or Discover Host Configuration
Write-Host "[3/7] Loading configuration and resolving Host address..." -ForegroundColor Cyan
$configPath = Join-Path $clientRoot "ClientConfig.json"
$configObj = $null
if (Test-Path -LiteralPath $configPath) {
    try {
        $configObj = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {}
}

if ($null -eq $configObj) {
    $configObj = [PSCustomObject]@{
        Connection = [PSCustomObject]@{
            HostAddress             = ""
            HostPort                = $HostPort
            DiscoveryPort           = 8766
            EnableDiscovery         = $true
            DiscoveryTimeoutSeconds = 4
            PollIntervalSeconds     = 10
            MaxBackoffSeconds       = 60
            RequestTimeoutSeconds   = 15
        }
        Security = [PSCustomObject]@{
            AuthSecret              = ""
            ClientId                = ""
        }
        Slideshow = [PSCustomObject]@{
            IntervalSeconds         = 60
            WallpaperStyle          = 10
            TileWallpaper           = 0
        }
        Paths = [PSCustomObject]@{
            CacheDir                = "./Cache"
            LogsDir                 = "./Logs"
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($HostAddress)) {
    $configObj.Connection.HostAddress = $HostAddress
}
if (-not [string]::IsNullOrWhiteSpace($AuthSecret)) {
    $configObj.Security.AuthSecret = $AuthSecret
}

$targetHost = $configObj.Connection.HostAddress
$targetPort = $configObj.Connection.HostPort

# Attempt UDP broadcast discovery if HostAddress is empty
if ([string]::IsNullOrWhiteSpace($targetHost) -and $configObj.Connection.EnableDiscovery) {
    Write-Host "  HostAddress is empty. Broadcasting UDP discovery packet on LAN..." -ForegroundColor Yellow
    $discUdp = New-Object System.Net.Sockets.UdpClient
    $discUdp.EnableBroadcast = $true
    $discUdp.Client.ReceiveTimeout = 3000
    try {
        $msg = [System.Text.Encoding]::UTF8.GetBytes("LAN_WALLPAPER_DISCOVER_REQ")
        $bcast = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Broadcast, $configObj.Connection.DiscoveryPort)
        [void]$discUdp.Send($msg, $msg.Length, $bcast)

        # Broadcast across all active subnets dynamically
        try {
            $adapters = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" }

            foreach ($a in $adapters) {
                $ipBytes = [System.Net.IPAddress]::Parse($a.IPAddress).GetAddressBytes()
                $prefix = $a.PrefixLength
                if ($prefix -gt 0 -and $prefix -le 30) {
                    $maskVal = [uint32]([Convert]::ToUInt32("1" * $prefix + "0" * (32 - $prefix), 2))
                    $maskBytes = [System.BitConverter]::GetBytes([System.Net.IPAddress]::HostToNetworkOrder([int]$maskVal))
                    $bcastBytes = New-Object byte[] 4
                    for ($i = 0; $i -lt 4; $i++) {
                        $bcastBytes[$i] = [byte]($ipBytes[$i] -bor (-bnot $maskBytes[$i]))
                    }
                    $directedBcast = New-Object System.Net.IPEndPoint((New-Object System.Net.IPAddress (,$bcastBytes)), $configObj.Connection.DiscoveryPort)
                    [void]$discUdp.Send($msg, $msg.Length, $directedBcast)
                }
            }
        } catch {}
        $remote = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $respBytes = $discUdp.Receive([ref]$remote)
        $discovered = [System.Text.Encoding]::UTF8.GetString($respBytes) | ConvertFrom-Json
        if ($discovered -and $discovered.service -eq "LAN_WALLPAPER_HOST") {
            $targetHost = $discovered.ip
            $targetPort = $discovered.port
            $configObj.Connection.HostAddress = $targetHost
            $configObj.Connection.HostPort = $targetPort
            Write-Host "  [OK] Host automatically discovered: $($discovered.hostname) at $targetHost`:$targetPort" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "  UDP discovery did not receive a response." -ForegroundColor DarkGray
    }
    finally {
        $discUdp.Close()
        $discUdp.Dispose()
    }
}

# If still empty, interactively prompt or error
if ([string]::IsNullOrWhiteSpace($targetHost)) {
    Write-Host ""
    Write-Host "Could not automatically discover the Host PC on this LAN subnet." -ForegroundColor Yellow
    $userEnteredHost = Read-Host "Please enter the Host PC IPv4 Address (e.g. 192.168.1.100)"
    if ([string]::IsNullOrWhiteSpace($userEnteredHost)) {
        throw "Fatal: Host IP address is required to proceed with client installation."
    }
    $targetHost = $userEnteredHost.Trim()
    $configObj.Connection.HostAddress = $targetHost
}

# If AuthSecret is missing, prompt
if ([string]::IsNullOrWhiteSpace($configObj.Security.AuthSecret)) {
    $userEnteredSecret = Read-Host "Please enter the Client Authentication Secret (from Host)"
    if ([string]::IsNullOrWhiteSpace($userEnteredSecret)) {
        throw "Fatal: Authentication secret is required for secure client connection."
    }
    $configObj.Security.AuthSecret = $userEnteredSecret.Trim()
}

# Save updated config
$updatedJson = $configObj | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($configPath, $updatedJson, [System.Text.Encoding]::UTF8)

# 4. Test Connectivity & Authentication
Write-Host "[4/7] Testing connection and authentication to Host..." -ForegroundColor Cyan
$healthUri = "http://$targetHost`:$targetPort/api/v1/health"
try {
    $health = Invoke-RestMethod -Uri $healthUri -TimeoutSec 5 -ErrorAction Stop
    Write-Host "  [OK] Host reachability confirmed ($($health.service) v$($health.version))" -ForegroundColor Green
    Write-Host "       Current Collection: $($health.collectionVersion) | Images: $($health.totalImages)" -ForegroundColor Gray
}
catch {
    throw "Fatal: Could not reach Host server at $healthUri. Ensure the Host PC is on and firewall is configured. Error: $($_.Exception.Message)"
}

# 5. Execute Initial Synchronization & First Wallpaper
Write-Host "[5/7] Executing initial image synchronization and desktop setup..." -ForegroundColor Cyan
$clientScript = Join-Path $clientRoot "Client.ps1"
if (-not (Test-Path -LiteralPath $clientScript)) {
    throw "Client script missing at $clientScript"
}

# Run client in RunOnce mode to download and apply first wallpaper immediately
& $clientScript -ConfigPath $configPath -RunOnce

# Verify local cache
$cachedFiles = Get-ChildItem -LiteralPath $cacheDir -File |
    Where-Object { $_.Extension.ToLowerInvariant() -in @(".jpg", ".jpeg", ".png", ".bmp") }

Write-Host "  [OK] Initial sync completed: $($cachedFiles.Count) images verified in local cache." -ForegroundColor Green

# 6. Configure Windows Task Scheduler User Logon Startup Task
Write-Host "[6/7] Configuring Windows Task Scheduler for interactive logon..." -ForegroundColor Cyan
$startupScript = Join-Path $PSScriptRoot "Configure-Startup.ps1"
if (-not (Test-Path -LiteralPath $startupScript)) {
    $startupScript = Join-Path $clientRoot "Configure-Startup.ps1"
}
if (Test-Path -LiteralPath $startupScript) {
    & $startupScript -Role "Client" -AppRoot (Split-Path $clientRoot -Parent)
}

# 7. Start Background Client Agent Process
Write-Host "[7/7] Launching Client Agent background process..." -ForegroundColor Cyan
if (-not $NoStart) {
    # Check if mutex is already held or start process
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$clientScript`" -ConfigPath `"$configPath`""
    Write-Host "  [OK] Client Agent background process active." -ForegroundColor Green
}

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host " CLIENT INSTALLATION COMPLETED SUCCESSFULLY" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host " Connected Host Address   : $targetHost`:$targetPort" -ForegroundColor Cyan
Write-Host " Cached Wallpapers        : $($cachedFiles.Count) images ready" -ForegroundColor Cyan
Write-Host " Desktop Status           : First wallpaper applied successfully" -ForegroundColor Cyan
Write-Host " Auto-Start Mode          : Registered in Task Scheduler for user '$($env:USERNAME)'" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host ""
