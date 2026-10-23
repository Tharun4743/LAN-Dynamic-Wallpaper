# ==============================================================================
# Client/Client.ps1
# LAN Dynamic Wallpaper - Client Synchronization Agent & Desktop Slideshow
# Pure Windows PowerShell 5.1+ / .NET - Single Instance, Zero-Admin Desktop Mode
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "",

    [Parameter(Mandatory = $false)]
    [string]$HostAddress = "",

    [Parameter(Mandatory = $false)]
    [switch]$RunOnce,

    [Parameter(Mandatory = $false)]
    [switch]$VerboseOutput
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
    $ConfigPath = Join-Path $scriptDir "ClientConfig.json"
}
$script:ConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)

# Single Instance Mutex Enforcement (Session-Scoped to allow legitimate multi-user sessions)
$userSid = ""
try {
    $userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
} catch {
    $userSid = [System.Environment]::UserName
}
$script:MutexName = "Local\LAN_Dynamic_Wallpaper_Client_$userSid"
$script:CreatedNew = $false
try {
    $script:AppMutex = New-Object System.Threading.Mutex($true, $script:MutexName, [ref]$script:CreatedNew)
    if (-not $script:CreatedNew) {
        Write-Warning "Another instance of LAN Dynamic Wallpaper Client is already running for user session ($userSid). Exiting."
        exit 0
    }
}
catch {
    Write-Verbose "Mutex acquisition notice: $($_.Exception.Message)"
}

# Import Wallpaper Engine
$wallpaperEngineScript = Join-Path $PSScriptRoot "Wallpaper.ps1"
if (-not (Test-Path -LiteralPath $wallpaperEngineScript)) {
    throw "Fatal: Wallpaper.ps1 not found at $wallpaperEngineScript"
}
. $wallpaperEngineScript

# Global Client State
$script:Running = $true
$script:CurrentIndex = 0
$script:LocalCollection = New-Object System.Collections.Generic.List[string]
$script:CurrentWallpaperHash = ""
$script:ConsecutiveFailures = 0
$script:LogLock = New-Object System.Object

function Write-ClientLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG", "SYNC")]
        [string]$Level = "INFO"
    )

    $timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-dd HH:mm:ss.fff")
    $logLine = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        "INFO"  { Write-Host $logLine -ForegroundColor Gray }
        "SYNC"  { Write-Host $logLine -ForegroundColor Cyan }
        "WARN"  { Write-Host $logLine -ForegroundColor Yellow }
        "ERROR" { Write-Host $logLine -ForegroundColor Red }
        "DEBUG" { if ($VerboseOutput) { Write-Host $logLine -ForegroundColor DarkGray } }
    }

    try {
        [System.Threading.Monitor]::Enter($script:LogLock)
        $logDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../Logs"))
        if (-not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $logFile = Join-Path $logDir ("client-{0}.log" -f [DateTime]::UtcNow.ToString("yyyy-MM-dd"))
        [System.IO.File]::AppendAllText($logFile, "$logLine`r`n", [System.Text.Encoding]::UTF8)
    }
    catch {}
    finally {
        [System.Threading.Monitor]::Exit($script:LogLock)
    }
}

function Get-ClientConfig {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path) {
        try {
            $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            return ($raw | ConvertFrom-Json)
        }
        catch {
            Write-ClientLog "Failed parsing $Path : $($_.Exception.Message). Using defaults." -Level WARN
        }
    }

    return [PSCustomObject]@{
        Connection = [PSCustomObject]@{
            HostAddress             = ""
            HostPort                = 8765
            DiscoveryPort           = 8766
            EnableDiscovery         = $true
            DiscoveryTimeoutSeconds = 4
            PollIntervalSeconds     = 10
            MaxBackoffSeconds       = 60
            RequestTimeoutSeconds   = 15
        }
        Security   = [PSCustomObject]@{
            AuthSecret = ""
            ClientId   = ""
        }
        Slideshow  = [PSCustomObject]@{
            IntervalSeconds = 60
            WallpaperStyle  = 10
            TileWallpaper   = 0
        }
        Paths      = [PSCustomObject]@{
            CacheDir = "../Cache"
            LogsDir  = "../Logs"
        }
    }
}

