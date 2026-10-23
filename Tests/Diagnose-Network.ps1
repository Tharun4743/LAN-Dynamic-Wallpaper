Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Write-Host "=== LAN DYNAMIC WALLPAPER - NETWORK SHARING DIAGNOSTIC ===" -ForegroundColor Cyan
Write-Host ""

# 1. Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host "[1] Running as Administrator: $isAdmin" -ForegroundColor $(if ($isAdmin) { "Green" } else { "Red" })

# 2. Windows Edition
$os = (Get-CimInstance Win32_OperatingSystem).Caption
Write-Host "[2] Windows Edition: $os"
$isHome = $os -match 'Home'
if ($isHome) {
    Write-Host "    WARNING: Windows Home has limited SMB server support" -ForegroundColor Yellow
}

# 3. LanmanServer
$svc = Get-Service -Name LanmanServer -ErrorAction SilentlyContinue
Write-Host "[3] LanmanServer service: $($svc.Status)" -ForegroundColor $(if ($svc.Status -eq 'Running') { "Green" } else { "Red" })

# 4. SMB config
$smbCfg = Get-SmbServerConfiguration -ErrorAction SilentlyContinue
Write-Host "[4] SMB2 enabled: $($smbCfg.EnableSMB2Protocol)"
Write-Host "    SMB1 enabled: $($smbCfg.EnableSMB1Protocol)"

# 5. Network IP
Write-Host "[5] Network adapters:"
Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
    Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.*' } | 
    ForEach-Object { Write-Host "    $($_.InterfaceAlias): $($_.IPAddress)" -ForegroundColor Green }

# 6. Port 445
Write-Host "[6] Port 445 listeners:"
$port445 = netstat -ano 2>$null | Select-String ':445 '
if ($port445) { $port445 | ForEach-Object { Write-Host "    $_" } } else { Write-Host "    NONE - SMB port not listening!" -ForegroundColor Red }

# 7. Existing shares
Write-Host "[7] Current SMB shares:"
$shares = Get-SmbShare -ErrorAction SilentlyContinue
foreach ($s in $shares) {
    Write-Host "    $($s.Name) -> $($s.Path)" -ForegroundColor $(if ($s.Name -like 'LAN*') { "Yellow" } else { "DarkGray" })
}

# 8. Stale old share
$oldShare = Get-SmbShare -Name "LAN-Dynamic-Wallpaper" -ErrorAction SilentlyContinue
if ($oldShare) {
    Write-Host "[8] STALE OLD SHARE FOUND: LAN-Dynamic-Wallpaper -> $($oldShare.Path)" -ForegroundColor Red
    Write-Host "    This is from the old architecture and should be removed." -ForegroundColor Red
} else {
    Write-Host "[8] No stale old share found (good)" -ForegroundColor Green
}

# 9. Client folder check
$scriptRoot = Split-Path -Parent $PSScriptRoot  # Go up from Tests/ to project root
$clientPath = Join-Path $scriptRoot "Client"
Write-Host "[9] Client folder: $clientPath"
Write-Host "    Exists: $(Test-Path $clientPath)"
if (Test-Path $clientPath) {
    $files = Get-ChildItem -LiteralPath $clientPath
    foreach ($f in $files) {
        Write-Host "    $($f.Name) ($($f.Length) bytes)" -ForegroundColor Green
    }
}

# 10. Test share creation (only if admin)
if ($isAdmin) {
    Write-Host "[10] Testing share creation..."
    $testShareName = "LAN-WP-DiagTest-$((Get-Random))"
    try {
        New-SmbShare -Name $testShareName -Path $clientPath -ReadAccess "Everyone" -ErrorAction Stop | Out-Null
        Write-Host "     Share creation: SUCCESS" -ForegroundColor Green
        Remove-SmbShare -Name $testShareName -Force -ErrorAction SilentlyContinue
        Write-Host "     Share removal: SUCCESS" -ForegroundColor Green
    } catch {
        Write-Host "     Share creation FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "[10] Skipping share creation test (not admin)" -ForegroundColor Yellow
}

# 11. Firewall File Sharing rules for Private profile
Write-Host "[11] File Sharing firewall (Private profile):"
$fsRules = Get-NetFirewallRule -DisplayGroup "File and Printer Sharing" -ErrorAction SilentlyContinue |
    Where-Object { $_.Profile -match 'Private' -and $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' }
$fsCount = @($fsRules).Count
Write-Host "     $fsCount inbound rules enabled for Private profile" -ForegroundColor $(if ($fsCount -gt 0) { "Green" } else { "Red" })

# 12. Network profile (Private vs Public)
Write-Host "[12] Network connection profiles:"
Get-NetConnectionProfile -ErrorAction SilentlyContinue | ForEach-Object {
    $color = if ($_.NetworkCategory -eq 'Private') { "Green" } elseif ($_.NetworkCategory -eq 'DomainAuthenticated') { "Green" } else { "Red" }
    Write-Host "     $($_.InterfaceAlias): $($_.NetworkCategory)" -ForegroundColor $color
    if ($_.NetworkCategory -eq 'Public') {
        Write-Host "     ^ WARNING: Public network blocks file sharing! Change to Private." -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== DIAGNOSTIC COMPLETE ===" -ForegroundColor Cyan
