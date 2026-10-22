# ==============================================================================
# Installer/Install-Host.ps1
# LAN Dynamic Wallpaper - Host Controller Installation & Packaging Engine
# Pure Windows PowerShell 5.1+ / Idempotent Enterprise Setup
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$Port = 8765,

    [Parameter(Mandatory = $false)]
    [int]$DiscoveryPort = 8766,

    [Parameter(Mandatory = $false)]
    [switch]$NoStart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 1. Verify Administrative Privileges & Self-Elevate if Necessary
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Elevation required. Relaunching installer as Administrator..." -ForegroundColor Yellow
    $argsList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($NoStart) { $argsList += " -NoStart" }
    Start-Process powershell.exe -ArgumentList $argsList -Verb RunAs
    exit 0
}

Write-Host "==============================================================================" -ForegroundColor Green
Write-Host " LAN DYNAMIC WALLPAPER SLIDESHOW - HOST INSTALLER" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green

# 2. Check Compatibility & Runtime
$psVersion = $PSVersionTable.PSVersion
Write-Host "[1/8] Verifying environment compatibility..." -ForegroundColor Cyan
Write-Host "  PowerShell Version: $psVersion" -ForegroundColor Gray
if ($psVersion.Major -lt 5 -or ($psVersion.Major -eq 5 -and $psVersion.Minor -lt 1)) {
    throw "Fatal: Windows PowerShell 5.1 or newer is required."
}

$os = Get-CimInstance Win32_OperatingSystem
Write-Host "  Operating System  : $($os.Caption) ($($os.Version))" -ForegroundColor Gray