function Save-ClientConfig {
    param([string]$Path, [object]$ConfigObj)
    try {
        $json = $ConfigObj | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($Path, $json, [System.Text.Encoding]::UTF8)

        # Apply restrictive Windows ACLs to protect client configuration
        try {
            $acl = Get-Acl -LiteralPath $Path
            $acl.SetAccessRuleProtection($true, $false)
            $userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
            $systemSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
            $adminSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
            $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($userSid, "FullControl", "Allow")))
            $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($systemSid, "FullControl", "Allow")))
            $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($adminSid, "FullControl", "Allow")))
            Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction SilentlyContinue
        } catch {}
    }
    catch {
        Write-ClientLog "Failed saving config: $($_.Exception.Message)" -Level WARN
    }
}

function Discover-HostOnLan {
    <#
    .SYNOPSIS
    Sends a UDP broadcast on the LAN to locate the active Host server.
    #>
    param(
        [int]$DiscoveryPort = 8766,
        [int]$TimeoutSeconds = 4
    )

    Write-ClientLog "Initiating LAN UDP host discovery on port $DiscoveryPort..." -Level INFO
    $udp = New-Object System.Net.Sockets.UdpClient
    $udp.EnableBroadcast = $true
    $udp.Client.ReceiveTimeout = ($TimeoutSeconds * 1000)

    try {
        $reqBytes = [System.Text.Encoding]::UTF8.GetBytes("LAN_WALLPAPER_DISCOVER_REQ")
        $broadcastEp = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Broadcast, $DiscoveryPort)
        [void]$udp.Send($reqBytes, $reqBytes.Length, $broadcastEp)

        # Broadcast dynamically across all active local subnets
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
                    $directedBcast = New-Object System.Net.IPEndPoint((New-Object System.Net.IPAddress (,$bcastBytes)), $DiscoveryPort)
                    [void]$udp.Send($reqBytes, $reqBytes.Length, $directedBcast)
                }
            }
        } catch {}

        $remoteEp = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $recvBytes = $udp.Receive([ref]$remoteEp)
        $responseJson = [System.Text.Encoding]::UTF8.GetString($recvBytes)
        $resp = $responseJson | ConvertFrom-Json

        if ($resp -and $resp.service -eq "LAN_WALLPAPER_HOST" -and -not [string]::IsNullOrWhiteSpace($resp.ip)) {
            $parsedIp = $null
            if ([System.Net.IPAddress]::TryParse($resp.ip, [ref]$parsedIp) -and ($resp.port -gt 0 -and $resp.port -le 65535)) {
                Write-ClientLog "Discovered Host PC: $($resp.hostname) at $($resp.ip):$($resp.port)" -Level INFO
                return $resp
            }
        }
    }
    catch [System.Net.Sockets.SocketException] {
        Write-ClientLog "UDP discovery timed out without response." -Level DEBUG
    }
    catch {
        Write-ClientLog "UDP discovery error: $($_.Exception.Message)" -Level DEBUG
    }
    finally {
        $udp.Close()
        $udp.Dispose()
    }

    # Parallel Subnet Sweep Fallback if UDP broadcast is dropped by network hardware
    Write-ClientLog "UDP broadcast silent. Initiating rapid local subnet sweep on port 8765..." -Level INFO
    try {
        $adapters = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" }

        foreach ($a in $adapters) {
            $localIp = $a.IPAddress
            $lastDot = $localIp.LastIndexOf('.')
            if ($lastDot -le 0) { continue }
            $subnetPrefix = $localIp.Substring(0, $lastDot)

            # Parallel non-blocking connection probes across the /24 subnet
            $tasks = New-Object System.Collections.Generic.List[object]
            foreach ($octet in 1..254) {
                $targetIp = "$subnetPrefix.$octet"
                $tcp = New-Object System.Net.Sockets.TcpClient
                $iar = $tcp.BeginConnect($targetIp, 8765, $null, $null)
                $tasks.Add([PSCustomObject]@{ Ip = $targetIp; Tcp = $tcp; Iar = $iar })
            }

            # Wait up to 1000ms in adaptive intervals for TCP connections to establish
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($sw.ElapsedMilliseconds -lt 1000) {
                $anyFinished = $false
                foreach ($t in $tasks) {
                    if ($t.Iar.IsCompleted) { $anyFinished = $true; break }
                }
                if ($anyFinished -and $sw.ElapsedMilliseconds -gt 350) { break }
                Start-Sleep -Milliseconds 100
            }

            $responsiveIps = New-Object System.Collections.Generic.List[string]
            foreach ($t in $tasks) {
                if ($t.Iar.IsCompleted) {
                    try {
                        $t.Tcp.EndConnect($t.Iar)
                        $responsiveIps.Add($t.Ip)
                    } catch {}
                }
                $t.Tcp.Close()
            }

            foreach ($rIp in $responsiveIps) {
                try {
                    $probeUri = "http://$rIp`:8765/api/v1/health"
                    $req = [System.Net.HttpWebRequest]::Create($probeUri)
                    $req.Timeout = 1500
                    $req.Method = "GET"
                    $resp = $req.GetResponse()
                    $sr = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
                    $txt = $sr.ReadToEnd()
                    $sr.Close()
                    $resp.Close()

                    $healthJson = $txt | ConvertFrom-Json
                    if ($healthJson -and ($healthJson.service -like "*WALLPAPER*HOST*" -or $healthJson.service -like "*Dynamic*Wallpaper*")) {
                        Write-ClientLog "Discovered Host PC via subnet sweep at $rIp`:8765" -Level INFO
                        return [PSCustomObject]@{
                            service  = "LAN_WALLPAPER_HOST"
                            hostname = if ($healthJson.PSObject.Properties['hostname']) { $healthJson.hostname } else { "Host-$rIp" }
                            ip       = $rIp
                            port     = 8765
                        }
                    }
                } catch {}
            }
        }
    } catch {
        Write-ClientLog "Subnet sweep fallback encountered error: $($_.Exception.Message)" -Level DEBUG
    }

    return $null
}

