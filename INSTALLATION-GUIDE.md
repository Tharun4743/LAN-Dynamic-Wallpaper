# 📖 LAN Dynamic Wallpaper: Installation & Deployment Guide

This guide details the complete deployment lifecycle for the LAN Dynamic Wallpaper Slideshow System across 1 Host Administrator PC and 30–100 Client Workstations on a local wired Ethernet LAN.

---

## 📋 System Prerequisites

### Host PC (The Central Administrator Computer)
- **Operating System**: Windows 11 (all versions) or Windows 10 (Version 1809 or newer, Pro / Enterprise / Education / Home).
- **PowerShell**: Windows PowerShell 5.1 (built into Windows) or PowerShell 7.x.
- **Permissions**: Administrator privileges required to bind the HTTP service on port `8765`, configure Windows Firewall rules, and reserve the URL ACL.
- **Network**: Static IPv4 address or DHCP reservation recommended on the wired Ethernet adapter.
- **Port Availability**:
  - `TCP 8765`: HTTP API and image streaming endpoint.
  - `UDP 8766`: Automated discovery responder.

### Client PCs (All 30–100 Workstations)
- **Operating System**: Windows 11 or Windows 10.
- **PowerShell**: Windows PowerShell 5.1 (built into Windows).
- **Permissions**: Administrator rights are required only once during initial setup (`Start-Client.bat`) to register automatic background startup. Normal ongoing wallpaper rotation runs as a **standard user** in the interactive desktop session.
- **Network**: Wired Ethernet or Wi-Fi connection on the same subnet as the Host (or routable LAN with static IP configuration).

---

## ⚡ The Two-Launcher Experience

The entire system is controlled by **exactly two user-facing batch files**:

| Launcher | Where to Run | Permissions | Primary Action |
| :--- | :--- | :--- | :--- |
| **`Start-Host.bat`** | On the Host Administrator PC | **Run as administrator** | Configures firewall, reserves URL ACL, opens `Wallpapers/` folder, starts HTTP/UDP service, and begins host desktop slideshow. |
| **`Start-Client.bat`** | On each Client Workstation | **Run as administrator** (initial setup) | Discovers Host on LAN, registers client node, downloads wallpapers into local cache, configures auto-start at user logon, and begins desktop rotation. |

---

## 🖥️ Step-by-Step Installation

### Part 1: Host PC Setup

1. Copy or clone the `LAN-Dynamic-Wallpaper` repository to the designated Host PC.
2. Right-click **`Start-Host.bat`** and select **Run as administrator**.
3. If prompted by Windows User Account Control (UAC), click **Yes**.
4. The host manager will automatically:
   - Check and validate the Windows PowerShell environment.
   - Idempotently configure Windows Defender Firewall rules for inbound TCP `8765` and UDP `8766` on `Private,Domain` network profiles.
   - Idempotently reserve the HTTP.sys URL ACL (`http://+:8765/`).
   - If `HostConfig.json` lacks secrets, generate fresh 256-bit cryptographic keys (`AdminSecret` and `AuthSecret`) and secure the configuration with restrictive Windows ACLs.
   - Automatically open the **`Wallpapers/`** folder in Windows Explorer on your screen.
5. **Drop your photo files** into this `Wallpapers/` folder:
   - Supported formats: **`.jpg`**, **`.jpeg`**, **`.png`**, **`.bmp`**, **`.gif`**, **`.webp`**, **`.tiff`**.
6. The host server immediately synchronizes the images, applies the initial wallpaper to the Host PC desktop, and begins rotating through the collection every **5 seconds**.
7. Keep the `Start-Host.bat` console window open (you may minimize it).

### Part 2: Client Workstation Deployment (30–100 PCs)

1. Copy the project folder to the client computer (via USB flash drive or local network share).
2. Right-click **`Start-Client.bat`** and select **Run as administrator** for initial setup.
3. The client launcher will automatically:
   - Validate PowerShell 5.1+ and required scripts.
   - Broadcast a UDP discovery probe on port `8766` (with fast subnet sweep fallback).
   - Locate the Host PC and query its health endpoint (`/api/v1/health`).
   - Register the client node with the Host (`POST /api/v1/auth/register`), receiving an assigned Client ID and secure client token.
   - Download the wallpaper collection manifest and sync images into the local `Cache/` directory.
   - Verify each downloaded image's SHA-256 hash before applying.
   - Immediately update the client workstation's visible desktop wallpaper.
   - Register silent background startup in the Windows user registry (`HKCU:\Software\Microsoft\Windows\CurrentVersion\Run`).
