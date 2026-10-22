# ==============================================================================
# Installer/Configure-Startup.ps1
# LAN Dynamic Wallpaper - Windows Task Scheduler Automation
# Idempotent startup registration for Host (System/Admin) and Client (Interactive User)
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Host", "Client")]
    [string]$Role,

    [Parameter(Mandatory = $false)]
    [string]$AppRoot = (Split-Path $PSScriptRoot -Parent),

    [Parameter(Mandatory = $false)]
    [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$taskName = if ($Role -eq "Host") { "LAN-Dynamic-Wallpaper-Host" } else { "LAN-Dynamic-Wallpaper-Client" }

if ($Remove) {
    Write-Host "Unregistering scheduled task '$taskName'..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Task '$taskName' unregistered successfully." -ForegroundColor Green
    return
}

# Clean existing task idempotently
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$psExe = (Get-Process -Id $PID).Path
if (-not (Test-Path $psExe)) {
    $psExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
}

if ($Role -eq "Host") {
    $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $AppRoot "Host\Host.ps1"))
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Host script does not exist at: $scriptPath"
    }

    $action = New-ScheduledTaskAction -Execute $psExe -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 0)

    # Register task for highest privileges on system startup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    try {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "LAN Dynamic Wallpaper Host Service" -Force | Out-Null
        Write-Host "  [OK] Host Scheduled Task '$taskName' registered to execute AtStartup as SYSTEM." -ForegroundColor Green
    }
    catch {
        # Fallback to current admin user if SYSTEM registration fails
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $userTrigger = New-ScheduledTaskTrigger -AtLogOn
        $userPrincipal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $userTrigger -Settings $settings -Principal $userPrincipal -Description "LAN Dynamic Wallpaper Host Service" -Force | Out-Null
        Write-Host "  [OK] Host Scheduled Task '$taskName' registered to execute AtLogon as $currentUser (Highest Privileges)." -ForegroundColor Green
    }
}
else {
    # CLIENT ROLE: Must execute in the interactive logged-in user desktop session
    $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $AppRoot "Client\Client.ps1"))
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Client script does not exist at: $scriptPath"
    }

    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $action = New-ScheduledTaskAction -Execute $psExe -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 0)
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "LAN Dynamic Wallpaper Client Slideshow Agent" -Force | Out-Null
    Write-Host "  [OK] Client Scheduled Task '$taskName' registered to execute AtLogon for user $currentUser in desktop session." -ForegroundColor Green
}