function Get-FileSha256Checksum {
    param([string]$FilePath)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $fs = [System.IO.File]::OpenRead($FilePath)
        $hashBytes = $sha256.ComputeHash($fs)
        $fs.Close()
        $fs.Dispose()
        $sb = New-Object System.Text.StringBuilder
        foreach ($b in $hashBytes) { [void]$sb.Append($b.ToString("x2")) }
        return $sb.ToString()
    }
    finally {
        $sha256.Dispose()
    }
}

function Invoke-ClientHttpRequest {
    param(
        [string]$Uri,
        [string]$Method = "GET",
        [string]$AuthToken = "",
        [object]$Body = $null,
        [string]$OutFile = "",
        [int]$TimeoutSec = 15
    )

    $req = [System.Net.HttpWebRequest]::Create($Uri)
    $req.Method = $Method
    $req.Timeout = ($TimeoutSec * 1000)
    $req.ReadWriteTimeout = ($TimeoutSec * 1000)
    $req.UserAgent = "LAN-Dynamic-Wallpaper-Client/1.0"

    if (-not [string]::IsNullOrWhiteSpace($AuthToken)) {
        $req.Headers.Add("X-Auth-Token", $AuthToken)
        $req.Headers.Add("Authorization", "Bearer $AuthToken")
    }

    if ($null -ne $Body) {
        $req.ContentType = "application/json; charset=utf-8"
        $json = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Compress }
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $req.ContentLength = $bodyBytes.Length
        $reqStream = $req.GetRequestStream()
        $reqStream.Write($bodyBytes, 0, $bodyBytes.Length)
        $reqStream.Close()
        $reqStream.Dispose()
    }

    try {
        $resp = [System.Net.HttpWebResponse]$req.GetResponse()
        
        if (-not [string]::IsNullOrWhiteSpace($OutFile)) {
            $respStream = $resp.GetResponseStream()
            $fs = [System.IO.File]::Create($OutFile)
            $buffer = New-Object byte[] 65536
            while (($read = $respStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $fs.Write($buffer, 0, $read)
            }
            $fs.Close()
            $fs.Dispose()
            $respStream.Close()
            $respStream.Dispose()

            $imgShaHeader = $resp.Headers["X-Image-Sha256"]
            $status = [int]$resp.StatusCode
            $resp.Close()
            return @{ StatusCode = $status; FileSaved = $true; ImageSha256Header = $imgShaHeader }
        }
        else {
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
            $content = $reader.ReadToEnd()
            $reader.Close()
            $reader.Dispose()
            $status = [int]$resp.StatusCode
            $resp.Close()
            return @{ StatusCode = $status; Content = $content }
        }
    }
    catch [System.Net.WebException] {
        $wEx = $_.Exception
        $stat = 0
        $bodyErr = ""
        if ($null -ne $wEx.Response) {
            $stat = [int](([System.Net.HttpWebResponse]$wEx.Response).StatusCode)
            try {
                $sr = New-Object System.IO.StreamReader($wEx.Response.GetResponseStream())
                $bodyErr = $sr.ReadToEnd()
                $sr.Close()
            } catch {}
            $wEx.Response.Close()
        }
        return @{ StatusCode = $stat; Error = $wEx.Message; Content = $bodyErr }
    }
}