# 3. Create Required Directory Hierarchy
Write-Host "[2/8] Creating directory structure..." -ForegroundColor Cyan
$appRoot = [System.IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$dirs = @("Host", "Client", "Installer", "Tools", "Tests", "Wallpapers", "Published", "Cache", "Logs")
foreach ($d in $dirs) {
    $p = Join-Path $appRoot $d
    if (-not (Test-Path -LiteralPath $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        Write-Host "  Created directory: $d" -ForegroundColor Gray
    }
}

# 4. Generate or Preserve Secure Credentials
Write-Host "[3/8] Checking security keys and configuration..." -ForegroundColor Cyan
$hostConfigPath = Join-Path $appRoot "Host\HostConfig.json"

function New-SecureTokenHex {
    param([int]$ByteCount = 32)
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $bytes = New-Object byte[] $ByteCount
    $rng.GetBytes($bytes)
    $rng.Dispose()
    $sb = New-Object System.Text.StringBuilder
    foreach ($b in $bytes) { [void]$sb.Append($b.ToString("x2")) }
    return $sb.ToString()
}

$authSecret = ""
$adminSecret = ""

if (Test-Path -LiteralPath $hostConfigPath) {
    try {
        $existing = Get-Content -LiteralPath $hostConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $authSecret = $existing.Security.AuthSecret
        $adminSecret = $existing.Security.AdminSecret
        Write-Host "  Existing cryptographic keys loaded from HostConfig.json." -ForegroundColor Gray
    } catch {}
}

if ([string]::IsNullOrWhiteSpace($authSecret) -or $authSecret.Length -lt 32) {
    $authSecret = New-SecureTokenHex -ByteCount 32
    Write-Host "  Generated new 256-bit client authentication secret." -ForegroundColor Yellow
}
if ([string]::IsNullOrWhiteSpace($adminSecret) -or $adminSecret.Length -lt 32) {
    $adminSecret = New-SecureTokenHex -ByteCount 32
    Write-Host "  Generated new 256-bit administrative secret." -ForegroundColor Yellow
}

$hostConfigObj = [PSCustomObject]@{
    Server = [PSCustomObject]@{
        BindAddress           = "0.0.0.0"
        Port                  = $Port
        DiscoveryPort         = $DiscoveryPort
        EnableDiscovery       = $true
        MaxConcurrentRequests = 128
        RequestTimeoutSeconds = 30
    }
    Security = [PSCustomObject]@{
        AuthSecret            = $authSecret
        AdminSecret           = $adminSecret
        RequireAuthentication = $true
        MaxImageSizeBytes     = 26214400
        AllowedExtensions     = @(".jpg", ".jpeg", ".png", ".bmp")
    }
    Slideshow = [PSCustomObject]@{
        DefaultIntervalSeconds = 60
    }
    Paths = [PSCustomObject]@{
        WallpapersDir         = "../Wallpapers"
        PublishedDir          = "../Published"
        LogsDir               = "../Logs"
        ClientsStore          = "./clients.json"
    }
}
$hostJson = $hostConfigObj | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($hostConfigPath, $hostJson, [System.Text.Encoding]::UTF8)
Write-Host "  HostConfig.json written successfully." -ForegroundColor Gray

# 5. Detect Active Ethernet IP & Port Reachability
Write-Host "[4/8] Detecting network interfaces and port availability..." -ForegroundColor Cyan
$activeIp = "127.0.0.1"
try {
    $adapters = Get-NetIPAddress -AddressFamily IPv4 -InterfaceOperationalStatus Up -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" }

    $preferred = $adapters | Where-Object {
        $alias = (Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue).InterfaceAlias
        $alias -like "*Ethernet*" -or $alias -like "*vEthernet*" -or $alias -like "*LAN*"
    } | Select-Object -First 1

    if ($null -ne $preferred) { $activeIp = $preferred.IPAddress }
    else {
        $fallback = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            ForEach-Object { Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue } |
            Where-Object { $_.IPAddress -notlike "127.*" } | Select-Object -First 1
        if ($fallback) { $activeIp = $fallback.IPAddress }
    }
} catch {}

Write-Host "  Active Ethernet IPv4 Address: $activeIp" -ForegroundColor Green
Write-Host "  Target HTTP Port            : $Port" -ForegroundColor Gray
Write-Host "  Target UDP Discovery Port   : $DiscoveryPort" -ForegroundColor Gray

# 6. Configure Windows Defender Firewall & URL ACL
Write-Host "[5/8] Configuring Windows Defender Firewall and HTTP.sys URL ACL..." -ForegroundColor Cyan
$firewallScript = Join-Path $PSScriptRoot "Configure-Firewall.ps1"
if (Test-Path -LiteralPath $firewallScript) {
    & $firewallScript -HttpPort $Port -DiscoveryPort $DiscoveryPort
}

# Add URL ACL reservation to allow non-admin binding to wildcard if needed
try {
    netsh http delete urlacl url="http://+:$Port/" 2>&1 | Out-Null
    netsh http add urlacl url="http://+:$Port/" user="Everyone" | Out-Null
    Write-Host "  [OK] URL reservation created: http://+:$Port/ (User: Everyone)" -ForegroundColor Green
}
catch {
    Write-Warning "URL ACL reservation note: $($_.Exception.Message)"
}

# 7. Configure Windows Task Scheduler Startup Task
Write-Host "[6/8] Configuring Windows Task Scheduler for automatic Host startup..." -ForegroundColor Cyan
$startupScript = Join-Path $PSScriptRoot "Configure-Startup.ps1"
if (Test-Path -LiteralPath $startupScript) {
    & $startupScript -Role "Host" -AppRoot $appRoot
}

# 8. Generate Distribution Package for 30-100 Clients
Write-Host "[7/8] Generating client deployment package..." -ForegroundColor Cyan
$clientPkgDir = Join-Path $PSScriptRoot "Client-Package"
if (-not (Test-Path -LiteralPath $clientPkgDir)) {
    New-Item -ItemType Directory -Path $clientPkgDir -Force | Out-Null
}

# Copy Client files
$clientFiles = @("Client.ps1", "Wallpaper.ps1")
foreach ($cf in $clientFiles) {
    Copy-Item -LiteralPath (Join-Path $appRoot "Client\$cf") -Destination (Join-Path $clientPkgDir $cf) -Force
}

# Copy Installer scripts for client
$clientInstallerFiles = @("Install-Client.bat", "Install-Client.ps1", "Configure-Startup.ps1", "Uninstall-Client.ps1")
foreach ($cif in $clientInstallerFiles) {
    $src = Join-Path $PSScriptRoot $cif
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $clientPkgDir $cif) -Force
    }
}

