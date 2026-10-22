# 📖 LAN Dynamic Wallpaper: Installation & Deployment Guide

This guide details the complete deployment lifecycle for the LAN Dynamic Wallpaper Slideshow System across 1 Host Administrator PC and 30–100 Client Workstations on a local wired Ethernet LAN.

---

## 📋 System Prerequisites

### Host PC
- **Operating System**: Windows 11 (21H2 or newer) or Windows 10 (1809 or newer), Pro / Enterprise / Education.
- **PowerShell**: Windows PowerShell 5.1 (built-in) or PowerShell 7.x.
- **Permissions**: Administrator privileges required for initial setup (firewall configuration, scheduled task creation, and URL ACL binding).
- **Network**: Static IPv4 address or DHCP reservation recommended on the wired Ethernet adapter.
- **Port Availability**:
  - `TCP 8765`: HTTP API and image streaming endpoint.
  - `UDP 8766`: Automated discovery responder.

### Client PCs (30–100 Workstations)
- **Operating System**: Windows 11 or Windows 10.
- **PowerShell**: Windows PowerShell 5.1 (built-in).
- **Permissions**: Standard User session permissions. **Does NOT require administrative rights to update the user's desktop wallpaper**.
- **Network**: Wired Ethernet connection on the same subnet as the Host (or routable LAN with static IP configuration).

---

## ⚡ Quick Run (The 3 Core Batch Files)

For rapid zero-setup deployment, copy the `LAN-Dynamic-Wallpaper` folder and run:
1. **On Host PC**: Double-click **`1-Start-Host.bat`** (Starts host server, publishes wallpapers, and begins host desktop slideshow).
2. **On Client PCs**: Double-click **`2-Start-Client.bat`** (Discovers host, syncs wallpapers, and begins client desktop slideshow).
3. **Automated Verification**: Double-click **`3-Test-System.bat`** (Runs all 5 test suites).

---

## 🖥️ Part 1: Host PC Installation & Persistent Service Setup

### Step 1.1: Run Elevated Host Installer
1. Open File Explorer and navigate to the project directory: `LAN-Dynamic-Wallpaper\Installer`.
2. Right-click `Install-Host.bat` and select **Run as Administrator** (or choose Option 4 in `Run-All.bat`).
3. Alternatively, launch an elevated PowerShell prompt and execute:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   .\Installer\Install-Host.ps1
   ```

### Step 1.2: Actions Performed Automatically
The installer performs the following operations without requiring manual intervention:
1. **Compatibility Check**: Confirms OS version and PowerShell 5.1+ runtime.
2. **Directory Scaffolding**: Verifies and initializes `Wallpapers\`, `Published\`, and `Logs\`.
3. **Cryptographic Credential Generation**:
   - Generates a 256-bit random client authentication token (`AuthSecret`).
   - Generates a 256-bit random administrator management key (`AdminSecret`).
   - Stores secrets in `Host\HostConfig.json`.
4. **Adapter IP Discovery**: Detects the active Ethernet network adapter and binds to its IPv4 address.
5. **Windows Firewall Rule Creation**:
   - `LAN-Dynamic-Wallpaper-Host-HTTP` (Inbound TCP `8765`, scoped to Private and Domain profiles).
   - `LAN-Dynamic-Wallpaper-Host-Discovery` (Inbound UDP `8766`, scoped to Private and Domain profiles).
6. **HTTP.sys URL ACL Registration**: Registers `http://+:8765/` to allow the HTTP listener to serve LAN traffic smoothly.
7. **Task Scheduler Registration**: Creates the scheduled task `LAN-Dynamic-Wallpaper-Host` configured to run at system startup with high priority and automatic restart on failure.
8. **Client Package Generation**: Packages all necessary client files (`Client.ps1`, `Wallpaper.ps1`, pre-configured `ClientConfig.json`, `Install-Client.bat`) into `Installer\Client-Package\`.
9. **Health Verification**: Pings `http://127.0.0.1:8765/api/v1/health` to confirm the host is live.

---

## 🖼️ Part 2: Dynamic Wallpaper Management

