# 📖 LAN Dynamic Wallpaper: Complete Installation & Deployment Guide

This guide details the complete deployment lifecycle for the LAN Dynamic Wallpaper Slideshow System across 1 Central Host PC and 30–100+ Client Workstations on a local wired or wireless LAN.

---

## ⚡ The Two-Launcher Experience

The entire system is controlled by **exactly two user-friendly batch files**:

| Launcher | Where to Run | Administrator Needed? | Primary Action |
| :--- | :--- | :--- | :--- |
| **`1-Start-Host.bat`** | On the Central Lab Server / Host PC | **Yes (Auto-prompts UAC)** | Binds HTTP on port `8765` and UDP on `8766` for LAN streaming, opens `Wallpapers/` folder, starts central sync service. |
| **`2-Start-Client.bat`** | On each Student / Client PC | ❌ **STRICTLY NO (Runs as Normal User)** | Auto-discovers Host on LAN, downloads wallpapers to local cache, sets interactive desktop wallpaper, syncs dynamically. |

> [!IMPORTANT]
> **Zero Administrator Rights on Client Workstations:**
> Students, lab users, or standard Windows accounts do **NOT** need admin rights or UAC passwords to use `2-Start-Client.bat`. Changing Windows desktop wallpaper (`SystemParametersInfoW`) and configuring user logon startup (`HKCU:\Software\Microsoft\Windows\CurrentVersion\Run`) operate entirely within the logged-in user's interactive desktop session (`HKEY_CURRENT_USER`).

---

## 📋 System Prerequisites

### Host PC (The Central Management Computer)
- **Operating System**: Windows 11 or Windows 10 (Pro, Enterprise, Education, or Home).
- **PowerShell**: Windows PowerShell 5.1 (built into Windows) or PowerShell 7.x.
- **Permissions**: Administrator rights (to bind port `8765` on Windows HTTP.SYS for LAN network access). `1-Start-Host.bat` automatically handles elevation.
- **Network**: Connected to the lab LAN (wired Ethernet recommended, or Wi-Fi).

### Client PCs (Student / Lab Workstations)
- **Operating System**: Windows 11 or Windows 10.
- **PowerShell**: Windows PowerShell 5.1 (standard on all Windows machines).
- **Permissions**: **Standard Normal User (No Admin Rights Needed)**.
- **Network**: Connected to the same LAN or Wi-Fi network as the Host.

---

## 🖥️ Step-by-Step Installation

### Part 1: Host PC Setup (Single Central PC)

1. **Download & Extract** the `LAN-Dynamic-Wallpaper` folder on the designated Host PC.
2. Double-click **`1-Start-Host.bat`**.
   - If prompted by Windows User Account Control (UAC), click **Yes**.
   - The launcher will start the central server and display the Host IP address (e.g., `192.168.31.20` or `172.16.20.169`).
3. The server will automatically open the **`Wallpapers/`** folder in Windows Explorer.
4. **Drop your photos or images** into the `Wallpapers/` folder:
   - Supported formats: **`.jpg`**, **`.jpeg`**, **`.png`**, **`.bmp`**, **`.gif`**, **`.webp`**, **`.tiff`**, **`.heic`**, **`.mp4`**, **`.mov`**, **`.wmv`**.
5. **Done!** The Host is now actively broadcasting and serving wallpapers over LAN. Keep the console window open (you can minimize it).

---

### Part 2: Client Workstation Deployment (Student / Workstation PCs)

You have **three ultra-simple methods** to connect client workstations:

#### 🌟 Method A: Zero-Typing via File Explorer "Network" (Fastest for Students)
1. On the client computer, press `Win + E` to open **File Explorer**.
2. Click **Network** in the left sidebar.
3. Click your **Host Computer Name** (e.g. `\\HOST-PC`).
4. Double-click **`2-Start-Client.bat`**.
   - **No administrator rights needed.**
   - **No password prompt is asked.**
   - The client immediately downloads wallpapers to its local cache and starts rotating!

#### ⚡ Method B: 1-Click Remote PowerShell Setup (Zero File Copy Needed)
On any client PC, simply open **PowerShell** and run the 1-click command shown on your Host screen:
```powershell
irm http://<HOST_IP>:8765/setup | iex
```
*(Example: `irm http://192.168.31.20:8765/setup | iex`)*
- Automatically downloads client scripts directly into `%LOCALAPPDATA%`, verifies SHA-256 hashes, sets wallpaper, and starts live sync!