# Generate ready-to-run ClientConfig.json in client package
$clientConfigObj = [PSCustomObject]@{
    Connection = [PSCustomObject]@{
        HostAddress             = $activeIp
        HostPort                = $Port
        DiscoveryPort           = $DiscoveryPort
        EnableDiscovery         = $true
        DiscoveryTimeoutSeconds = 4
        PollIntervalSeconds     = 10
        MaxBackoffSeconds       = 60
        RequestTimeoutSeconds   = 15
    }
    Security = [PSCustomObject]@{
        AuthSecret              = $authSecret
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
$clientConfigJson = $clientConfigObj | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText((Join-Path $clientPkgDir "ClientConfig.json"), $clientConfigJson, [System.Text.Encoding]::UTF8)

# Also update base Client/ClientConfig.json
[System.IO.File]::WriteAllText((Join-Path $appRoot "Client\ClientConfig.json"), $clientConfigJson, [System.Text.Encoding]::UTF8)
Write-Host "  [OK] Client package generated at: $clientPkgDir" -ForegroundColor Green
Write-Host "       (Pre-configured with Host IP: $activeIp, Port: $Port, and AuthSecret)" -ForegroundColor Gray

# 9. Launch Host & Validate Health Endpoint
Write-Host "[8/8] Starting and validating Host service..." -ForegroundColor Cyan
if (-not $NoStart) {
    # Check if Host is already running or launch
    $healthUri = "http://localhost:$Port/api/v1/health"
    $isLive = $false
    try {
        $probe = Invoke-RestMethod -Uri $healthUri -TimeoutSec 2 -ErrorAction Stop
        if ($probe.status -eq "ok") { $isLive = $true }
    } catch {}

    if (-not $isLive) {
        $hostScript = Join-Path $appRoot "Host\Host.ps1"
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$hostScript`"" -WindowStyle Minimized
        Start-Sleep -Seconds 3

        for ($t = 0; $t -lt 6; $t++) {
            try {
                $probe = Invoke-RestMethod -Uri $healthUri -TimeoutSec 2 -ErrorAction Stop
                if ($probe.status -eq "ok") {
                    $isLive = $true
                    break
                }
            } catch {
                Start-Sleep -Seconds 1
            }
        }
    }

    if ($isLive) {
        Write-Host "  [OK] Host HTTP Health Check Passed: $healthUri (HTTP 200)" -ForegroundColor Green
    } else {
        Write-Warning "Host process launched, but health check is not responding yet. Verify Host window or logs."
    }
}

# 10. Final Installation Report
Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host " HOST INSTALLATION COMPLETED SUCCESSFULLY" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host " Host IP Address          : $activeIp" -ForegroundColor Cyan
Write-Host " HTTP Port                : $Port" -ForegroundColor Cyan
Write-Host " UDP Discovery Port       : $DiscoveryPort" -ForegroundColor Cyan
Write-Host " Wallpapers Drop Folder   : $(Join-Path $appRoot 'Wallpapers')" -ForegroundColor Yellow
Write-Host " Client Deployment Folder : $clientPkgDir" -ForegroundColor Yellow
Write-Host ""
Write-Host " TO DEPLOY TO 30-100 CLIENT COMPUTERS:" -ForegroundColor White
Write-Host " 1. Copy the '$clientPkgDir' folder to each Client PC." -ForegroundColor Gray
Write-Host " 2. Double-click 'Install-Client.bat' on each Client PC once." -ForegroundColor Gray
Write-Host " 3. Slideshow rotation and dynamic sync will run automatically at user logon." -ForegroundColor Gray
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host ""