The administrator manages the active desktop slideshow simply by managing files in the `Wallpapers\` folder on the Host PC:

### Adding New Images
1. Copy any valid image (`.jpg`, `.jpeg`, `.png`, `.bmp`) into `Wallpapers\`.
2. The background `Publisher.ps1` file-system monitor automatically:
   - Detects the new file.
   - Waits for copy completion to ensure the file is not locked.
   - Inspects the binary magic bytes to reject corrupted or spoofed files.
   - Computes the SHA-256 hash.
   - Copies the file atomically to `Published\`.
   - Generates an updated `manifest.json` with a new `collectionVersion`.
3. Connected clients will detect the new collection on their next 10-second check and automatically download the new image.

### Replacing an Image (Same Filename)
1. Overwrite an existing image in `Wallpapers\` with a new file having the exact same name.
2. The publisher computes the new SHA-256 hash.
3. Because the hash differs from the published record, the host increments the collection version and updates the published asset.
4. Clients download the updated image without corrupting their active slideshow.

### Deleting an Image
1. Delete the image file from `Wallpapers\`.
2. The publisher detects the deletion, prunes the file from `Published\`, and publishes an updated manifest.
3. Clients synchronize, remove the deleted image from their local `Cache\`, and smoothly advance to the next available image.

---

## 💻 Part 3: Client PC Deployment (30–100 PCs)

### Mode A: One-Time Manual Installation (Small Fleets)
Use this mode for independent systems or environments without centralized device management.

1. Copy the generated `Installer\Client-Package\` directory to a shared USB drive or read-only network share.
2. On each target client PC, copy the folder to a local location (e.g., `C:\ProgramData\LAN-Dynamic-Wallpaper\Client`).
3. Double-click `Install-Client.bat` inside the user's active desktop session.
4. The client installer will:
   - Attempt automatic UDP host discovery on port `8766`.
   - If discovery succeeds, write the host IP to `ClientConfig.json`.
   - If discovery fails (e.g. across subnets), prompt the user/admin to input the host IP once.
   - Test connection and verify authentication against the host.
   - Download the initial manifest and wallpaper image collection into `Cache\`.
   - Immediately apply the initial wallpaper via Win32 `SystemParametersInfoW`.
   - Register a Windows Scheduled Task (`LAN-Dynamic-Wallpaper-Client`) configured to start at user logon in interactive session mode.

---

### Mode B: Centralized Enterprise Deployment (30–100 Workstations)
For enterprise fleets joined to Active Directory or managed via Microsoft Intune, deploy the client package silently without user intervention.

#### Architecture of Centralized Package
Place the client files on a central read-only SMB network share:
`\\FileServer\Deploy\LAN-Dynamic-Wallpaper\`

#### Active Directory Group Policy (GPO) Deployment
1. Open **Group Policy Management Console** (`gpmc.msc`).
2. Create or edit a GPO targeted at the **Workstations Organizational Unit (OU)**.
3. Navigate to: **User Configuration** -> **Policies** -> **Windows Settings** -> **Scripts (Logon/Logoff)** -> **Logon**.
4. Add a PowerShell logon script pointing to a bootstrap script:
   ```powershell
   # GPO-ClientDeploy.ps1
   $targetDir = "$env:LOCALAPPDATA\LAN-Dynamic-Wallpaper"
   $sourceShare = "\\FileServer\Deploy\LAN-Dynamic-Wallpaper\Client-Package"
   
   if (-not (Test-Path "$targetDir\Client\Client.ps1")) {
       New-Item -ItemType Directory -Path "$targetDir\Client" -Force | Out-Null
       Copy-Item -Path "$sourceShare\*" -Destination "$targetDir\Client" -Recurse -Force
       
       # Execute silent client installation
       & "$targetDir\Client\Install-Client.ps1" -InstallDir "$targetDir\Client" -Silent
   }
   ```

#### Microsoft Intune / SCCM Deployment
1. Package the `Client-Package` folder into a `.intunewin` file using the Microsoft Win32 Content Prep Tool.
2. Configure **Install Command**:
   ```cmd
   powershell.exe -ExecutionPolicy Bypass -File Install-Client.ps1 -Silent
   ```
3. Configure **Uninstall Command**:
   ```cmd
   powershell.exe -ExecutionPolicy Bypass -File Uninstall-Client.ps1
   ```
4. Set **Install Behavior**: **User** (Critical: must run in interactive user context to apply desktop wallpaper).
5. Set **Detection Rule**: File existence check for `%LOCALAPPDATA%\LAN-Dynamic-Wallpaper\Client\Client.ps1`.

---

## 🔬 Part 4: Staged Rollout & Verification Procedure

### Staged Rollout Plan
To guarantee zero network congestion and verify stability, follow this staged rollout:

| Phase | Target Scope | Duration | Success Criteria |
| :--- | :--- | :--- | :--- |
| **Phase 1: Pilot** | 2 Client PCs | 24 Hours | Initial synchronization, rotation every 60s, offline survival test |
| **Phase 2: Department** | 10 Client PCs | 48 Hours | Concurrent manifest polling, new image dispatch test, CPU < 1% |
| **Phase 3: Full Fleet** | 30–100 Client PCs | Ongoing | Stable rotation across all rooms, telemetry audit verified |

### Two-Client Acceptance Scenario Test
Execute this verification checklist before rolling out to the broader fleet:
1. **Setup**: Install Host on PC 1. Install Client on PC 2 and PC 3.
2. **Initial Sync**: Add 5 sample wallpapers to Host. Confirm both PC 2 and PC 3 download all 5 images and cycle through them.
3. **Dynamic Addition**: Drop 2 new photos into `Wallpapers\`. Confirm both clients pick up the new images within 15 seconds.
4. **Content Replacement**: Replace photo #1 with a new photo of the same filename. Confirm clients receive the updated hash.
5. **Deletion**: Delete photo #5 from Host. Confirm clients remove it from `Cache\` and continue cycling through photos 1–4.
6. **Network Disruption**: Disconnect Ethernet cable on PC 2. Confirm PC 2 continues rotating through cached wallpapers without error dialogs. Reconnect Ethernet and verify synchronization resumes.

---

## 🗑️ Part 5: Clean Uninstallation

### Uninstall Client
Run inside the user session on the client workstation:
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Installer\Uninstall-Client.ps1
```
Removes:
- Scheduled Task `LAN-Dynamic-Wallpaper-Client`.
- Terminates background client agent processes.
- Optionally purges downloaded wallpaper cache (`-PurgeCache`).

### Uninstall Host
Run from an elevated administrator PowerShell prompt on the Host PC:
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Installer\Uninstall-Host.ps1
```
Removes:
- Scheduled Task `LAN-Dynamic-Wallpaper-Host`.
- Terminates background host HTTP listener and UDP daemon.
- Deletes Windows Firewall rules (`LAN-Dynamic-Wallpaper-Host-HTTP` and `LAN-Dynamic-Wallpaper-Host-Discovery`).
- Removes URL ACL `http://+:8765/`.
