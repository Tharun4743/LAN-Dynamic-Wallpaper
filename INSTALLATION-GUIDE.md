# 📖 LAN Dynamic Wallpaper: Complete Installation & Deployment Guide

This guide details the complete deployment lifecycle for the LAN Dynamic Wallpaper Slideshow System across 1 Central Host PC (Teacher/Server) and 30–100+ Client Workstations (Students) on a local wired or wireless LAN.

---

## ⚡ Quick Reference: Installation & Run Order

### 🖥️ On the Host PC (Teacher / Lab Server)

**Step 1 — Open the Share:**
- Double-click **`1-Host-Network-Start.bat`** *(Click Yes at UAC)*.
- *(Opens client package share so student PCs can download the files).*

**Step 2 — Start Wallpaper Service:**
- Double-click **`2-Host-Wallpaper-Start.bat`** *(Click Yes at UAC)*.
- Drop your photos into the **`Wallpapers/`** folder.
- *(Keep this window open during your lab session).*

---

### 💻 On Each Client PC (Students)

**Step 3 — Run the Client:**
- Open **File Explorer** ➔ click **Network** ➔ open **Host PC** ➔ open **`LAN-WP-ClientPkg`**
- Double-click **`3-Client-Download-Start.bat`** *(No Admin Needed!)*
- *(Wallpapers start rotating in sync with the Host immediately).*

---

### 🛑 When Done (Host PC)

**Step 4 — Stop Sharing (Optional):**
- Run **`4-Host-Network-Stop.bat`**
- *(Closes the download share; wallpapers on student PCs keep rotating uninterrupted).*

**Step 5 — Stop Everything:**
- Run **`5-Stop-All.bat`**
- *(Stops the wallpaper server and removes all firewall rules).*

---

## ⚡ The Five-Launcher Architecture

The system uses **five dedicated batch files** managing two completely independent services:

