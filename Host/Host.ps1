# ==============================================================================
# Host/Host.ps1
# LAN Dynamic Wallpaper - Central Management Server & UDP Discovery Daemon
# Pure Windows PowerShell 5.1+ / .NET - Role-Based Access Control Architecture
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "",
    [Parameter(Mandatory = $false)]
    [int]$Port = 0,
    [Parameter(Mandatory = $false)]
    [switch]$NoLocalSlideshow = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
} elseif ($null -ne $MyInvocation -and $null -ne $MyInvocation.MyCommand -and ($MyInvocation.MyCommand.PSObject.Properties['Path'])) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    (Get-Location).Path
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $scriptDir "HostConfig.json"
}
$script:ConfigPath = [System.IO.Path]::GetFullPath($ConfigPath.Trim().Trim('"').Trim("'"))

# Ensure security protocol supports modern TLS if needed
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Tls12'

# Import Publisher engine
$publisherScript = Join-Path $scriptDir "Publisher.ps1"
if (-not (Test-Path -LiteralPath $publisherScript)) {
    throw "Fatal: Publisher.ps1 not found at $publisherScript"
}
$savedConfig = $script:ConfigPath
$IsImportedModule = $true
. $publisherScript -ConfigPath $savedConfig
$script:ConfigPath = $savedConfig

# Import Wallpaper engine for Host Desktop Slideshow
$wallpaperScript = Join-Path $scriptDir "../Client/Wallpaper.ps1"
if (Test-Path -LiteralPath $wallpaperScript) {
    try {
        . $wallpaperScript
    } catch {
        # Desktop wallpaper engine can be safely ignored in non-interactive sessions
    }
}

# Application State
$script:Running = $true
$script:StartTime = [DateTime]::UtcNow
$script:HttpListener = $null
$script:UdpListener = $null
$script:HostMutex = $null
$script:ClientRegistry = @{}
$script:ClientTokens = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:ClientLock = New-Object System.Object
$script:LogLock = New-Object System.Object
$script:LogDirectory = $null

function New-CryptoSecret {
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 32
    $rng.GetBytes($bytes)
    $sb = New-Object System.Text.StringBuilder
    foreach ($b in $bytes) { [void]$sb.Append($b.ToString("x2")) }
    return $sb.ToString()
}


function Write-HostLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG", "AUDIT")]
        [string]$Level = "INFO",
        [string]$ClientIp = "-"
    )

    $timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-dd HH:mm:ss.fff")
    $logLine = "[$timestamp] [$Level] [$ClientIp] $Message"

    # Colorized Console output
    switch ($Level) {
        "INFO"  { Write-Host $logLine -ForegroundColor Gray }
        "AUDIT" { Write-Host $logLine -ForegroundColor Cyan }
        "WARN"  { Write-Host $logLine -ForegroundColor Yellow }
        "ERROR" { Write-Host $logLine -ForegroundColor Red }
        "DEBUG" { Write-Host $logLine -ForegroundColor DarkGray }
    }

    # Daily Rotating File Log
    try {
        [System.Threading.Monitor]::Enter($script:LogLock)
        $logDir = if ($null -ne $script:LogDirectory -and -not [string]::IsNullOrWhiteSpace($script:LogDirectory)) {
            $script:LogDirectory
        } else {
            [System.IO.Path]::GetFullPath((Join-Path $scriptDir "../Logs"))
        }
        if (-not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $logFile = Join-Path $logDir ("host-{0}.log" -f [DateTime]::UtcNow.ToString("yyyy-MM-dd"))
        [System.IO.File]::AppendAllText($logFile, "$logLine`r`n", [System.Text.Encoding]::UTF8)
    }
    catch {
        # Avoid crashing on logging I/O contention
    }
    finally {
        [System.Threading.Monitor]::Exit($script:LogLock)
    }
}

function Get-ActiveEthernetIp {
    <#
    .SYNOPSIS
    Discovers the active LAN/Wi-Fi IPv4 address, prioritizing the interface with the active default gateway.
    #>
    try {
        # Priority 1: Default gateway IPv4 route (the active interface connected to LAN/Internet)
        $gwRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            Where-Object { $_.NextHop -ne "0.0.0.0" } |
            Sort-Object RouteMetric |
            Select-Object -First 1

        if ($null -ne $gwRoute) {
            $gwIp = Get-NetIPAddress -InterfaceIndex $gwRoute.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
                Select-Object -First 1
            if ($null -ne $gwIp -and -not [string]::IsNullOrWhiteSpace($gwIp.IPAddress)) {
                return $gwIp.IPAddress
            }
        }

        # Priority 2: Any physical Wi-Fi or Ethernet adapter
        $adapters = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" }

        $preferred = $adapters | Where-Object {
            $alias = (Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue).InterfaceAlias
            $alias -like "*Wi-Fi*" -or $alias -like "*Ethernet*" -or $alias -like "*LAN*"
        } | Select-Object -First 1

        if ($null -ne $preferred) {
            return $preferred.IPAddress
        }

        if ($adapters -and $adapters.Count -gt 0) {
            return ($adapters | Select-Object -First 1).IPAddress
        }

        # Ultimate fallback
        $anyIp = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
            Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and -not [System.Net.IPAddress]::IsLoopback($_) } |
            Select-Object -First 1

        if ($null -ne $anyIp) {
            return $anyIp.IPAddressToString
        }
    }
    catch {
        Write-HostLog "Adapter detection error: $($_.Exception.Message)" -Level WARN
    }

    return "127.0.0.1"
}

function Load-ClientRegistry {
    param([string]$Path)
    [System.Threading.Monitor]::Enter($script:ClientLock)
    try {
        if (Test-Path -LiteralPath $Path) {
            $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            $json = $raw | ConvertFrom-Json
            $dict = @{}
            $script:ClientTokens.Clear()
            if ($null -ne $json) {
                foreach ($prop in $json.PSObject.Properties) {
                    $dict[$prop.Name] = $prop.Value
                    if ($null -ne $prop.Value -and $prop.Value.PSObject.Properties['clientToken'] -and -not [string]::IsNullOrWhiteSpace($prop.Value.clientToken)) {
                        $script:ClientTokens[$prop.Value.clientToken] = $prop.Name
                    }
                }
            }
            $script:ClientRegistry = $dict
            Write-HostLog "Loaded $($script:ClientRegistry.Count) clients from registry store." -Level INFO
        }
    }
    catch {
        Write-HostLog "Could not load client registry: $($_.Exception.Message)" -Level WARN
    }
    finally {
        [System.Threading.Monitor]::Exit($script:ClientLock)
    }
}

