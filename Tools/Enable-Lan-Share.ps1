# ==============================================================================
# Tools/Enable-Lan-Share.ps1
# Configures Windows SMB Network Share with No Password Required for Lab PCs
# ==============================================================================

[CmdletBinding()]
param(
    [string]$ShareName = "LAN-Dynamic-Wallpaper",
    [string]$FolderPath = "c:\Users\tharu\Downloads\IT\LAN-Dynamic-Wallpaper"
)

# Check Administrator
net session >nul 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[INFO] Requesting Administrator elevation to configure Windows Network Share..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "==============================================================================" -ForegroundColor Green
Write-Host " CONFIGURING WINDOWS LAN NETWORK SHARE (NO PASSWORD NEEDED)" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green

# 1. Grant NTFS Read & Execute permissions to Everyone and Guests
Write-Host "1. Setting folder NTFS access permissions for 'Everyone'..." -ForegroundColor Cyan
$acl = Get-Acl -LiteralPath $FolderPath
$ruleEveryone = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.SetAccessRule($ruleEveryone)
Set-Acl -LiteralPath $FolderPath -AclObject $acl

# 2. Create or update the SMB Share
Write-Host "2. Creating Windows SMB Share '$ShareName'..." -ForegroundColor Cyan
if (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue) {
    Remove-SmbShare -Name $ShareName -Force -ErrorAction SilentlyContinue | Out-Null
}
New-SmbShare -Name $ShareName -Path $FolderPath -ReadAccess "Everyone" -FullAccess "Administrators" -ErrorAction Stop | Out-Null

# 3. Disable Password-Protected Sharing in Windows Registry
Write-Host "3. Permitting Guest and Anonymous LAN access (No Password Prompt)..." -ForegroundColor Cyan
try {
    # Allow anonymous read
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "NullSessionShares" -Value @($ShareName) -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "everyoneincludesanonymous" -Value 1 -Force -ErrorAction SilentlyContinue
} catch {}

# 4. Detect IP
$gwRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Where-Object { $_.NextHop -ne "0.0.0.0" } | Sort-Object RouteMetric | Select-Object -First 1
$ip = if ($gwRoute) {
    (Get-NetIPAddress -InterfaceIndex $gwRoute.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "127.*" } | Select-Object -First 1).IPAddress
} else {
    [System.Environment]::MachineName
}

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host " SUCCESS! Folder is now shared across LAN without passwords." -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host " Any client PC in your lab can now open File Explorer and type:" -ForegroundColor Yellow
Write-Host "   \\$ip\$ShareName" -ForegroundColor Cyan
Write-Host " Or:" -ForegroundColor Yellow
Write-Host "   \\$([System.Environment]::MachineName)\$ShareName" -ForegroundColor Cyan
Write-Host ""
Write-Host " They can simply double-click '2-Start-Client.bat' to start!" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host "Press any key to close..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