#### 🌐 Method C: Web Browser Download
1. On any client PC, open Chrome, Edge, or Firefox and go to:
   ```
   http://<HOST_IP>:8765
   ```
2. Click **Download 2-Start-Client.bat** and double-click the downloaded file!
   - The downloaded batch file has the Host IP already baked in dynamically!

---

## 🔄 Dynamic Real-Time Wallpaper Updates (Zero Server Restarts)

The system includes continuous real-time directory synchronization:

- **Add an Image**:
  Drop any new `.jpg`, `.png`, or `.webp` file into the `Wallpapers/` folder on the Host PC.
  Within **2 seconds**, all connected client PCs detect the update, download the new image, and include it in the rotation cycle without stopping or restarting the server.
- **Replace an Image**:
  Overwrite an existing image in `Wallpapers/` with an updated file.
  The Host detects the changed SHA-256 hash and clients update their local copy seamlessly.
- **Delete an Image**:
  Delete an image from `Wallpapers/`.
  The Host updates the collection manifest and clients cleanly prune the deleted file from their cache.
- **Change Slideshow Timer**:
  Open `Host\HostConfig.json` in Notepad, change `"DefaultIntervalSeconds": 5` to any number of seconds (e.g., `10` or `60`), and save.
  The Host detects the change dynamically within **2 seconds** and all clients adapt their slideshow timer without server restarts!

---

## ⏱️ Exact-Second Synchronized Rotation

All computers in the lab rotate their wallpaper at the **exact same second**:
- The slideshow uses UTC Unix epoch alignment:
  $$\text{Index} = \lfloor \text{EpochSeconds} / \text{IntervalSeconds} \rfloor \pmod N$$
- Every PC in the lab calculates the exact same index simultaneously.
- Default rotation interval: **5 seconds** (configurable dynamically in `Host/HostConfig.json`).

---

## 🛡️ Why Wallpaper Changes Without Admin on Client Side

Some administrators wonder whether standard users can change desktop wallpaper without UAC approval. Here is the technical breakdown:

1. **Win32 User32 API**: `SystemParametersInfoW(SPI_SETDESKWALLPAPER, 0, path, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE)` operates directly on the current user's desktop session. It does not touch system-wide protected files or elevated kernel drivers.
2. **Current User Registry**: Wallpaper settings are stored in `HKCU:\Control Panel\Desktop` (`HKEY_CURRENT_USER`). Standard Windows users have full read and write access to their own user registry hive.
3. **Logon Auto-Start**: The startup registry key `HKCU:\Software\Microsoft\Windows\CurrentVersion\Run` is also located in `HKEY_CURRENT_USER`. Standard users can register startup programs for their own account without administrative privileges.
4. **Local Cache Isolation**: When run from a read-only network share, downloaded wallpapers and configs are automatically redirected to `%LOCALAPPDATA%\LAN-Dynamic-Wallpaper-Client\`, where the user has full normal write permissions.

---

## 🚨 Troubleshooting & FAQ

### Issue: Client Shows "UDP broadcast silent / Host not found"
- **Solution 1**: Verify the Host PC is running `1-Start-Host.bat` and connected to the same network.
- **Solution 2**: Launch `2-Start-Client.bat` with the Host IP directly:
  ```cmd
  2-Start-Client.bat 192.168.31.20
  ```
- **Solution 3**: Or use the 1-click PowerShell bootstrap:
  ```powershell
  irm http://192.168.31.20:8765/setup | iex
  ```

### Issue: Host Fails to Bind Port 8765
- **Cause**: Windows HTTP.SYS requires administrator rights to open a server port accessible to the LAN.
- **Solution**: Make sure you launch `1-Start-Host.bat` (which automatically prompts for UAC elevation) on the Host PC.

### Issue: Wallpaper Does Not Display on Client
- **Solution**: Open Windows **Settings** -> **Personalization** -> **Background** and ensure the background mode is set to **Picture** (not Windows Spotlight).

---

## 🗑️ Clean Uninstallation

### To Remove Client Workstation:
1. Close the client console window.
2. To remove the automatic logon startup entry, run in PowerShell:
   ```powershell
   Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "LAN-Dynamic-Wallpaper-Client" -ErrorAction SilentlyContinue
   ```
3. Delete `%LOCALAPPDATA%\LAN-Dynamic-Wallpaper-Client`.

### To Stop Host Server:
1. Close the `1-Start-Host.bat` console window.
2. To remove the SMB share:
   ```cmd
   net share LAN-Dynamic-Wallpaper /delete /y
   ```