function Save-ClientRegistry {
    param([string]$Path)
    [System.Threading.Monitor]::Enter($script:ClientLock)
    try {
        $parent = Split-Path $Path -Parent
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        $json = $script:ClientRegistry | ConvertTo-Json -Depth 4
        [System.IO.File]::WriteAllText($Path, $json, [System.Text.Encoding]::UTF8)
    }
    catch {
        Write-HostLog "Could not persist client registry: $($_.Exception.Message)" -Level WARN
    }
    finally {
        [System.Threading.Monitor]::Exit($script:ClientLock)
    }
}

function Start-UdpDiscoveryServer {
    param(
        [int]$Port = 8766,
        [int]$HttpPort = 8765,
        [string]$HostIp
    )

    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.Open()

    $powershell = [System.Management.Automation.PowerShell]::Create()
    $powershell.Runspace = $runspace

    [void]$powershell.AddScript({
        param($Port, $HttpPort, $HostIp, $HostName)
        try {
            $udp = New-Object System.Net.Sockets.UdpClient($Port)
            $udp.EnableBroadcast = $true
            $endpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)

            while ($true) {
                $receiveBytes = $udp.Receive([ref]$endpoint)
                $requestMsg = [System.Text.Encoding]::UTF8.GetString($receiveBytes).Trim()

                if ($requestMsg -eq "LAN_WALLPAPER_DISCOVER_REQ") {
                    $responseObj = @{
                        service   = "LAN_WALLPAPER_HOST"
                        version   = "1.0.0"
                        ip        = $HostIp
                        port      = $HttpPort
                        hostname  = $HostName
                        timestamp = [DateTime]::UtcNow.ToString("o")
                    }
                    $json = ($responseObj | ConvertTo-Json -Compress)
                    $respBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                    $udp.Send($respBytes, $respBytes.Length, $endpoint) | Out-Null
                }
            }
        }
        catch {
            # Socket closed or shutdown
        }
        finally {
            if ($null -ne $udp) { $udp.Close() }
        }
    }).AddArgument($Port).AddArgument($HttpPort).AddArgument($HostIp).AddArgument([System.Environment]::MachineName)

    $handle = $powershell.BeginInvoke()
    return @{ PowerShell = $powershell; Runspace = $runspace; Handle = $handle }
}

function Send-JsonResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode = 200,
        [object]$Data
    )

    $json = $Data | ConvertTo-Json -Depth 5 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

    $Response.StatusCode = $StatusCode
    $Response.ContentType = "application/json; charset=utf-8"
    $Response.ContentLength64 = $bytes.Length
    $Response.Headers.Add("Access-Control-Allow-Origin", "*")
    $Response.Headers.Add("X-Content-Type-Options", "nosniff")

    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
    $Response.Close()
}

function Send-FileResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [string]$FilePath,
        [string]$Sha256
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        Send-JsonResponse -Response $Response -StatusCode 404 -Data @{ error = "File not found" }
        return
    }

    $ext = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    $mime = switch ($ext) {
        ".jpg"  { "image/jpeg" }
        ".jpeg" { "image/jpeg" }
        ".png"  { "image/png" }
        ".bmp"  { "image/bmp" }
        default { "application/octet-stream" }
    }

    $fileInfo = Get-Item -LiteralPath $FilePath
    $Response.StatusCode = 200
    $Response.ContentType = $mime
    $Response.ContentLength64 = $fileInfo.Length
    $Response.Headers.Add("X-Content-Type-Options", "nosniff")
    $Response.Headers.Add("X-Image-Sha256", $Sha256)
    $Response.Headers.Add("Cache-Control", "public, max-age=86400")

    $buffer = New-Object byte[] 65536
    $fs = [System.IO.File]::OpenRead($FilePath)
    try {
        while (($read = $fs.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $Response.OutputStream.Write($buffer, 0, $read)
        }
    }
    finally {
        $fs.Close()
        $fs.Dispose()
        $Response.OutputStream.Close()
        $Response.Close()
    }
}

function Get-RequestAuthToken {
    param([System.Net.HttpListenerRequest]$Request)

    $token = $Request.Headers["X-Auth-Token"]
    if ([string]::IsNullOrWhiteSpace($token)) {
        $authHeader = $Request.Headers["Authorization"]
        if ($null -ne $authHeader -and $authHeader.StartsWith("Bearer ", [System.StringComparison]::OrdinalIgnoreCase)) {
            $token = $authHeader.Substring(7).Trim()
        }
    }
    return $token
}

function Get-RequestBodyJson {
    param([System.Net.HttpListenerRequest]$Request)

    if (-not $Request.HasEntityBody) {
        return $null
    }

    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
    try {
        $body = $reader.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($body)) { return $null }
        return ($body | ConvertFrom-Json)
    }
    finally {
        $reader.Close()
        $reader.Dispose()
    }
}

# ==============================================================================
# MAIN HOST SERVER ROUTING & EXECUTION
# ==============================================================================