function Register-ClientNode {
    param(
        [string]$BaseUrl,
        [string]$AuthSecret,
        $ClientId = $null,
        $ClientToken = $null
    )

    $regUri = "$BaseUrl/api/v1/auth/register"
    $payload = @{
        hostname      = [System.Environment]::MachineName
        mac           = "AUTO"
        clientVersion = "1.0.0"
    }

    Write-ClientLog "Registering client node with host: $regUri" -Level INFO
    $res = Invoke-ClientHttpRequest -Uri $regUri -Method "POST" -AuthToken $AuthSecret -Body $payload
    if ($res.StatusCode -eq 200 -and $res.Content) {
        $data = $res.Content | ConvertFrom-Json
        if ($null -ne $ClientId -and $ClientId -is [System.Management.Automation.PSReference]) {
            $ClientId.Value = $data.clientId
        }
        if ($null -ne $ClientToken -and $ClientToken -is [System.Management.Automation.PSReference] -and $data.PSObject.Properties['clientToken'] -and -not [string]::IsNullOrWhiteSpace($data.clientToken)) {
            $ClientToken.Value = $data.clientToken
        }
        Write-ClientLog "Client registration confirmed. Assigned Client ID: $($data.clientId)" -Level INFO
        return [PSCustomObject]@{
            Success     = $true
            ClientId    = $data.clientId
            ClientToken = (if ($data.PSObject.Properties['clientToken']) { $data.clientToken } else { "" })
            Interval    = (if ($data.PSObject.Properties['slideshowInterval']) { $data.slideshowInterval } else { 5 })
        }
    }
    else {
        Write-ClientLog "Registration failed (HTTP $($res.StatusCode)): $($res.Error)" -Level WARN
        return [PSCustomObject]@{ Success = $false; Error = $res.Error; StatusCode = $res.StatusCode }
    }
}

