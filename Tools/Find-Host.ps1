# ==============================================================================
# Tools/Find-Host.ps1
# LAN Dynamic Wallpaper - UDP Broadcast Host Discovery Tool
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$DiscoveryPort = 8766,

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSeconds = 4
)

Set-StrictMode -Version Latest

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " LAN DYNAMIC WALLPAPER - HOST DISCOVERY UTILITY" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "Broadcasting discovery packet on UDP port $DiscoveryPort (Timeout: ${TimeoutSeconds}s)..." -ForegroundColor Gray

$udp = New-Object System.Net.Sockets.UdpClient
$udp.EnableBroadcast = $true
$udp.Client.ReceiveTimeout = ($TimeoutSeconds * 1000)

$foundHosts = @()

try {
    $reqBytes = [System.Text.Encoding]::UTF8.GetBytes("LAN_WALLPAPER_DISCOVER_REQ")
    $broadcastEp = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Broadcast, $DiscoveryPort)
    [void]$udp.Send($reqBytes, $reqBytes.Length, $broadcastEp)

    # Dynamically compute and broadcast on all active local subnets
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

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $remoteEp = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)

    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        try {
            $recvBytes = $udp.Receive([ref]$remoteEp)
            $json = [System.Text.Encoding]::UTF8.GetString($recvBytes)
            $resp = $json | ConvertFrom-Json
            if ($resp -and $resp.service -eq "LAN_WALLPAPER_HOST" -and -not [string]::IsNullOrWhiteSpace($resp.ip)) {
                $parsedIp = $null
                if ([System.Net.IPAddress]::TryParse($resp.ip, [ref]$parsedIp) -and ($resp.port -gt 0 -and $resp.port -le 65535)) {
                    $foundHosts += $resp
                }
            }
        }
        catch [System.Net.Sockets.SocketException] {
            break # Timeout reached
        }
    }
}
catch {
    Write-Error "Discovery error: $($_.Exception.Message)"
}
finally {
    $udp.Close()
    $udp.Dispose()
}

# Subnet sweep fallback if UDP broadcast was dropped
if ($foundHosts.Count -eq 0) {
    Write-Host "UDP broadcast returned no response. Running rapid /24 subnet HTTP probe on port 8765..." -ForegroundColor Gray
    try {
        $adapters = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" }

        foreach ($a in $adapters) {
            $localIp = $a.IPAddress
            $lastDot = $localIp.LastIndexOf('.')
            if ($lastDot -le 0) { continue }
            $subnetPrefix = $localIp.Substring(0, $lastDot)

            $tasks = New-Object System.Collections.Generic.List[object]
            foreach ($octet in 1..254) {
                $targetIp = "$subnetPrefix.$octet"
                $tcp = New-Object System.Net.Sockets.TcpClient
                $iar = $tcp.BeginConnect($targetIp, 8765, $null, $null)
                $tasks.Add([PSCustomObject]@{ Ip = $targetIp; Tcp = $tcp; Iar = $iar })
            }

            Start-Sleep -Milliseconds 400

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
                    if ($healthJson -and $healthJson.service -eq "LAN_WALLPAPER_HOST") {
                        $foundHosts += [PSCustomObject]@{
                            service   = "LAN_WALLPAPER_HOST"
                            hostname  = if ($healthJson.PSObject.Properties['hostname']) { $healthJson.hostname } else { "Host-$rIp" }
                            ip        = $rIp
                            port      = 8765
                            version   = if ($healthJson.PSObject.Properties['collectionVersion']) { $healthJson.collectionVersion } else { "1.0" }
                            timestamp = [DateTime]::UtcNow.ToString("o")
                        }
                    }
                } catch {}
            }
        }
    } catch {}
}

Write-Host ""
if ($foundHosts.Count -eq 0) {
    Write-Host "No active Host PCs responded on UDP port $DiscoveryPort." -ForegroundColor Yellow
    Write-Host "Possible causes:" -ForegroundColor Gray
    Write-Host "  1. Host server is not running (execute 1-Start-Host.bat on Host PC)." -ForegroundColor Gray
    Write-Host "  2. Host firewall is blocking UDP port $DiscoveryPort (run Installer\Configure-Firewall.ps1 on Host)." -ForegroundColor Gray
    Write-Host "  3. Wired network switch or router drops UDP broadcast traffic between subnets." -ForegroundColor Gray
}
elseif ($foundHosts.Count -eq 1) {
    $h = $foundHosts[0]
    Write-Host "Found 1 Active Host PC:" -ForegroundColor Green
    Write-Host "  Hostname   : $($h.hostname)" -ForegroundColor White
    Write-Host "  IP Address : $($h.ip)" -ForegroundColor Cyan
    Write-Host "  HTTP Port  : $($h.port)" -ForegroundColor Cyan
    Write-Host "  Version    : $($h.version)" -ForegroundColor Gray
}
else {
    Write-Host "WARNING: Multiple Host PCs ($($foundHosts.Count)) responded on this LAN subnet!" -ForegroundColor Yellow
    $foundHosts | Format-Table -Property hostname, ip, port, version, timestamp -AutoSize
    Write-Host "Ensure only one central Host is publishing wallpapers, or configure ClientConfig.json manually." -ForegroundColor Yellow
}
Write-Host "==============================================================================" -ForegroundColor Cyan
