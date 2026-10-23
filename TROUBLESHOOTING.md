# 🛠️ LAN Dynamic Wallpaper: Diagnostic & Troubleshooting Guide

This guide provides troubleshooting workflows, diagnostic commands, and remediation runbooks for the LAN Dynamic Wallpaper Slideshow System.

---

## 🧰 Built-in Diagnostic Tool Suite

Before attempting manual troubleshooting, execute the diagnostic scripts located in the `Tools\` directory.

| Script | Purpose | When to Use |
| :--- | :--- | :--- |
| `Tools/Diagnose.ps1` | Comprehensive system health check | Run on Host or Client to inspect firewall rules, ports, tasks, registry, and logs |
| `Tools/Find-Host.ps1` | UDP broadcast network probe | Run on Client PC if automatic discovery is not locating the Host |
| `Tools/Test-Connection.ps1` | End-to-end network & authentication test | Run on Client PC to test TCP handshake, HTTP latency, and token validity |
| `Tools/Deployment-Report.ps1` | Fleet telemetry dashboard | Run on Host PC to view online, stale, and offline client workstations |

---

## 🔍 Common Failure Scenarios & Solutions

### Scenario 1: Client Cannot Connect to Host ("Host Unreachable" or Timeout)
**Symptoms**: Client logs show `Cannot connect to host http://192.168.x.x:8765: Unable to connect to remote server`.