function Sync-ClientCollection {
    <#
    .SYNOPSIS
    Downloads manifest, reconciles local cache, verifies SHA-256 hashes,
    removes obsolete files, and updates local collection list.
    #>
    param(
        [string]$BaseUrl,
        [string]$AuthSecret,
        [string]$CacheDir,
        $ClientId = ""
    )

    $manifestUri = "$BaseUrl/api/v1/manifest"
    $res = Invoke-ClientHttpRequest -Uri $manifestUri -Method "GET" -AuthToken $AuthSecret
    if ($res.StatusCode -ne 200 -or -not $res.Content) {
        Write-ClientLog "Failed to retrieve manifest from $manifestUri (HTTP $($res.StatusCode))" -Level WARN
        return $false
    }

    $remoteManifest = $res.Content | ConvertFrom-Json
    $remoteVersion = $remoteManifest.collectionVersion
    $images = $remoteManifest.images

    $localManifestPath = Join-Path $CacheDir "local-manifest.json"
    $localVersion = ""
    if (Test-Path -LiteralPath $localManifestPath) {
        try {
            $lm = Get-Content -LiteralPath $localManifestPath -Raw | ConvertFrom-Json
            $localVersion = $lm.collectionVersion
        } catch {}
    }

    if ($remoteVersion -eq $localVersion) {
        Write-ClientLog "Local collection up to date (Version: $localVersion)." -Level DEBUG
        return $true
    }

    Write-ClientLog "New collection detected: $remoteVersion (Images: $($images.Count)). Initiating download..." -Level SYNC

    $downloadedFiles = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $hasErrors = $false

    foreach ($img in $images) {
        $fileName = $img.name
        
        # Defensive check against path traversal or illegal characters in manifest
        if ([string]::IsNullOrWhiteSpace($fileName) -or $fileName.Contains("..") -or $fileName.Contains("/") -or $fileName.Contains("\") -or ($fileName.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0)) {
            Write-ClientLog "Security rejection: Invalid or malicious filename in manifest: '$fileName'. Skipping." -Level ERROR
            continue
        }

        $expectedHash = $img.hash
        $targetPath = Join-Path $CacheDir $fileName
        [void]$downloadedFiles.Add($fileName)

        # Check if already present with valid hash
        if (Test-Path -LiteralPath $targetPath) {
            $existingHash = Get-FileSha256Checksum -FilePath $targetPath
            if ($existingHash -eq $expectedHash) {
                Write-ClientLog "Cached asset verified: $fileName (Hash: $expectedHash)" -Level DEBUG
                continue
            }
        }

        # Download to .tmp file atomically
        $tmpPath = Join-Path $CacheDir "$fileName.clttmp"
        $downloadUrl = "$BaseUrl$($img.downloadUrl)"

        Write-ClientLog "Downloading asset: $fileName ($($img.size) bytes)..." -Level INFO
        $dlRes = Invoke-ClientHttpRequest -Uri $downloadUrl -Method "GET" -AuthToken $AuthSecret -OutFile $tmpPath

        if ($dlRes.StatusCode -eq 200 -and (Test-Path -LiteralPath $tmpPath)) {
            $actualHash = Get-FileSha256Checksum -FilePath $tmpPath
            if ($actualHash -eq $expectedHash) {
                # Atomic swap into cache
                Move-Item -LiteralPath $tmpPath -Destination $targetPath -Force
                Write-ClientLog "Successfully verified and cached: $fileName" -Level SYNC
            }
            else {
                Write-ClientLog "Integrity mismatch for $fileName! Expected: $expectedHash, Actual: $actualHash. Rejecting." -Level ERROR
                Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
                $hasErrors = $true
            }
        }
        else {
            Write-ClientLog "Failed downloading $fileName (HTTP $($dlRes.StatusCode))" -Level ERROR
            $hasErrors = $true
        }
    }

    if ($hasErrors) {
        Write-ClientLog "Synchronization had errors; keeping previous local manifest until next cycle." -Level WARN
        return $false
    }

    # Prune cached files that are no longer in the manifest
    $cachedItems = Get-ChildItem -LiteralPath $CacheDir -File
    foreach ($ci in $cachedItems) {
        if ($ci.Name -eq "local-manifest.json" -or $ci.Name.EndsWith(".clttmp") -or $ci.Name.EndsWith(".tmp")) {
            continue
        }
        if (-not $downloadedFiles.Contains($ci.Name)) {
            Write-ClientLog "Pruning deleted image from cache: $($ci.Name)" -Level SYNC
            Remove-Item -LiteralPath $ci.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    # Save local manifest atomically
    $tmpManifest = Join-Path $CacheDir "local-manifest.json.tmp"
    [System.IO.File]::WriteAllText($tmpManifest, ($remoteManifest | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)
    Move-Item -LiteralPath $tmpManifest -Destination $localManifestPath -Force

    Write-ClientLog "Synchronization complete. Active Collection Version: $remoteVersion" -Level SYNC
    return $true
}

function Refresh-LocalCollectionList {
    param([string]$CacheDir)

    $list = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $CacheDir) {
        $files = Get-ChildItem -LiteralPath $CacheDir -File |
            Where-Object { $_.Extension.ToLowerInvariant() -in @(".jpg", ".jpeg", ".png", ".bmp", ".gif", ".webp", ".tiff", ".tif") } |
            Sort-Object -Property Name

        foreach ($f in $files) {
            $list.Add($f.FullName)
        }
    }
    return $list
}

function Send-ClientHeartbeat {
    param(
        [string]$BaseUrl,
        [string]$AuthSecret,
        [string]$ClientId,
        [string]$CurrentHash
    )

    if ([string]::IsNullOrWhiteSpace($ClientId)) { return }

    $hbUri = "$BaseUrl/api/v1/heartbeat"
    $payload = @{
        clientId         = $ClientId
        currentImageHash = $CurrentHash
        hostname         = [System.Environment]::MachineName
    }
    Invoke-ClientHttpRequest -Uri $hbUri -Method "POST" -AuthToken $AuthSecret -Body $payload | Out-Null
}

# ==============================================================================
# MAIN CLIENT AGENT EXECUTION LOOP
# ==============================================================================

function Start-ClientAgent {
    [CmdletBinding()]
    param(
        [string]$Path = $script:ConfigPath,
        [string]$HostOverride = ""
    )

    $cfg = Get-ClientConfig -Path $Path
    $configDir = Split-Path $Path -Parent
    $cacheDir = [System.IO.Path]::GetFullPath((Join-Path $configDir $cfg.Paths.CacheDir))
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }

    $authSecret = $cfg.Security.AuthSecret
    $authSecret = $cfg.Security.AuthSecret
    if ([string]::IsNullOrWhiteSpace($authSecret) -or $authSecret -eq "GENERATE_ON_INSTALL") {
        if ($env:LAN_WALLPAPER_AUTH_SECRET) {
            $authSecret = $env:LAN_WALLPAPER_AUTH_SECRET
            $cfg.Security.AuthSecret = $authSecret
        }
        elseif (Test-Path -LiteralPath (Join-Path $configDir "../Host/HostConfig.json")) {
            try {
                $hCfg = Get-Content -LiteralPath (Join-Path $configDir "../Host/HostConfig.json") -Raw | ConvertFrom-Json
                if ($hCfg.Security.AuthSecret) {
                    $authSecret = $hCfg.Security.AuthSecret
                    $cfg.Security.AuthSecret = $authSecret
                    Save-ClientConfig -Path $ConfigPath -ConfigObj $cfg
                    Write-ClientLog "Synchronized AuthSecret from local Host configuration." -Level INFO
                }
            } catch {}
        }
        else {
            Write-ClientLog "No static pre-shared key configured. Utilizing automatic LAN client provisioning." -Level INFO
        }
    }

    # Idempotently register interactive desktop logon startup in HKCU Run
    try {
        $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        $currentVal = (Get-ItemProperty -Path $runKey -Name "LAN-Dynamic-Wallpaper-Client" -ErrorAction SilentlyContinue)."LAN-Dynamic-Wallpaper-Client"
        $thisScript = if ($PSCommandPath) { $PSCommandPath } else { Join-Path $scriptDir "Client.ps1" }
        $targetCmd = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$([System.IO.Path]::GetFullPath($thisScript))`""
        if ($currentVal -ne $targetCmd) {
            Set-ItemProperty -Path $runKey -Name "LAN-Dynamic-Wallpaper-Client" -Value $targetCmd -Force -ErrorAction SilentlyContinue | Out-Null
            Write-ClientLog "Registered interactive user logon auto-start in HKCU Run." -Level DEBUG
        }
    } catch {}

    $clientId = $cfg.Security.ClientId
    $hostIp = if (-not [string]::IsNullOrWhiteSpace($HostOverride)) { $HostOverride.Trim() } else { $cfg.Connection.HostAddress }
    $hostPort = $cfg.Connection.HostPort
    $discPort = $cfg.Connection.DiscoveryPort
    $enableDisc = $cfg.Connection.EnableDiscovery
    $pollInterval = if ($cfg.Connection.PollIntervalSeconds -gt 0) { $cfg.Connection.PollIntervalSeconds } else { 3 }
    $slideshowInterval = if ($cfg.Slideshow.IntervalSeconds -gt 0) { $cfg.Slideshow.IntervalSeconds } else { 5 }
    $maxBackoff = $cfg.Connection.MaxBackoffSeconds

    if (-not [string]::IsNullOrWhiteSpace($HostOverride)) {
        $cfg.Connection.HostAddress = $hostIp
        Save-ClientConfig -Path $ConfigPath -ConfigObj $cfg
    }

    Write-Host ""
    Write-Host "==============================================================================" -ForegroundColor Green
    Write-Host " LAN DYNAMIC WALLPAPER SLIDESHOW - CLIENT WORKSTATION" -ForegroundColor Green
    Write-Host "==============================================================================" -ForegroundColor Green
    Write-Host " Configured Host IP       : $(if ($hostIp) { $hostIp } else { '[Auto-Discovery Active]' })" -ForegroundColor Cyan
    Write-Host " HTTP Service Port        : $hostPort" -ForegroundColor Cyan
    Write-Host " Slideshow Timer          : $slideshowInterval seconds (Exact-second synchronization)" -ForegroundColor Yellow
    Write-Host " Collection Poll Rate     : Dynamic 2s live sync" -ForegroundColor Cyan
    Write-Host " Local Image Cache        : $cacheDir" -ForegroundColor DarkGray
    Write-Host "==============================================================================" -ForegroundColor Green
    Write-Host ""

    # Initial host discovery if HostAddress is empty
    if ([string]::IsNullOrWhiteSpace($hostIp) -and $enableDisc) {
        $disc = Discover-HostOnLan -DiscoveryPort $discPort -TimeoutSeconds $cfg.Connection.DiscoveryTimeoutSeconds
        if ($null -ne $disc) {
            $hostIp = $disc.ip
            $hostPort = $disc.port
            $cfg.Connection.HostAddress = $hostIp
            Save-ClientConfig -Path $ConfigPath -ConfigObj $cfg
        }
    }

    if ([string]::IsNullOrWhiteSpace($hostIp)) {
        Write-ClientLog "Host IP not yet found. Retaining local cache offline mode until Host is detected on LAN." -Level WARN
    }

    # Initialize local collection from cache
    $script:LocalCollection = Refresh-LocalCollectionList -CacheDir $cacheDir
    Write-ClientLog "Initial cache loaded: $($script:LocalCollection.Count) valid images ready." -Level INFO

    $currentAppliedWallpaper = ""

    # If cache has images, set initial synchronized wallpaper immediately
    if ($script:LocalCollection.Count -gt 0) {
        $syncObj = Get-SynchronizedWallpaper -ImageFiles $script:LocalCollection -IntervalSeconds $slideshowInterval
        if ($null -ne $syncObj) {
            $currentAppliedWallpaper = $syncObj.Path
            $script:CurrentIndex = $syncObj.Index
            Set-DesktopWallpaper -ImagePath $syncObj.Path | Out-Null
            $script:CurrentWallpaperHash = Get-FileSha256Checksum -FilePath $syncObj.Path
            Write-ClientLog "Initial synchronized wallpaper established: $(Split-Path $syncObj.Path -Leaf)" -Level INFO
        }
    }

    if ($RunOnce) {
        if (-not [string]::IsNullOrWhiteSpace($hostIp)) {
            $baseUrl = "http://$hostIp`:$hostPort"
            $regRes = Register-ClientNode -BaseUrl $baseUrl -AuthSecret $authSecret
            if ($regRes.Success) {
                $authSecret = $regRes.ClientToken
                $cfg.Security.AuthSecret = $authSecret
                $cfg.Security.ClientId = $regRes.ClientId
                Save-ClientConfig -Path $ConfigPath -ConfigObj $cfg
            }
            Sync-ClientCollection -BaseUrl $baseUrl -AuthSecret $authSecret -CacheDir $cacheDir -ClientId $clientId | Out-Null
            $script:LocalCollection = Refresh-LocalCollectionList -CacheDir $cacheDir
            if ($script:LocalCollection.Count -gt 0) {
                $syncObj = Get-SynchronizedWallpaper -ImageFiles $script:LocalCollection -IntervalSeconds $slideshowInterval
                if ($syncObj) { Set-DesktopWallpaper -ImagePath $syncObj.Path | Out-Null }
            }
        }
        return
    }

    $lastManifestPoll = [DateTime]::MinValue
    $lastHeartbeat = [DateTime]::MinValue

    try {
        while ($script:Running) {
            $now = [DateTime]::UtcNow

            # ------------------------------------------------------------------
            # 1. Exact-Second Synchronized Desktop Wallpaper Rotation
            # ------------------------------------------------------------------
            if ($script:LocalCollection.Count -gt 0) {
                $syncObj = Get-SynchronizedWallpaper -ImageFiles $script:LocalCollection -IntervalSeconds $slideshowInterval
                if ($null -ne $syncObj -and $syncObj.Path -ne $currentAppliedWallpaper) {
                    $currentAppliedWallpaper = $syncObj.Path
                    $script:CurrentIndex = $syncObj.Index
                    Set-DesktopWallpaper -ImagePath $syncObj.Path | Out-Null
                    $script:CurrentWallpaperHash = Get-FileSha256Checksum -FilePath $syncObj.Path
                    Write-ClientLog "Slideshow synchronized: $(Split-Path $syncObj.Path -Leaf) (Index: $($syncObj.Index + 1)/$($script:LocalCollection.Count))" -Level INFO
                }
            }

            # ------------------------------------------------------------------
            # 2. Dynamic Live Manifest Sync Loop (checks every 2 seconds)
            # ------------------------------------------------------------------
            $effectivePollInterval = if ($script:ConsecutiveFailures -gt 0) {
                [Math]::Min(15, [Math]::Pow(2, $script:ConsecutiveFailures))
            } else {
                2
            }

            if (($now - $lastManifestPoll).TotalSeconds -ge $effectivePollInterval) {
                $lastManifestPoll = $now

                # If Host IP still unknown, retry discovery
                if ([string]::IsNullOrWhiteSpace($hostIp) -and $enableDisc) {
                    $disc = Discover-HostOnLan -DiscoveryPort $discPort -TimeoutSeconds 2
                    if ($null -ne $disc) {
                        $hostIp = $disc.ip
                        $hostPort = $disc.port
                        $cfg.Connection.HostAddress = $hostIp
                        Save-ClientConfig -Path $ConfigPath -ConfigObj $cfg
                        Write-ClientLog "Host discovered at $hostIp`:$hostPort" -Level INFO
                    }
                }

                if (-not [string]::IsNullOrWhiteSpace($hostIp)) {
                    $baseUrl = "http://$hostIp`:$hostPort"

                    # Register if not yet enrolled
                    if ([string]::IsNullOrWhiteSpace($clientId) -or [string]::IsNullOrWhiteSpace($authSecret)) {
                        $regRes = Register-ClientNode -BaseUrl $baseUrl -AuthSecret $authSecret
                        if ($regRes -and $regRes.Success) {
                            $clientId = $regRes.ClientId
                            $authSecret = $regRes.ClientToken
                            $slideshowInterval = $regRes.Interval
                            $cfg.Security.ClientId = $clientId
                            $cfg.Security.AuthSecret = $authSecret
                            $cfg.Slideshow.IntervalSeconds = $slideshowInterval
                            Save-ClientConfig -Path $ConfigPath -ConfigObj $cfg
                        }
                    }

                    # Perform synchronization
                    $syncOk = Sync-ClientCollection -BaseUrl $baseUrl -AuthSecret $authSecret -CacheDir $cacheDir -ClientId $clientId
                    if ($syncOk) {
                        $script:ConsecutiveFailures = 0
                        $script:LocalCollection = Refresh-LocalCollectionList -CacheDir $cacheDir
                    }
                    else {
                        $script:ConsecutiveFailures++
                        # If sync failed (e.g. 401 Unauthorized or host restarted), re-enroll automatically
                        if ($script:ConsecutiveFailures -ge 2 -or [string]::IsNullOrWhiteSpace($authSecret)) {
                            Write-ClientLog "Re-enrolling with Host to refresh authentication token..." -Level WARN
                            $regRes = Register-ClientNode -BaseUrl $baseUrl -AuthSecret ""
                            if ($regRes -and $regRes.Success) {
                                $clientId = $regRes.ClientId
                                $authSecret = $regRes.ClientToken
                                $slideshowInterval = $regRes.Interval
                                $cfg.Security.ClientId = $clientId
                                $cfg.Security.AuthSecret = $authSecret
                                $cfg.Slideshow.IntervalSeconds = $slideshowInterval
                                Save-ClientConfig -Path $ConfigPath -ConfigObj $cfg
                                $script:ConsecutiveFailures = 0
                                Sync-ClientCollection -BaseUrl $baseUrl -AuthSecret $authSecret -CacheDir $cacheDir -ClientId $clientId | Out-Null
                                $script:LocalCollection = Refresh-LocalCollectionList -CacheDir $cacheDir
                            }
                        }
                    }

                    # Heartbeat dispatch (every 30 seconds)
                    if (($now - $lastHeartbeat).TotalSeconds -ge 30) {
                        $lastHeartbeat = $now
                        Send-ClientHeartbeat -BaseUrl $baseUrl -AuthSecret $authSecret -ClientId $clientId -CurrentHash $script:CurrentWallpaperHash
                    }
                }
            }

            # Sleep 500ms quantum to allow exact-second clock transition accuracy
            Start-Sleep -Milliseconds 500
        }
    }
    finally {
        Write-ClientLog "Client agent stopping cleanly." -Level INFO
        if ($null -ne $script:AppMutex) {
            $script:AppMutex.ReleaseMutex()
            $script:AppMutex.Dispose()
        }
    }
}

# Run Agent
Start-ClientAgent -Path $script:ConfigPath -HostOverride $HostAddress