function Start-HostServer {
    [CmdletBinding()]
    param(
        [string]$ConfigFilePath = $script:ConfigPath,
        [int]$PortOverride = 0,
        [switch]$NoLocalSlideshow = $false
    )

    $ConfigFilePath = [System.IO.Path]::GetFullPath($ConfigFilePath.Trim().Trim('"').Trim("'"))
    $cfg = Get-PublisherConfig -Path $ConfigFilePath
    $port = if ($PortOverride -gt 0) { $PortOverride } else { $cfg.Server.Port }
    $discPort = $cfg.Server.DiscoveryPort
    $authSecret = $cfg.Security.AuthSecret
    $adminSecret = $cfg.Security.AdminSecret
    $maxImageBytes = $cfg.Security.MaxImageSizeBytes
    $allowedExts = $cfg.Security.AllowedExtensions
    $defaultInterval = $cfg.Slideshow.DefaultIntervalSeconds

    # Dynamic cryptographic secret generation if secrets are empty or placeholders
    $secretsUpdated = $false
    if ([string]::IsNullOrWhiteSpace($authSecret) -or $authSecret -eq "GENERATE_ON_INSTALL") {
        $authSecret = New-CryptoSecret
        $cfg.Security.AuthSecret = $authSecret
        $secretsUpdated = $true
    }
    if ([string]::IsNullOrWhiteSpace($adminSecret) -or $adminSecret -eq "GENERATE_ON_INSTALL") {
        $adminSecret = New-CryptoSecret
        $cfg.Security.AdminSecret = $adminSecret
        $secretsUpdated = $true
    }
    if ($secretsUpdated) {
        try {
            $updatedJson = $cfg | ConvertTo-Json -Depth 5
            [System.IO.File]::WriteAllText($ConfigFilePath, $updatedJson, [System.Text.Encoding]::UTF8)
            Write-HostLog "Generated new cryptographically random 256-bit secrets for Host." -Level AUDIT

            # Apply restrictive Windows ACLs to configuration file
            try {
                $acl = Get-Acl -LiteralPath $ConfigFilePath
                $acl.SetAccessRuleProtection($true, $false)
                $adminSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
                $systemSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
                $userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
                $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($adminSid, "FullControl", "Allow")))
                $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($systemSid, "FullControl", "Allow")))
                $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($userSid, "FullControl", "Allow")))
                Set-Acl -LiteralPath $ConfigFilePath -AclObject $acl -ErrorAction SilentlyContinue
            } catch {}
        }
        catch {
            Write-HostLog "Notice: Could not persist newly generated secrets: $($_.Exception.Message)" -Level WARN
        }
    }

    # Enforce Single-Instance Host Mutex per Port
    $createdNewHost = $false
    try {
        $script:HostMutex = New-Object System.Threading.Mutex($true, "Global\LAN_Dynamic_Wallpaper_Host_Port_$port", [ref]$createdNewHost)
        if (-not $createdNewHost) {
            Write-HostLog "Another instance of Host Server is already running on port $port. Exiting." -Level ERROR
            throw "Duplicate host server instance detected on port $port."
        }
    }
    catch [System.Exception] {
        if ($_.Exception.Message -like "*Duplicate host*") { throw }
    }

    $configDir = Split-Path $ConfigFilePath -Parent
    $wallpapersDir = [System.IO.Path]::GetFullPath((Join-Path $configDir $cfg.Paths.WallpapersDir))
    $publishedDir = [System.IO.Path]::GetFullPath((Join-Path $configDir $cfg.Paths.PublishedDir))
    $clientsStorePath = [System.IO.Path]::GetFullPath((Join-Path $configDir $cfg.Paths.ClientsStore))
    $script:LogDirectory = [System.IO.Path]::GetFullPath((Join-Path $configDir $cfg.Paths.LogsDir))

    # Initialize directories
    foreach ($dir in @($wallpapersDir, $publishedDir, (Split-Path $clientsStorePath -Parent))) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    Load-ClientRegistry -Path $clientsStorePath

    # Initial publication sync
    Write-HostLog "Synchronizing wallpaper directory: $wallpapersDir" -Level INFO
    $initialManifest = Sync-WallpaperCollection -SourceDir $wallpapersDir -TargetDir $publishedDir `
        -MaxSizeBytes $maxImageBytes -AllowedExts $allowedExts -SlideshowInterval $defaultInterval

    # Start continuous FileSystemWatcher
    Start-WallpaperWatcher -SourceDir $wallpapersDir -TargetDir $publishedDir `
        -MaxSizeBytes $maxImageBytes -AllowedExts $allowedExts -SlideshowInterval $defaultInterval

    # Detect Host IP
    $hostIp = Get-ActiveEthernetIp
    Write-Host ""
    Write-Host "==============================================================================" -ForegroundColor Green
    Write-Host "  LAN DYNAMIC WALLPAPER SLIDESHOW - HOST MANAGER & SERVER" -ForegroundColor Green
    Write-Host "==============================================================================" -ForegroundColor Green
    Write-Host "  [WALLPAPERS FOLDER] UPLOAD / DROP YOUR PHOTOS & VIDEOS HERE:" -ForegroundColor Yellow
    Write-Host "     $([System.IO.Path]::GetFullPath($wallpapersDir))" -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  [FORMATS]  Supported : JPG, PNG, BMP, GIF, WEBP, HEIC, TIFF, MP4, MOV, WMV" -ForegroundColor White
    Write-Host "  [TIMER]    Slideshow : $defaultInterval SECONDS (Exact-second sync on all PCs)" -ForegroundColor Yellow
    Write-Host "  [CAPACITY] Max Fleet : Up to 10,000 photos (100 MB per file limit)" -ForegroundColor White
    Write-Host "  [NETWORK]  Host IPv4 : $hostIp (HTTP: $port | UDP Discovery: $discPort)" -ForegroundColor Cyan
    # Auto-configure Windows Network Folder Share for Everyone (Read-Only)
    try {
        $rootProjectDir = [System.IO.Path]::GetFullPath((Join-Path $scriptDir ".."))
        $existingShare = Get-SmbShare -Name "LAN-Dynamic-Wallpaper" -ErrorAction SilentlyContinue
        if ($null -eq $existingShare) {
            New-SmbShare -Name "LAN-Dynamic-Wallpaper" -Path $rootProjectDir -ReadAccess "Everyone" -FullAccess "Administrators" -ErrorAction SilentlyContinue | Out-Null
        }
    } catch {}

    Write-Host "------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  [EASY 1-CLICK METHODS FOR YOUR 80 CLIENT COMPUTERS]:" -ForegroundColor White
    Write-Host "  Method 1 (Fastest): Open PowerShell on client PC and run:" -ForegroundColor Cyan
    Write-Host "            irm http://$hostIp`:$port/setup | iex" -ForegroundColor Yellow
    Write-Host "  Method 2 (Network Share): Press Win + R on client PC, enter:" -ForegroundColor Cyan
    Write-Host "            \\$hostIp\LAN-Dynamic-Wallpaper" -ForegroundColor Yellow
    Write-Host "            and double-click '2-Start-Client.bat'" -ForegroundColor White
    Write-Host "  Method 3 (Web Browser): In Chrome or Edge on client PC, open:" -ForegroundColor Cyan
    Write-Host "            http://$hostIp`:$port" -ForegroundColor Yellow
    Write-Host "==============================================================================" -ForegroundColor Green
    Write-Host ""

    # Start UDP Discovery
    $udpWorker = $null
    if ($cfg.Server.EnableDiscovery) {
        $udpWorker = Start-UdpDiscoveryServer -Port $discPort -HttpPort $port -HostIp $hostIp
        Write-HostLog "UDP Discovery responder active on UDP port $discPort" -Level INFO
    }

    # Start HTTP Listener with validated interface binding
    $bound = $false
    $bindError = $null

    # Tier 1: Wildcard prefix (for elevated host with URL ACL)
    try {
        $testListener = New-Object System.Net.HttpListener
        $testListener.Prefixes.Add("http://+:$port/")
        $testListener.Start()
        $script:HttpListener = $testListener
        $bound = $true
    } catch {
        $bindError = $_.Exception.Message
    }

    # Tier 2: Direct Host LAN IP + 127.0.0.1
    if (-not $bound -and $hostIp -ne "127.0.0.1") {
        try {
            $testListener = New-Object System.Net.HttpListener
            $testListener.Prefixes.Add("http://$hostIp`:$port/")
            $testListener.Prefixes.Add("http://127.0.0.1:$port/")
            $testListener.Start()
            $script:HttpListener = $testListener
            $bound = $true
        } catch {
            $bindError = $_.Exception.Message
        }
    }

    # Tier 3: Loopback only if explicitly configured or running on isolated test environment without physical LAN
    if (-not $bound -and ($hostIp -eq "127.0.0.1" -or ($null -ne $cfg.Server.BindAddress -and $cfg.Server.BindAddress -eq "127.0.0.1"))) {
        try {
            $testListener = New-Object System.Net.HttpListener
            $testListener.Prefixes.Add("http://127.0.0.1:$port/")
            $testListener.Prefixes.Add("http://localhost:$port/")
            $testListener.Start()
            $script:HttpListener = $testListener
            $bound = $true
        } catch {
            $bindError = $_.Exception.Message
        }
    }

    # Enforce strict LAN binding: Stop with clear error if external LAN binding fails
    if (-not $bound) {
        Write-HostLog "FATAL: Failed to bind HTTP Server to LAN on port $port ($bindError)." -Level ERROR
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor Red
        Write-Host "  BINDING ERROR: Cannot bind HTTP Server on port $port" -ForegroundColor Red
        Write-Host "==============================================================================" -ForegroundColor Red
        Write-Host "  Possible causes:" -ForegroundColor Yellow
        Write-Host "  1. Port $port is already in use by another application." -ForegroundColor White
        Write-Host "     Check with: netstat -ano | findstr :$port" -ForegroundColor Cyan
        Write-Host "  2. Windows Firewall is blocking the port." -ForegroundColor White
        Write-Host "     Allow it with (run once as admin): netsh advfirewall firewall add rule name=""LAN-Wallpaper"" dir=in action=allow protocol=TCP localport=$port" -ForegroundColor Cyan
        Write-Host "==============================================================================" -ForegroundColor Red
        throw "Failed to bind HttpListener on port ${port}: $bindError"
    }

    Write-HostLog "HTTP Server listening for client connections on port $port" -Level INFO

    $lastReconciliation = [DateTime]::UtcNow
    $lastRegistrySave = [DateTime]::UtcNow
    $lastConfigCheck = [DateTime]::UtcNow
    $lastConfigFileWrite = if (Test-Path -LiteralPath $ConfigFilePath) { (Get-Item -LiteralPath $ConfigFilePath).LastWriteTimeUtc } else { [DateTime]::MinValue }
    $currentHostWallpaper = ""
    $localImageFiles = New-Object System.Collections.Generic.List[string]

    $refreshHostSlideshow = {
        $localImageFiles.Clear()
        if (Test-Path -LiteralPath $publishedDir) {
            $pFiles = Get-ChildItem -LiteralPath $publishedDir -File |
                Where-Object { $_.Name -ne "manifest.json" -and -not $_.Name.EndsWith(".pubtmp") -and -not $_.Name.EndsWith(".tmp") } |
                Sort-Object Name
            foreach ($pf in $pFiles) {
                $localImageFiles.Add($pf.FullName)
            }
        }
    }

    # Initial Host desktop wallpaper application
    if (-not $NoLocalSlideshow -and ([System.Management.Automation.PSTypeName]'Win32WallpaperEngine').Type) {
        try {
            & $refreshHostSlideshow
            if ($localImageFiles.Count -gt 0) {
                $syncObj = Get-SynchronizedWallpaper -ImageFiles $localImageFiles -IntervalSeconds $defaultInterval
                if ($null -ne $syncObj) {
                    $currentHostWallpaper = $syncObj.Path
                    Set-DesktopWallpaper -ImagePath $syncObj.Path | Out-Null
                    Write-HostLog "Host desktop wallpaper synchronized to: $([System.IO.Path]::GetFileName($syncObj.Path))" -Level INFO
                }
            }
        } catch {}
    }

    try {
        while ($script:Running) {
            # Non-blocking async accept
            $contextTask = $script:HttpListener.GetContextAsync()

            while (-not $contextTask.Wait(500)) {
                if (-not $script:Running) { break }

                $now = [DateTime]::UtcNow

                # Dynamic re-read of HostConfig.json if modified (e.g. interval changed without restarting server)
                if (($now - $lastConfigCheck).TotalSeconds -ge 2) {
                    $lastConfigCheck = $now
                    try {
                        if (Test-Path -LiteralPath $ConfigFilePath) {
                            $currentFileWrite = (Get-Item -LiteralPath $ConfigFilePath).LastWriteTimeUtc
                            if ($currentFileWrite -gt $lastConfigFileWrite) {
                                $lastConfigFileWrite = $currentFileWrite
                                $newCfg = Get-PublisherConfig -Path $ConfigFilePath
                                if ($null -ne $newCfg -and $null -ne $newCfg.Slideshow -and $newCfg.Slideshow.DefaultIntervalSeconds -gt 0) {
                                    if ($newCfg.Slideshow.DefaultIntervalSeconds -ne $defaultInterval) {
                                        $defaultInterval = $newCfg.Slideshow.DefaultIntervalSeconds
                                        Write-HostLog "Dynamic config reload: Slideshow interval updated to $defaultInterval seconds." -Level AUDIT
                                    }
                                }
                                if ($null -ne $newCfg -and $null -ne $newCfg.Security) {
                                    if ($newCfg.Security.MaxImageSizeBytes -gt 0) { $maxImageBytes = $newCfg.Security.MaxImageSizeBytes }
                                    if ($newCfg.Security.AllowedExtensions) { $allowedExts = $newCfg.Security.AllowedExtensions }
                                }
                            }
                        }
                    } catch {}
                }

                # Ultra-fast fallback reconciliation (every 2 seconds) so changes in Wallpapers folder update dynamically without stopping server
                if (($now - $lastReconciliation).TotalSeconds -ge 2) {
                    $lastReconciliation = $now
                    Sync-WallpaperCollection -SourceDir $wallpapersDir -TargetDir $publishedDir `
                        -MaxSizeBytes $maxImageBytes -AllowedExts $allowedExts -SlideshowInterval $defaultInterval | Out-Null
                }

                # Host desktop wallpaper exact-second synchronized rotation (matches all clients simultaneously)
                if (-not $NoLocalSlideshow -and ([System.Management.Automation.PSTypeName]'Win32WallpaperEngine').Type) {
                    try {
                        & $refreshHostSlideshow
                        if ($localImageFiles.Count -gt 0) {
                            $syncObj = Get-SynchronizedWallpaper -ImageFiles $localImageFiles -IntervalSeconds $defaultInterval
                            if ($null -ne $syncObj -and $syncObj.Path -ne $currentHostWallpaper) {
                                $currentHostWallpaper = $syncObj.Path
                                Set-DesktopWallpaper -ImagePath $syncObj.Path | Out-Null
                                Write-HostLog "Host desktop wallpaper synchronized to: $([System.IO.Path]::GetFileName($syncObj.Path)) (Index: $($syncObj.Index + 1)/$($localImageFiles.Count))" -Level INFO
                            }
                        }
                    } catch {}
                }

                # Periodic client store persistence (every 60 seconds)
                if (($now - $lastRegistrySave).TotalSeconds -ge 60) {
                    $lastRegistrySave = $now
                    Save-ClientRegistry -Path $clientsStorePath
                }
            }

            if (-not $script:Running) { break }

            $context = $contextTask.Result
            $request = $context.Request
            $response = $context.Response
            $clientIp = $request.RemoteEndPoint.Address.ToString()
            $path = $request.Url.AbsolutePath
            $method = $request.HttpMethod.ToUpperInvariant()

            # Execute request handler in isolated block
            try {
                # --------------------------------------------------------------
                # ROUTE -1: GET / (Web Setup Portal for Lab Workstations)
                # --------------------------------------------------------------
                if ($method -eq "GET" -and ($path -eq "/" -or $path -eq "/index.html")) {
                    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>LAN Dynamic Wallpaper - Lab Setup</title>
    <style>
        :root { --bg: #090d16; --card: #131b2e; --border: #23314f; --accent: #2563eb; --accent-glow: #3b82f6; --text: #f1f5f9; --text-dim: #94a3b8; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background: var(--bg); color: var(--text); display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 20px; }
        .card { background: var(--card); border: 1px solid var(--border); border-radius: 16px; max-width: 620px; width: 100%; padding: 36px; box-shadow: 0 20px 50px rgba(0,0,0,0.5); text-align: center; }
        .badge { display: inline-block; background: rgba(37,99,235,0.15); border: 1px solid rgba(59,130,246,0.3); color: #60a5fa; font-size: 13px; font-weight: 600; padding: 4px 12px; border-radius: 9999px; margin-bottom: 16px; }
        h1 { margin: 0 0 10px; font-size: 26px; font-weight: 700; }
        p { color: var(--text-dim); font-size: 15px; line-height: 1.6; margin: 0 0 24px; }
        .code-box { background: #060911; border: 1px solid var(--border); border-radius: 10px; padding: 14px 18px; font-family: Consolas, 'Courier New', monospace; font-size: 14px; color: #38bdf8; word-break: break-all; margin-bottom: 24px; display: flex; align-items: center; justify-content: space-between; text-align: left; }
        .btn { display: inline-flex; align-items: center; justify-content: center; background: var(--accent); color: #fff; text-decoration: none; font-weight: 600; font-size: 15px; padding: 12px 24px; border-radius: 8px; border: none; cursor: pointer; transition: all 0.2s; gap: 8px; }
        .btn:hover { background: var(--accent-glow); box-shadow: 0 0 20px rgba(59,130,246,0.4); }
        .btn-copy { background: #1e293b; color: #e2e8f0; font-size: 13px; padding: 6px 14px; border: 1px solid #334155; border-radius: 6px; cursor: pointer; }
        .btn-copy:hover { background: #334155; }
        .options { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin-top: 24px; text-align: left; }
        .option-box { background: rgba(255,255,255,0.02); border: 1px solid var(--border); border-radius: 10px; padding: 16px; }
        .option-box h3 { font-size: 15px; margin: 0 0 6px; color: #fff; }
        .option-box p { font-size: 13px; margin: 0; }
    </style>
</head>
<body>
    <div class="card">
        <div class="badge">LAN Dynamic Wallpaper • Workstation Setup</div>
        <h1>Connect This Computer</h1>
        <p>Run the 1-click command below in PowerShell, or download the batch file. No administrator privileges or passwords required.</p>
        
        <div class="code-box">
            <span id="cmd-text">irm http://$hostIp`:$port/setup | iex</span>
            <button class="btn-copy" onclick="copyCmd()">Copy</button>
        </div>

        <div style="display: flex; gap: 12px; justify-content: center;">
            <a href="/2-Start-Client.bat" class="btn">⬇️ Download 2-Start-Client.bat</a>
        </div>

        <div class="options">
            <div class="option-box">
                <h3>Option 1: PowerShell</h3>
                <p>Press <b>Win + R</b>, type <code>powershell</code>, paste the copied command, and press Enter.</p>
            </div>
            <div class="option-box">
                <h3>Option 2: Batch File</h3>
                <p>Download and double-click <code>2-Start-Client.bat</code>. It starts rotating wallpapers instantly.</p>
            </div>
        </div>
    </div>
    <script>
        function copyCmd() {
            var text = document.getElementById('cmd-text').innerText;
            navigator.clipboard.writeText(text).then(function() {
                alert('Copied! Now open PowerShell, paste, and press Enter.');
            });
        }
    </script>
</body>
</html>
"@
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
                    $response.StatusCode = 200
                    $response.ContentType = "text/html; charset=utf-8"
                    $response.ContentLength64 = $bytes.Length
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)
                    $response.OutputStream.Close()
                    $response.Close()
                    continue
                }

                # --------------------------------------------------------------
                # ROUTE -0b: GET /2-Start-Client.bat (Direct Batch Download with Dynamic Host IP)
                # --------------------------------------------------------------
                if ($method -eq "GET" -and $path -eq "/2-Start-Client.bat") {
                    $batPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDir "../2-Start-Client.bat"))
                    if (Test-Path -LiteralPath $batPath) {
                        $batContent = [System.IO.File]::ReadAllText($batPath, [System.Text.Encoding]::ASCII)
                        # Dynamically inject current Host IP so clients downloading via browser connect immediately
                        $batContent = $batContent.Replace('set "SERVER_OVERRIDE="', "set `"SERVER_OVERRIDE=$hostIp`"")
                        $bytes = [System.Text.Encoding]::ASCII.GetBytes($batContent)
                        $response.StatusCode = 200
                        $response.ContentType = "application/x-bat"
                        $response.Headers.Add("Content-Disposition", "attachment; filename=2-Start-Client.bat")
                        $response.ContentLength64 = $bytes.Length
                        $response.OutputStream.Write($bytes, 0, $bytes.Length)
                        $response.OutputStream.Close()
                        $response.Close()
                        continue
                    }
                }

                # --------------------------------------------------------------
                # ROUTE 0: GET /setup (1-Click Client Provisioning Script for Lab PCs)
                # --------------------------------------------------------------
                if ($method -eq "GET" -and ($path -eq "/setup" -or $path -eq "/setup/")) {
                    $bootstrapScript = @"
# LAN Dynamic Wallpaper - 1-Click Client Setup
`$ErrorActionPreference = 'Stop'
Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host " LAN DYNAMIC WALLPAPER - CLIENT WORKSTATION SETUP" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host " Connecting to Host at http://$hostIp`:$port ..." -ForegroundColor Cyan

`$clientDir = Join-Path `$env:LOCALAPPDATA 'LAN-Dynamic-Wallpaper-Client'
if (-not (Test-Path -LiteralPath `$clientDir)) {
    New-Item -ItemType Directory -Path `$clientDir -Force | Out-Null
}

`$files = @('Client.ps1', 'Wallpaper.ps1', 'ClientConfig.json')
foreach (`$f in `$files) {
    `$url = "http://$hostIp`:$port/client/`$f"
    `$dest = Join-Path `$clientDir `$f
    Write-Host " Downloading `$f ..." -ForegroundColor Gray
    Invoke-WebRequest -Uri `$url -OutFile `$dest -UseBasicParsing
}

Write-Host " [SUCCESS] Client files installed to: `$clientDir" -ForegroundColor Green
Write-Host " [STARTING] Launching Client Slideshow Agent in background..." -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host ""

Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"`$clientDir\Client.ps1`""
"@
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($bootstrapScript)
                    $response.StatusCode = 200
                    $response.ContentType = "text/plain; charset=utf-8"
                    $response.ContentLength64 = $bytes.Length
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)
                    $response.OutputStream.Close()
                    $response.Close()
                    continue
                }

                # --------------------------------------------------------------
                # ROUTE 0b: GET /client/{filename} (Client Provisioning Assets)
                # --------------------------------------------------------------
                if ($method -eq "GET" -and $path.StartsWith("/client/")) {
                    $rawFileName = [System.Uri]::UnescapeDataString($path.Substring("/client/".Length)).Trim()
                    if ($rawFileName -in @("Client.ps1", "Wallpaper.ps1", "ClientConfig.json")) {
                        $clientSrcPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDir "../Client/$rawFileName"))
                        if (Test-Path -LiteralPath $clientSrcPath) {
                            $fileText = [System.IO.File]::ReadAllText($clientSrcPath, [System.Text.Encoding]::UTF8)
                            if ($rawFileName -eq "ClientConfig.json") {
                                try {
                                    $cc = $fileText | ConvertFrom-Json
                                    $cc.Connection.HostAddress = $hostIp
                                    $cc.Connection.HostPort = $port
                                    $cc.Slideshow.IntervalSeconds = $defaultInterval
                                    $fileText = $cc | ConvertTo-Json -Depth 5
                                } catch {}
                            }
                            $bytes = [System.Text.Encoding]::UTF8.GetBytes($fileText)
                            $response.StatusCode = 200
                            $response.ContentType = "text/plain; charset=utf-8"
                            $response.ContentLength64 = $bytes.Length
                            $response.OutputStream.Write($bytes, 0, $bytes.Length)
                            $response.OutputStream.Close()
                            $response.Close()
                            continue
                        }
                    }
                    Send-JsonResponse -Response $response -StatusCode 404 -Data @{ error = "File not found" }
                    continue
                }

                # --------------------------------------------------------------
                # ROUTE 1: GET /api/v1/health (Public / Monitoring)
                # --------------------------------------------------------------
                if ($method -eq "GET" -and $path -eq "/api/v1/health") {
                    $manifestPath = Join-Path $publishedDir "manifest.json"
                    $curVer = "none"
                    $imgCount = 0
                    if (Test-Path -LiteralPath $manifestPath) {
                        $m = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
                        $curVer = $m.collectionVersion
                        $imgCount = $m.totalImages
                    }

                    $uptime = [Math]::Round(([DateTime]::UtcNow - $script:StartTime).TotalSeconds)
                    Send-JsonResponse -Response $response -StatusCode 200 -Data @{
                        status            = "ok"
                        service           = "LAN-Dynamic-Wallpaper-Host"
                        version           = "1.0.0"
                        uptimeSeconds     = $uptime
                        hostIp            = $hostIp
                        requireAuth       = [bool]$cfg.Security.RequireAuthentication
                        collectionVersion = $curVer
                        totalImages       = $imgCount
                        registeredClients = $script:ClientRegistry.Count
                    }
                    continue
                }

                # --------------------------------------------------------------
                # ROUTE 2: POST /api/v1/auth/register (Client Registration)
                # --------------------------------------------------------------
                if ($method -eq "POST" -and $path -eq "/api/v1/auth/register") {
                    $token = Get-RequestAuthToken -Request $request
                    $isLanClient = ($clientIp -like "192.168.*" -or $clientIp -like "10.*" -or $clientIp -like "172.1[6-9].*" -or $clientIp -like "172.2[0-9].*" -or $clientIp -like "172.3[0-1].*" -or $clientIp -eq "127.0.0.1" -or $clientIp -eq "::1" -or $clientIp -like "fe80:*")
                    $autoEnroll = if ($null -ne $cfg.Security.PSObject.Properties['AutoEnrollLanClients']) { [bool]$cfg.Security.AutoEnrollLanClients } else { $true }

                    $authAuthorized = $false
                    if (-not $cfg.Security.RequireAuthentication) {
                        $authAuthorized = $true
                    }
                    elseif (-not [string]::IsNullOrWhiteSpace($token) -and $token -eq $authSecret) {
                        $authAuthorized = $true
                    }
                    elseif ($autoEnroll -and $isLanClient -and [string]::IsNullOrWhiteSpace($token)) {
                        $authAuthorized = $true
                    }
                    else {
                        $authAuthorized = $false
                    }

                    if (-not $authAuthorized) {
                        Write-HostLog "Registration rejected: Invalid auth secret from $clientIp" -Level AUDIT -ClientIp $clientIp
                        Send-JsonResponse -Response $response -StatusCode 401 -Data @{ error = "Unauthorized: Invalid authentication secret" }
                        continue
                    }

                    $body = Get-RequestBodyJson -Request $request
                    $hostname = if ($null -ne $body -and $body.PSObject.Properties['hostname']) { $body.hostname } else { "PC-$clientIp" }
                    $mac = if ($null -ne $body -and $body.PSObject.Properties['mac']) { $body.mac } else { "unknown" }
                    $cVersion = if ($null -ne $body -and $body.PSObject.Properties['clientVersion']) { $body.clientVersion } else { "1.0.0" }

                    $clientId = "CLT-" + ([System.Guid]::NewGuid().ToString("N").Substring(0, 12).ToUpperInvariant())
                    $clientToken = "CLTK-" + (New-CryptoSecret).Substring(0, 32)
                    
                    [System.Threading.Monitor]::Enter($script:ClientLock)
                    try {
                        $script:ClientRegistry[$clientId] = @{
                            clientId      = $clientId
                            hostname      = $hostname
                            ipAddress     = $clientIp
                            macAddress    = $mac
                            clientVersion = $cVersion
                            registeredAt  = [DateTime]::UtcNow.ToString("o")
                            lastSeenAt    = [DateTime]::UtcNow.ToString("o")
                            status        = "ONLINE"
                            clientToken   = $clientToken
                            currentHash   = ""
                        }
                        $script:ClientTokens[$clientToken] = $clientId
                    }
                    finally {
                        [System.Threading.Monitor]::Exit($script:ClientLock)
                    }

                    Write-HostLog "Client registered successfully: $clientId ($hostname at $clientIp)" -Level AUDIT -ClientIp $clientIp
                    Save-ClientRegistry -Path $clientsStorePath
                    
                    $mPath = Join-Path $publishedDir "manifest.json"
                    $curVer = "none"
                    if (Test-Path -LiteralPath $mPath) {
                        $m = Get-Content -LiteralPath $mPath -Raw | ConvertFrom-Json
                        $curVer = $m.collectionVersion
                    }

                    Send-JsonResponse -Response $response -StatusCode 200 -Data @{
                        clientId               = $clientId
                        clientToken            = $clientToken
                        status                 = "ENROLLED"
                        slideshowInterval      = $defaultInterval
                        collectionVersion      = $curVer
                    }
                    continue
                }

                # --------------------------------------------------------------
                # RBAC Token Check for Data Endpoints (Client or Admin)
                # --------------------------------------------------------------
                $token = Get-RequestAuthToken -Request $request
                $isAdmin = ($null -ne $token -and $token -eq $adminSecret)
                $isClient = ($null -ne $token -and ($token -eq $authSecret -or $script:ClientTokens.ContainsKey($token)))

                if ($cfg.Security.RequireAuthentication -and (-not $isAdmin -and -not $isClient)) {
                    Write-HostLog "Access Denied: Missing or invalid token for $path" -Level WARN -ClientIp $clientIp
                    Send-JsonResponse -Response $response -StatusCode 401 -Data @{ error = "Unauthorized: Authentication required" }
                    continue
                }

                # --------------------------------------------------------------
                # ROUTE 3: GET /api/v1/manifest (Client / Admin)
                # --------------------------------------------------------------
                if ($method -eq "GET" -and $path -eq "/api/v1/manifest") {
                    $manifestPath = Join-Path $publishedDir "manifest.json"
                    if (-not (Test-Path -LiteralPath $manifestPath)) {
                        Send-JsonResponse -Response $response -StatusCode 404 -Data @{ error = "No manifest available" }
                        continue
                    }

                    $rawJson = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8)
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($rawJson)
                    $response.StatusCode = 200
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.ContentLength64 = $bytes.Length
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)
                    $response.OutputStream.Close()
                    $response.Close()
                    continue
                }

                # --------------------------------------------------------------
                # ROUTE 4: GET /api/v1/wallpaper/{filename} (Client / Admin)
                # --------------------------------------------------------------
                if ($method -eq "GET" -and $path.StartsWith("/api/v1/wallpaper/")) {
                    $rawFileName = [System.Uri]::UnescapeDataString($path.Substring("/api/v1/wallpaper/".Length))

                    # STRICT PATH TRAVERSAL DEFENSE
                    if ($rawFileName.Contains("..") -or $rawFileName.Contains("/") -or $rawFileName.Contains("\") -or ($rawFileName.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0)) {
                        Write-HostLog "SECURITY ALERT: Path traversal attempt detected from ${clientIp}: '$rawFileName'" -Level ERROR -ClientIp $clientIp
                        Send-JsonResponse -Response $response -StatusCode 400 -Data @{ error = "Invalid file identifier" }
                        continue
                    }

                    $targetFilePath = [System.IO.Path]::GetFullPath((Join-Path $publishedDir $rawFileName))
                    
                    # Ensure path is strictly within $publishedDir
                    if (-not $targetFilePath.StartsWith($publishedDir, [System.StringComparison]::OrdinalIgnoreCase)) {
                        Write-HostLog "SECURITY ALERT: Out-of-bounds path access rejected: '$targetFilePath'" -Level ERROR -ClientIp $clientIp
                        Send-JsonResponse -Response $response -StatusCode 403 -Data @{ error = "Access forbidden" }
                        continue
                    }

                    if (-not (Test-Path -LiteralPath $targetFilePath)) {
                        Send-JsonResponse -Response $response -StatusCode 404 -Data @{ error = "Image not found" }
                        continue
                    }

                    $sha256 = Get-FileSha256 -FilePath $targetFilePath
                    Send-FileResponse -Response $response -FilePath $targetFilePath -Sha256 $sha256
                    continue
                }

                # --------------------------------------------------------------
                # ROUTE 5: POST /api/v1/heartbeat (Client Node Telemetry)
                # --------------------------------------------------------------
                if ($method -eq "POST" -and $path -eq "/api/v1/heartbeat") {
                    $body = Get-RequestBodyJson -Request $request
                    $cid = if ($null -ne $body -and $body.PSObject.Properties['clientId']) { $body.clientId } else { "UNKNOWN" }
                    $imgHash = if ($null -ne $body -and $body.PSObject.Properties['currentImageHash']) { $body.currentImageHash } else { "" }

                    [System.Threading.Monitor]::Enter($script:ClientLock)
                    try {
                        if ($script:ClientRegistry.ContainsKey($cid)) {
                            $entry = $script:ClientRegistry[$cid]
                            $entry.lastSeenAt = [DateTime]::UtcNow.ToString("o")
                            $entry.ipAddress = $clientIp
                            $entry.status = "ONLINE"
                            $entry.currentHash = $imgHash
                            $script:ClientRegistry[$cid] = $entry
                        }
                        else {
                            $hName = if ($null -ne $body -and $body.PSObject.Properties['hostname']) { $body.hostname } else { "PC-$clientIp" }
                            $script:ClientRegistry[$cid] = @{
                                clientId    = $cid
                                hostname    = $hName
                                ipAddress   = $clientIp
                                lastSeenAt  = [DateTime]::UtcNow.ToString("o")
                                status      = "ONLINE"
                                currentHash = $imgHash
                            }
                        }
                    }
                    finally {
                        [System.Threading.Monitor]::Exit($script:ClientLock)
                    }

                    Send-JsonResponse -Response $response -StatusCode 200 -Data @{ status = "ACK"; timestamp = [DateTime]::UtcNow.ToString("o") }
                    continue
                }

                # --------------------------------------------------------------
                # ROUTE 6: GET /api/v1/admin/clients (SuperAdmin Role Only)
                # --------------------------------------------------------------
                if ($method -eq "GET" -and $path -eq "/api/v1/admin/clients") {
                    if (-not $isAdmin) {
                        Send-JsonResponse -Response $response -StatusCode 403 -Data @{ error = "Forbidden: Administrator role required" }
                        continue
                    }

                    [System.Threading.Monitor]::Enter($script:ClientLock)
                    $clientList = @()
                    try {
                        $now = [DateTime]::UtcNow
                        foreach ($key in $script:ClientRegistry.Keys) {
                            $c = $script:ClientRegistry[$key]
                            $lastDt = [DateTime]::Parse($c.lastSeenAt)
                            $diffSec = ($now - $lastDt).TotalSeconds
                            $status = if ($diffSec -lt 45) { "ONLINE" } elseif ($diffSec -lt 180) { "STALE" } else { "OFFLINE" }
                            
                            $clientList += [PSCustomObject]@{
                                clientId      = $c.clientId
                                hostname      = $c.hostname
                                ipAddress     = $c.ipAddress
                                lastSeenAt    = $c.lastSeenAt
                                secondsAgo    = [Math]::Round($diffSec)
                                status        = $status
                                currentHash   = $c.currentHash
                            }
                        }
                    }
                    finally {
                        [System.Threading.Monitor]::Exit($script:ClientLock)
                    }

                    Send-JsonResponse -Response $response -StatusCode 200 -Data @{
                        totalClients = $clientList.Count
                        clients      = $clientList
                    }
                    continue
                }

                # --------------------------------------------------------------
                # ROUTE 7: POST /api/v1/admin/sync (SuperAdmin Role Only)
                # --------------------------------------------------------------
                if ($method -eq "POST" -and $path -eq "/api/v1/admin/sync") {
                    if (-not $isAdmin) {
                        Send-JsonResponse -Response $response -StatusCode 403 -Data @{ error = "Forbidden: Administrator role required" }
                        continue
                    }

                    Write-HostLog "Admin force-sync triggered by $clientIp" -Level AUDIT -ClientIp $clientIp
                    $syncResult = Sync-WallpaperCollection -SourceDir $wallpapersDir -TargetDir $publishedDir `
                        -MaxSizeBytes $maxImageBytes -AllowedExts $allowedExts -SlideshowInterval $defaultInterval

                    Send-JsonResponse -Response $response -StatusCode 200 -Data @{
                        message           = "Force sync completed successfully"
                        collectionVersion = $syncResult.collectionVersion
                        totalImages       = $syncResult.totalImages
                    }
                    continue
                }

                # Catch-all: Route Not Found
                Send-JsonResponse -Response $response -StatusCode 404 -Data @{ error = "Endpoint not found: $method $path" }
            }
            catch {
                Write-HostLog "Internal server error on $path : $($_.Exception.Message)" -Level ERROR -ClientIp $clientIp
                try {
                    Send-JsonResponse -Response $response -StatusCode 500 -Data @{ error = "Internal server error" }
                } catch {}
            }
        }
    }
    finally {
        Write-HostLog "Host server shutting down..." -Level INFO
        Save-ClientRegistry -Path $clientsStorePath
        Stop-WallpaperWatcher
        if ($null -ne $script:HttpListener -and $script:HttpListener.IsListening) {
            $script:HttpListener.Stop()
            $script:HttpListener.Close()
        }
        if ($null -ne $udpWorker) {
            $udpWorker.PowerShell.Stop()
            $udpWorker.PowerShell.Dispose()
            $udpWorker.Runspace.Close()
            $udpWorker.Runspace.Dispose()
        }
        if ($null -ne $script:HostMutex) {
            try { $script:HostMutex.ReleaseMutex() } catch {}
            $script:HostMutex.Dispose()
            $script:HostMutex = $null
        }
    }
}

# Run Host
Start-HostServer -ConfigFilePath $script:ConfigPath -PortOverride $Port -NoLocalSlideshow:$NoLocalSlideshow