**Diagnostic Steps**:
1. On the **Client PC**, run:
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\Tools\Test-Connection.ps1 -HostIp <HOST_IP>
   ```
2. On the **Host PC**, verify that the host process is actively listening on TCP port `8765`:
   ```powershell
   Get-NetTCPConnection -LocalPort 8765 -ErrorAction SilentlyContinue
   ```
3. Test TCP reachability from the client:
   ```powershell
   Test-NetConnection -ComputerName <HOST_IP> -Port 8765
   ```

**Remediation**:
- **Firewall blocked**: Launch `1-Start-Host.bat` as Administrator on the Host PC (it automatically registers Windows Firewall rules for TCP 8765 and UDP 8766).
- **Wrong Host IP**: Verify the host's actual IPv4 address using `Get-NetIPAddress -AddressFamily IPv4` on the Host PC and update `Client\ClientConfig.json`.
- **Network Profile**: Ensure the Ethernet network connection is set to **Private** or **Domain**, not Public:
  ```powershell
  Set-NetConnectionProfile -InterfaceAlias "Ethernet" -NetworkCategory Private
  ```

---

### Scenario 2: Automatic Host Discovery Fails
**Symptoms**: Running `Find-Host.ps1` prints `No response received from broadcast discovery`.

**Cause**: Many enterprise managed switches, VLANs, and routers block UDP broadcast packets (`255.255.255.255`) across subnets.

**Remediation (Static Fallback)**:
The client is architected to operate flawlessly with a static IP configuration without relying on UDP broadcast.
1. Open `Client\ClientConfig.json` on the client workstation.
2. Set `HostIp` directly to the Host PC's static IP address:
   ```json
   {
     "Host": {
       "HostIp": "192.168.1.50",
       "Port": 8765,
       "AutoDiscover": false
     }
   }
   ```
3. Save the file. The client will immediately bypass broadcast discovery and connect directly.

---

### Scenario 3: Authentication Error (HTTP 401 Unauthorized)
**Symptoms**: Client logs report `HTTP 401 Unauthorized: Invalid authentication secret`.

**Cause**: The `AuthSecret` token in `ClientConfig.json` does not match the `AuthSecret` defined in the Host's `HostConfig.json`.

**Remediation**:
1. On the **Host PC**, inspect `Host\HostConfig.json` to find the current `AuthSecret`:
   ```json
   "Security": {
     "AuthSecret": "<your_256_bit_client_token>",
     ...
   }
   ```
2. On the **Client PC**, enter this token when prompted by `2-Start-Client.bat` or save it directly into `Client\ClientConfig.json` under `"AuthSecret"`.

---

### Scenario 4: Wallpaper Does Not Change on the Desktop
**Symptoms**: Client logs show successful download and image rotation, but the desktop wallpaper remains unchanged.

**Common Causes & Remediation**:
1. **Service Running in Wrong Session**:
   - The wallpaper agent must run inside the **interactive user session**, NOT as a noninteractive background SYSTEM service.
   - Verify that the scheduled task `LAN-Dynamic-Wallpaper-Client` is configured to run as `Users` or the logged-in user at logon.
2. **Windows Slideshow Conflict**:
   - If Windows personalization is set to Windows Spotlight or Windows Slideshow, Windows may overwrite the wallpaper.
   - Open **Settings** -> **Personalization** -> **Background** and set background to **Picture**.
3. **Corrupted Registry Key**:
   - Check the active desktop wallpaper registry key:
     ```powershell
     Get-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name Wallpaper
     ```
   - Test manual API wallpaper application:
     ```powershell
     . .\Client\Wallpaper.ps1
     Set-DesktopWallpaper -ImagePath "C:\Full\Path\To\Cache\image.jpg"
     ```

---

### Scenario 5: Image Dropped in Wallpapers Folder is Not Showing
**Symptoms**: Administrator copies an image into `Wallpapers\`, but clients never receive it and `manifest.json` does not update.

**Diagnostic Check**:
1. Open the Host log: `Logs\host-YYYY-MM-DD.log`.
2. Look for validation warnings:
   - `Image validation failed for 'test.jpg': Invalid JPEG header bytes`
   - `Image validation failed for 'large.png': File exceeds maximum size`
   - `Skipping non-image extension: 'document.pdf'`

**Remediation**:
- **Format check**: Ensure the file is a true JPEG, PNG, or BMP image. Renaming an `.exe` or `.txt` file to `.jpg` will be rejected by the magic-byte validator.
- **Size limit**: By default, the host enforces a 25 MB limit (`26214400` bytes). Increase `MaxImageSizeBytes` in `HostConfig.json` if using high-resolution 4K/8K images.
- **Copy lock**: Ensure the file is not held open by an editing tool (e.g. Photoshop). The publisher waits up to 5 retries for locks to release.

---

### Scenario 6: Scheduled Task Does Not Start at Windows Login
**Symptoms**: Workstation reboots and the client slideshow does not start until manually launched.

**Diagnostic Check**:
Run in PowerShell:
```powershell
Get-ScheduledTask -TaskName "LAN-Dynamic-Wallpaper-Client" | Select-Object TaskName, State
Get-ScheduledTaskInfo -TaskName "LAN-Dynamic-Wallpaper-Client"
```

**Remediation**:
- Verify the task status is `Ready`. If `Disabled`, enable it:
  ```powershell
  Enable-ScheduledTask -TaskName "LAN-Dynamic-Wallpaper-Client"
  ```
- Check task history in Windows Event Viewer: **Applications and Services Logs** -> **Microsoft** -> **Windows** -> **TaskScheduler** -> **Operational**.
- Re-register the startup task cleanly:
  ```powershell
  powershell.exe -ExecutionPolicy Bypass -File .\Installer\Configure-Startup.ps1 -Target Client -Action Install
  ```

---

## 📜 Log Analysis & Rotating Log Locations

All application events are logged with microsecond UTC timestamps, log severity levels (`INFO`, `WARN`, `ERROR`, `AUDIT`), and remote client IP addresses:

- **Host Logs**: `Host\..\Logs\host-YYYY-MM-DD.log`
  ```
  [2026-10-23 02:14:10.123] [AUDIT] [192.168.1.105] Client registered successfully: CLT-A1B2C3D4 (LAB-PC-05)
  [2026-10-23 02:14:10.234] [INFO] [192.168.1.105] Served asset: campus.jpg (Hash: e3b0c442...)
  ```
- **Client Logs**: `Client\..\Logs\client-YYYY-MM-DD.log`
  ```
  [2026-10-23 02:14:12.456] [INFO] [-] Synchronized collection v20261022204411_f5f6e097 (5 images in cache)
  [2026-10-23 02:15:12.789] [INFO] [-] Advanced desktop wallpaper to: event.jpg (Index 2/5)
  ```

---

## 🚨 Recovery & Rollback Runbook

### Emergency Rollback: Reverting to Default Windows Wallpaper
If an unintended image is published to all workstations:
1. Delete the image from `Wallpapers\` on the Host PC.
2. The Host automatically broadcasts the updated collection without the deleted image.
3. Within 10 seconds, all client workstations remove the file from their active slideshow.
4. To force an immediate update across all clients, trigger an administrative force-sync:
   ```powershell
   $headers = @{ "Authorization" = "Bearer <ADMIN_SECRET>" }
   Invoke-RestMethod -Uri "http://127.0.0.1:8765/api/v1/admin/sync" -Method Post -Headers $headers
   ```