| # | Launcher | Where to Run | Administrator Required? | Primary Purpose |
|:--|:---|:---|:---|:---|
| **1** | **`1-Host-Network-Start.bat`** | Host PC | ✅ Yes (Auto-prompts UAC) | **Network Distribution Share**: Creates read-only SMB share `LAN-WP-ClientPkg` (exposing only `Client\` folder). Auto-places `3-Client-Download-Start.bat` inside the share. Enables Network Discovery and File Sharing firewall rules. **Stays open until manually stopped.** |
| **2** | **`2-Host-Wallpaper-Start.bat`** | Host PC | ✅ Yes (Auto-prompts UAC) | **Wallpaper Streaming Service**: Binds central HTTP wallpaper listener (port 8765) and UDP discovery beacon (port 8766). Handles dynamic wallpaper streaming, manifest updates, and fleet synchronization. |
| **3** | **`3-Client-Download-Start.bat`** | Each Client PC | ❌ **No (Standard User)** | **Single Client Installer & Agent**: Auto-discovers host, downloads `Client.ps1`, `Wallpaper.ps1`, and `ClientConfig.json` into `%USERPROFILE%\Downloads\LAN-Dynamic-Wallpaper\`, and launches the wallpaper agent. **Zero manual configuration.** |
| **4** | **`4-Host-Network-Stop.bat`** | Host PC | ✅ Yes (Auto-prompts UAC) | **Stop Network Share Only**: Closes SMB share `LAN-WP-ClientPkg` and removes its firewall rule. **The wallpaper service on port 8765 remains completely unaffected!** |
| **5** | **`5-Stop-All.bat`** | Host PC | ✅ Yes (Auto-prompts UAC) | **Stop Everything**: One-click total shutdown. Closes network share, terminates Host.ps1 wallpaper process, and removes all project firewall rules. |

> [!IMPORTANT]
> **Complete Service Independence:** Stopping the network distribution share via `4-Host-Network-Stop.bat` does **not** affect wallpaper rotation. Clients that have already downloaded the package continue receiving wallpapers over HTTP with zero interruption.

---

## 📋 System Prerequisites & Privileges Breakdown

### Host PC (Central Teacher / Lab Server)
- **Operating System**: Windows 11 or Windows 10 (Pro, Enterprise, Education, or Home).
- **PowerShell**: Windows PowerShell 5.1 (built into Windows) or PowerShell 7.x.
- **Permissions**: **Administrator elevation required** (for HTTP port binding on port 8765 and SMB share creation). Handled automatically with UAC prompt.
- **Network**: Connected to the lab LAN (Ethernet or Wi-Fi). Network profile must be set to **Private**.

### Client PCs (Student / Lab Workstations)
- **Operating System**: Windows 11 or Windows 10.
- **PowerShell**: Windows PowerShell 5.1 (standard on all Windows machines).
- **Permissions**: **Standard Normal User (Zero Admin Rights Needed)**.
  - Setting Windows desktop wallpaper via Win32 `SystemParametersInfoW` executes within the user's interactive session.
  - Client files are stored in `%USERPROFILE%\Downloads\LAN-Dynamic-Wallpaper\`.
  - No system registry keys, drivers, or elevated permissions are touched.
- **Network**: Connected to the same LAN or Wi-Fi network as the Host.

---

## 🖥️ Detailed Step-by-Step Deployment Workflow

### Phase 1: Host PC Setup

1. **Step 1 — Start the Network Share**:
   - Double-click **`1-Host-Network-Start.bat`** and click **Yes** at the UAC prompt.
   - The script:
     - Purges any stale shares from previous architectures.
     - Starts `LanmanServer` if stopped.
     - Ensures the single client batch file `3-Client-Download-Start.bat` is in the `Client\` folder.
     - Creates the SMB share `LAN-WP-ClientPkg` with read-only permissions for `Everyone`.
     - Enables `Network Discovery` and `File and Printer Sharing` firewall rules.
     - Auto-launches File Explorer directly to `\\<YOUR-COMPUTER-NAME>` so you can see the shared folder.
   - *Leave this open or minimize it while students join.*

2. **Step 2 — Start the Wallpaper Service**:
   - Double-click **`2-Host-Wallpaper-Start.bat`** and click **Yes** at the UAC prompt.
   - The wallpaper service binds to port **8765** and the UDP discovery beacon binds to port **8766**.
   - Drop your pictures into the `Wallpapers/` folder.
   - *Keep this console window open during your lab session.*

---

### Phase 2: Client Workstation Deployment (Zero Manual Config)

Students and lab users do **NOT** need to edit IP addresses or configuration files. They can connect using either method below:

#### Method A: Open File Explorer & Network (Standard Way)
1. On the student workstation, press **`Win + E`** (open File Explorer).
2. In the left sidebar, click **Network**.
3. Double-click the **Host PC Name** (e.g., `THARUNKUMARK`).
   *(Shortcut: You can also press `Win + R`, paste `\\<HOST_IP>\LAN-WP-ClientPkg`, and press Enter).*
4. Open the shared folder: **`LAN-WP-ClientPkg`**.
5. The folder opens showing:
   - 📄 **`3-Client-Download-Start.bat`**  *(The single client batch file)*
   - 📄 `Client.ps1`
   - 📄 `ClientConfig.json`
   - 📄 `Wallpaper.ps1`
   - 📄 `_HOSTINFO.txt`
6. Double-click **`3-Client-Download-Start.bat`**.
   - It identifies the UNC host location automatically.
   - Copies files into `%USERPROFILE%\Downloads\LAN-Dynamic-Wallpaper\`.
   - Starts the wallpaper agent.
   - **Zero admin rights required. No password asked.**

#### Method B: Distribute via USB / Local File
1. Copy **`3-Client-Download-Start.bat`** onto a USB drive or client computer.
2. Run it on the client workstation.
3. The launcher automatically queries the network:
   - Finds the host via UDP broadcast beacon (port 8766).
   - Probes LAN neighbors for `_HOSTINFO.txt`.
   - Downloads the package, sets up `%USERPROFILE%\Downloads\LAN-Dynamic-Wallpaper\`, and starts rotation.

#### Method C: 1-Click PowerShell Setup (Zero File Copy)
On any client PC, open PowerShell and run:
```powershell
irm http://<HOST_IP>:8765/setup | iex
```

---

### Phase 3: Post-Distribution Share Shutdown

Once all client workstations have downloaded the package:
1. On the Host PC, double-click **`4-Host-Network-Stop.bat`**.
2. The network share `LAN-WP-ClientPkg` is closed.
3. **The wallpaper service on port 8765 continues running untouched.**
4. All student computers keep rotating wallpapers in real-time over HTTP.

---

### Phase 4: Session Completion & Cleanup

When your lab session or event is finished:
1. On the Host PC, run **`5-Stop-All.bat`** to stop the wallpaper server, clean up firewall rules, and close all shares.

---

## 🔄 Real-Time Dynamic Updates (Zero Server Restarts)

| Goal | Action | Result |
| :--- | :--- | :--- |
| **Add new photo** | Drop `.jpg`, `.png`, or `.webp` into `Wallpapers/` on Host. | Within 2 seconds, all clients download and add it to rotation. |
| **Remove a photo** | Delete the file from `Wallpapers/` on Host. | Clients immediately prune it from local cache. |
| **Change rotation interval** | Edit `"DefaultIntervalSeconds"` in `Host\HostConfig.json` and save. | Host dynamically reloads without restart; clients update interval. |
| **Check connected clients** | Open `http://<HOST_IP>:8765` in browser or view `Host\clients.json`. | Live list of enrolled workstations and heartbeats. |

---

## ⏱️ Exact-Second Fleet Synchronization

All client workstations in the lab calculate transitions against UTC epoch time:
$$\text{Index} = \lfloor \text{EpochSeconds} / \text{IntervalSeconds} \rfloor \pmod N$$
- Every computer in the fleet displays the **exact same image at the exact same second**.
- Because every PC aligns with UTC epoch time, all screens rotate simultaneously in perfect lockstep without requiring network broadcast chatter every second!

---

## 🛡️ Why Wallpaper Changes Without Admin on Client Side

Some administrators wonder whether standard users can change desktop wallpaper without UAC approval:

1. **Win32 User32 API**: `SystemParametersInfoW(SPI_SETDESKWALLPAPER, 0, path, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE)` operates directly on the current user's desktop session. It does not touch system-wide protected files or kernel drivers.
2. **Current User Registry**: Wallpaper settings are stored in `HKCU:\Control Panel\Desktop` (`HKEY_CURRENT_USER`). Standard Windows users have full read and write access to their own user registry hive.
3. **Logon Auto-Start**: The startup registry key `HKCU:\Software\Microsoft\Windows\CurrentVersion\Run` is also located in `HKEY_CURRENT_USER`. Standard users can register startup programs for their own account without administrative privileges.
4. **Local Directory Storage**: Client files are saved in `%USERPROFILE%\Downloads\LAN-Dynamic-Wallpaper\`, where the user has full normal write permissions.

---

## 🚨 Troubleshooting & Diagnostics

### Built-in Diagnostics & Tests
Run from PowerShell in the project directory:
```powershell
# Network sharing, SMB & firewall diagnostic:
powershell.exe -ExecutionPolicy Bypass -File Tests\Diagnose-Network.ps1

# Full master test harness (all 7 suites):
powershell.exe -ExecutionPolicy Bypass -File Tests\Run-All-Tests.ps1
```

### Issue: "Network" folder doesn't show in File Explorer sidebar
- **Cause**: Windows 11 removed SMBv1 NetBIOS Computer Browser. The sidebar "Network" view uses WS-Discovery which can take minutes to populate.
- **Solution**: Do not wait for the sidebar. Press **`Win + R`**, enter `\\<HOST_IP>\LAN-WP-ClientPkg`, and press **Enter**. It opens immediately.

### Issue: Client Cannot Reach Share (`\\HOST-IP\LAN-WP-ClientPkg`)
- Confirm `1-Host-Network-Start.bat` ran on the Host.
- Verify the host network profile is set to **Private** (Windows Settings → Network & Internet → Properties → Private).
- Verify the client and host are connected to the same Wi-Fi SSID or LAN switch.

### Issue: Wallpaper Service Not Responding (`http://<HOST_IP>:8765`)
- Confirm `2-Host-Wallpaper-Start.bat` is running on the Host.
- Ensure the firewall rule `LAN-WP-WallpaperService` was allowed (added automatically).
- Check `netstat -ano | findstr :8765` on the Host to confirm the port is listening.

### Issue: Client Wallpaper Does Not Change
- Open Windows **Settings → Personalization → Background** and ensure the mode is **Picture** (not Windows Spotlight).
- Check the client log in `%USERPROFILE%\Downloads\LAN-Dynamic-Wallpaper\Logs\`.

---

## 🗑️ Clean Uninstallation

### Remove Client Installation:
```powershell
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "LAN-Dynamic-Wallpaper-Client" -ErrorAction SilentlyContinue
Remove-Item -Path "$env:USERPROFILE\Downloads\LAN-Dynamic-Wallpaper" -Recurse -Force
```

### Stop & Clean Host:
Run **`5-Stop-All.bat`** as Administrator. All shares, background processes, and project firewall rules are removed.
