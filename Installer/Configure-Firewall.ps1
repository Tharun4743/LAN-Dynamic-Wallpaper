# ==============================================================================
# Installer/Configure-Firewall.ps1
# LAN Dynamic Wallpaper - Automated Windows Firewall Rule Manager
# Scoped specifically to LAN subnet, Private/Domain profiles only
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$HttpPort = 8765,

    [Parameter(Mandatory = $false)]
    [int]$DiscoveryPort = 8766,

    [Parameter(Mandatory = $false)]
    [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Verify Administrator elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "Firewall configuration requires administrative privileges. Please re-run from an elevated PowerShell prompt."
}

$httpRuleName = "LAN-Dynamic-Wallpaper-Host-HTTP"
$udpRuleName  = "LAN-Dynamic-Wallpaper-Host-UDP"

if ($Remove) {
    Write-Host "Removing LAN Dynamic Wallpaper firewall rules..." -ForegroundColor Yellow
    Remove-NetFirewallRule -DisplayName $httpRuleName -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName $udpRuleName -ErrorAction SilentlyContinue
    Write-Host "Firewall rules removed successfully." -ForegroundColor Green
    return
}

Write-Host "Configuring Windows Defender Firewall for LAN Dynamic Wallpaper..." -ForegroundColor Cyan

# Remove existing rules first to guarantee clean idempotent state
Remove-NetFirewallRule -DisplayName $httpRuleName -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName $udpRuleName -ErrorAction SilentlyContinue

# Rule 1: HTTP Server (TCP Inbound)
New-NetFirewallRule -DisplayName $httpRuleName `
    -Description "Inbound HTTP rule for LAN Dynamic Wallpaper host server" `
    -Direction Inbound `
    -LocalPort $HttpPort `
    -Protocol TCP `
    -Action Allow `
    -Profile Private, Domain `
    -Enabled True | Out-Null

Write-Host "  [OK] Inbound TCP Rule Created: Port $HttpPort (Private/Domain profiles)" -ForegroundColor Green

# Rule 2: UDP Discovery Responder (UDP Inbound)
New-NetFirewallRule -DisplayName $udpRuleName `
    -Description "Inbound UDP broadcast rule for LAN Dynamic Wallpaper zero-config discovery" `
    -Direction Inbound `
    -LocalPort $DiscoveryPort `
    -Protocol UDP `
    -Action Allow `
    -Profile Private, Domain `
    -Enabled True | Out-Null

Write-Host "  [OK] Inbound UDP Rule Created: Port $DiscoveryPort (Private/Domain profiles)" -ForegroundColor Green
Write-Host "Firewall configuration completed successfully." -ForegroundColor Green