4. **Daily Ongoing Operation**:
   - Users do **NOT** need to run `Start-Client.bat` every day.
   - When a student or employee logs into Windows, the wallpaper agent starts automatically in their interactive user desktop session and maintains synchronized rotation in the background.

---

## 🖼️ Dynamic Wallpaper Synchronization Lifecycle

Once the Host and Clients are running, managing content requires zero command typing:

- **Adding a Photo**:
  Drop any supported image file into the `Wallpapers/` folder on the Host PC.
  Within 10 seconds, all connected client computers will automatically download the new file and add it into their active rotation cycle.
- **Replacing a Photo**:
  Overwrite an existing file in `Wallpapers/` with an updated image using the same filename.
  The Host detects the changed SHA-256 hash, increments the collection version, and client workstations update their cached copy seamlessly.
- **Deleting a Photo**:
  Delete the file from `Wallpapers/` on the Host PC.
  The Host updates the manifest. On their next polling cycle, client workstations prune the deleted file from their local cache and continue rotating through remaining wallpapers without interruption.

---

## 🔧 Enterprise Deployment via Network Share

For large-scale computer labs or school deployments:

1. Place the project on a central read-only LAN file share:
   `\\FileServer\Shares\LAN-Dynamic-Wallpaper`
2. Create an Active Directory Group Policy Object (GPO) or computer startup script to run initial setup on client machines:
   ```cmd
   cmd.exe /c "\\FileServer\Shares\LAN-Dynamic-Wallpaper\Start-Client.bat"
   ```
3. Alternatively, deploy a logon script executing the client agent directly:
   ```powershell
   powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "\\FileServer\Shares\LAN-Dynamic-Wallpaper\Client\Client.ps1"
   ```

---

## 🧪 Automated Testing & Verification

To verify all system components without adding extra batch files, execute the master test suite using PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File Tests\Run-All-Tests.ps1
```

The automated test harness executes 5 comprehensive integration test suites:
1. **`Test-Publisher.ps1`**: Validates file locks, magic-byte inspection, SHA-256 recalculation, and atomic manifest publishing.
2. **`Test-Client.ps1`**: Validates Win32 P/Invoke desktop wallpaper rotation, deterministic cycling, cache retention, and mutex duplicate prevention.
3. **`Test-Host.ps1`**: Validates HTTP listener routing, client registration, authenticated manifest delivery, binary asset streaming, and RBAC authorization guards.
4. **`Test-Security.ps1`**: Validates path traversal attack rejection (`..`, `%2f`, `%5c`), authentication bypass protection, and zero information leakage.
5. **`Test-100Clients.ps1`**: Executes a 100-client concurrent load simulation (400 HTTP requests in ~1 second) to guarantee multi-client fleet stability.

---

## 🚨 Troubleshooting & Actionable Error Recovery

### Error: Host Fails to Bind Port 8765
- **Cause**: Port `8765` is in use by another application or the launcher was run without administrator privileges.
- **Fix**: Right-click `Start-Host.bat` and select **Run as administrator**. To inspect what process is using the port, run:
  ```powershell
  Get-NetTCPConnection -LocalPort 8765
  ```

### Error: Client Reports "UDP Discovery Silent / Host Not Found"
- **Cause**: Network switches or VLAN routers are dropping UDP broadcast traffic between subnets.
- **Fix**: Open `Client\ClientConfig.json` in Notepad on the client PC. Enter the Host PC's IP address directly:
  ```json
  "HostAddress": "192.168.1.50"
  ```
  Save the file and run `Start-Client.bat` again.

### Error: Desktop Wallpaper Does Not Update
- **Cause**: The process is running in a non-interactive session or Windows personalization is locked to Windows Spotlight.
- **Fix**: Ensure the agent is running under the interactive logged-in user. In Windows **Settings** -> **Personalization** -> **Background**, set the background mode to **Picture**.

---

## 🗑️ Safe Uninstallation

### To Remove Client Workstation Setup:
1. Close the client window or terminate any running client process:
   ```powershell
   Get-Process -Name "powershell" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like "*Client Workstation*" } | Stop-Process -Force
   ```
2. Remove the Windows logon auto-start entry:
   ```powershell
   Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "LAN-Dynamic-Wallpaper-Client" -ErrorAction SilentlyContinue
   ```
3. Delete the local `Cache/` folder and project files.

### To Remove Host Server Setup:
1. Close the `Start-Host.bat` console window.
2. Delete the Windows Firewall rules:
   ```powershell
   Remove-NetFirewallRule -DisplayName "LAN-Dynamic-Wallpaper-Host-*" -ErrorAction SilentlyContinue
   ```
3. Remove the HTTP.sys URL ACL reservation:
   ```cmd
   netsh http delete urlacl url=http://+:8765/
   ```
