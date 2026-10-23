# 🖼️ LAN Dynamic Wallpaper Slideshow System

[![Platform](https://img.shields.io/badge/Platform-Windows%2011%20%7C%20Windows%2010-0078D6.svg?logo=windows)](https://microsoft.com)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20(Pure)-5391FE.svg?logo=powershell)](https://microsoft.com/powershell)
[![Architecture](https://img.shields.io/badge/Architecture-Host%20%2F%20Client%20RBAC-107C41.svg)]()
[![Dependencies](https://img.shields.io/badge/Dependencies-Zero%20(Built--in%20Only)-success.svg)]()
[![Fleet Capacity](https://img.shields.io/badge/Fleet%20Capacity-30--100%20Client%20Nodes-blueviolet.svg)]()
[![Test Verdict](https://img.shields.io/badge/Automated%20Tests-100%25%20PASS%20(5%2F5%20Suites)-brightgreen.svg)]()

An enterprise-grade, high-performance, **pure Windows PowerShell** LAN Dynamic Wallpaper Slideshow System built for 30–100+ Windows 11 and Windows 10 computers in labs, classrooms, and corporate offices.

The central Host manages all client wallpapers dynamically without server restarts, and every PC in the lab changes photos at the **exact same second**.

---

## ⚡ The Two-Launcher Experience (Strictly 2 Batch Files)

The entire system is controlled by **exactly two batch files**:

| Launcher | Where to Run | Administrator Needed? | Primary Action |
| :--- | :--- | :--- | :--- |
| **`1-Start-Host.bat`** | On the Central Lab Server / Host PC | **Yes (Auto-prompts UAC)** | Configures firewall, starts discovery services, shares folder password-free across LAN, opens `Wallpapers/` folder, starts central sync server. |
| **`2-Start-Client.bat`** | On each Student / Client PC | ❌ **STRICTLY NO (Runs as Normal User)** | Discovers Host on LAN, caches wallpapers locally, sets interactive Windows desktop wallpaper, and syncs dynamically. |

---

## 🚀 3 Easy Ways to Connect Client Workstations

You have **three ultra-simple methods** to connect all 80+ client PCs in your lab:

### 🌟 Way 1: Zero-Typing via File Explorer "Network" (Fastest for Students)
1. On the client computer, press `Win + E` to open **File Explorer**.
2. Click **Network** in the left sidebar.
3. Click your **Host Computer Name** (e.g. `\\HOST-PC`).
4. Double-click **`2-Start-Client.bat`**.
   - **No administrator rights needed.**
   - **No password prompt is asked.**
   - The client immediately downloads wallpapers to its local cache and starts rotating!

### ⚡ Way 2: 1-Click Remote PowerShell Setup (Zero File Copy)
On any client PC, press `Win + R`, type `powershell`, and run the 1-click command shown on your Host screen:
```powershell
irm http://<HOST_IP>:8765/setup | iex
```
*(Example: `irm http://192.168.31.20:8765/setup | iex`)*
- Automatically downloads client scripts into `%LOCALAPPDATA%`, verifies SHA-256 hashes, sets wallpaper, and starts live sync!

### 🌐 Way 3: Web Browser Download
1. On any client PC, open Chrome, Edge, or Firefox and go to:
   ```
   http://<HOST_IP>:8765
   ```
2. Click **Download 2-Start-Client.bat** and double-click the downloaded file!
   - The downloaded batch file has the Host IP already baked in dynamically!

---

## 🔄 Dynamic Zero-Restart Operation & Instant Sync

- **Add Photos Without Server Restarts**:
  Drop any photo (`.jpg`, `.png`, `.webp`, `.bmp`, `.gif`, `.tiff`) into the `Wallpapers/` folder on the Host PC.
  Within **2 seconds**, the Host generates a new atomic manifest, and all 80+ client workstations download the photo and add it to the rotation cycle without stopping or restarting!
- **Remove Photos**:
  Delete an image from `Wallpapers/`. All client PCs automatically detect the deletion and prune it from their local cache.
- **Dynamic Timer Reload**:
  Want to change the slideshow interval from 5s to 10s or 60s? Simply edit `"DefaultIntervalSeconds"` in `Host\HostConfig.json`. The Host detects the change dynamically within 2 seconds and updates all clients automatically!

---

## ⏱️ Exact-Second Fleet Synchronization

All client workstations in the lab calculate transitions against UTC epoch time:
$$\text{Index} = \lfloor \text{EpochSeconds} / \text{IntervalSeconds} \rfloor \pmod N$$
- Every computer in the fleet displays the **exact same image at the exact same second**.
- Because every PC aligns with UTC epoch time, all screens rotate simultaneously in perfect lockstep without requiring network broadcast chatter every second!

---

## 💡 Frequently Asked Actions

| What You Want to Do | How to Do It in 1 Step |
| :--- | :--- |
| **Add a new photo without stopping server** | Just drop the photo file into `Wallpapers/` on the Host PC. Within 2-3 seconds, all client computers will automatically download and start showing it! |
| **Remove a photo** | Delete the file from `Wallpapers/` on the Host PC. All client computers immediately prune it from their cache. |
| **Change the slideshow timer** | Open `Host\HostConfig.json` in Notepad, change `"DefaultIntervalSeconds": 5` to any number (e.g. `10`), and save. Host auto-reloads dynamically! |
| **Connect client PC in 3 seconds** | Open PowerShell on the client and run: `irm http://<HOST_IP>:8765/setup \| iex`. |
| **Check connected clients** | In browser, open `http://<HOST_IP>:8765` or inspect `Host\clients.json` to view live client workstations. |
| **Run verification tests** | Open PowerShell and run `powershell -ExecutionPolicy Bypass -File Tests\Run-All-Tests.ps1`. |

---

## ⚡ Key Highlights & Architecture

- **Zero External Dependencies**: Operates exclusively using built-in Windows PowerShell 5.1+, Windows APIs via Win32 P/Invoke (`SystemParametersInfoW`), and the Windows Defender Firewall. **No Python, Node.js, Java, databases, or cloud services required**.
- **Exactly Two User-Facing Launchers**: Eliminates confusing multiple scripts or installers. The system exposes strictly `1-Start-Host.bat` and `2-Start-Client.bat`.
- **1 Host to 30–100+ Clients**: Scales smoothly to 100+ concurrent Windows workstations with sub-second latency and zero dropped requests.
- **Role-Based Access Control (RBAC)**:
  - **`SuperAdmin / HostAdmin`**: Full control over host synchronization, fleet management, client roster audits, and system configuration via `AdminSecret`.
  - **`ClientNode`**: Restricted access to authenticated manifest retrieval, binary asset streaming, and heartbeat telemetry via provisioned `clientToken`.
  - **`Monitor / Auditor`**: Unauthenticated read-only health probe access (`/api/v1/health`) for network monitoring tools.
- **Zero Hardcoded Secrets in Git**: No credentials, tokens, or personal passwords are committed to source control. Secrets are generated cryptographically on first run and stored locally with strict Windows ACLs.
- **Automatic Auto-Discovery & Resilient Fallback**: Clients locate the host via UDP broadcast handshake on port `8766` with automated fallback to subnet sweep and static IP configuration.
- **Deterministic Desktop Rotation**: Seamless cycling through local cache even during network interruptions, host reboots, or temporary disconnections.
- **Single-Instance Mutex Guarantee**: Prevents duplicate client processes and desktop lockups via session-scoped system mutex (`Local\LAN_Dynamic_Wallpaper_Client_$userSid`).

---

## 🏛️ System Architecture

```
                                  +---------------------------+
                                  |   Host Administrator PC   |
                                  |  (Drops / Deletes Images) |
                                  +-------------+-------------+
                                                |
                                                v
                                  +---------------------------+
                                  |    Wallpapers/ Folder     |
                                  +-------------+-------------+
                                                |
                                                v
                                  +---------------------------+
                                  |       Publisher.ps1       |
                                  | - Magic-byte validation   |
                                  | - Lock verification      |
                                  | - SHA-256 hashing         |
                                  | - Atomic manifest publish |
                                  +-------------+-------------+
                                                |
                                                v
                                  +---------------------------+
                                  |    Host.ps1 HTTP Engine   |
                                  | (TCP: 8765 / UDP: 8766)   |
                                  +-------------+-------------+
                                                |
       +----------------------------------------+----------------------------------------+
       |                                        |                                        |
       v (HTTP GET /manifest & /wallpaper)      v (HTTP GET /manifest & /wallpaper)      v
+-------------+                          +-------------+                          +-------------+
| Client PC 1 |                          | Client PC 2 |                          |Client PC 100|
| Client.ps1  |                          | Client.ps1  |                          | Client.ps1  |
| Wallpaper.  |                          | Wallpaper.  |                          | Wallpaper.  |
|    ps1      |                          |    ps1      |                          |    ps1      |
| Local Cache |                          | Local Cache |                          | Local Cache |
+-------------+                          +-------------+                          +-------------+
```

---

## 📂 Project Directory Structure

```
LAN-Dynamic-Wallpaper/
├── 1-Start-Host.bat             # 🖥️ 1-CLICK HOST LAUNCHER (Run on central Host PC)
├── 2-Start-Client.bat           # 💻 1-CLICK CLIENT LAUNCHER (Normal User - No Admin Needed!)
├── Host/
│   ├── Host.ps1                 # Multi-threaded HTTP listener & UDP discovery daemon
│   ├── Publisher.ps1            # Format converter, magic-byte validator, SHA-256 hasher, manifest generator
│   └── HostConfig.json          # Host network, port, security, and slideshow settings
├── Client/
│   ├── Client.ps1               # Client background synchronization and health agent
│   ├── Wallpaper.ps1            # Win32 P/Invoke desktop wallpaper rotation engine
│   └── ClientConfig.json        # Client network, host IP, secret, and interval settings
├── Wallpapers/                  # 📂 SINGLE PHOTO VAULT (Drop photos here; auto-distributed across LAN)
├── Tests/
│   ├── Run-All-Tests.ps1        # Master test harness executing all 5 suites with summary scorecard
│   ├── Test-Host.ps1            # Automated suite for host endpoints, tokens & RBAC (17 tests)
│   ├── Test-Publisher.ps1       # Automated suite for file watcher, magic bytes & hashing (13 tests)
│   ├── Test-Client.ps1          # Automated suite for Win32 API, rotation & mutex (16 tests)
│   ├── Test-Security.ps1        # Penetration suite for path traversal & auth bypass (15 tests)
│   └── Test-100Clients.ps1      # 100-client concurrent load benchmark simulation (100 nodes, 400 reqs)
├── README.md                    # Primary system architecture, quickstart, and reference
└── INSTALLATION-GUIDE.md        # Comprehensive host and client deployment manual
```

---

## 🖥️ Supported Operating Systems & Prerequisites

- **Operating System**: Windows 11 (all editions) or Windows 10 (Version 1809 or newer, 64-bit/32-bit).
- **PowerShell**: Windows PowerShell 5.1 (built into Windows) or PowerShell 7.x.
- **Host Permissions**: Administrator elevation required on the Host PC to bind port `8765` for LAN HTTP streaming. `1-Start-Host.bat` handles this automatically.
- **Client Permissions**: **Zero Administrator Rights Needed**. Any student or standard Windows user can run `2-Start-Client.bat`. Changing desktop wallpaper and configuring user startup operate entirely within the logged-in user's interactive session (`HKEY_CURRENT_USER`).
- **Network**: Wired Ethernet LAN or stable private Wi-Fi network on the same IP subnet.
- **Supported Formats**: `.jpg`, `.jpeg`, `.png`, `.bmp`, `.gif`, `.webp`, `.tiff`, `.heic`, `.ico`, `.mp4`, `.mov`, `.wmv`.

---

## 🔒 Security Architecture Summary

1. **Role-Based Access Control (RBAC)**:
   - `SuperAdmin`: Possesses 256-bit `AdminSecret` for client roster auditing and force-sync.
   - `ClientNode`: Automatically enrolled and assigned a unique `clientToken` during registration.
   - `Monitor`: Unauthenticated access restricted exclusively to `/api/v1/health`.
2. **Defensive Path Traversal Protection**:
   - Request paths are URL-decoded, regex-filtered against directory traversal sequences (`..`, `%2f`, `%5c`), and verified to reside within the canonical `Wallpapers\` directory boundary.
3. **Magic-Byte Binary Inspection**:
   - Every file added to `Wallpapers/` is inspected for genuine image headers (e.g. JPEG `FF D8 FF`, PNG `89 50 4E 47`) before publishing. Renamed executables or scripts are rejected.
4. **Zero Secret Exposure**:
   - `HostConfig.json` and `ClientConfig.json` contain empty string placeholders in version control. Fresh secrets are generated cryptographically on first run and protected with Windows File Access Control Lists (ACLs).
5. **Interactive Desktop Session Isolation**:
   - The desktop wallpaper is applied using Win32 `SystemParametersInfoW` within the logged-in user's interactive session. Non-interactive background SYSTEM services cannot update the user desktop.

---

## 📊 Measured Benchmark Results (100 Concurrent Clients)

The system includes an automated stress simulation suite (`Tests\Test-100Clients.ps1`) executing real end-to-end multi-step client transactions (Registration, Manifest retrieval, Binary download, Heartbeat telemetry) concurrently:

| Metric | Measured Value | Target Standard | Status |
| :--- | :--- | :--- | :--- |
| **Fleet Scale** | **100 Concurrent Workstations** | 30–100 Clients | ✅ PASS |
| **Total HTTP Transactions** | **400 Requests** | 400 Requests | ✅ PASS |
| **Wall-Clock Duration** | **2.04 seconds** | < 15 seconds | ✅ PASS |
| **Fleet Throughput** | **196.2 requests / sec** | > 50 req/sec | ✅ PASS |
| **Workflow Success Rate** | **100% (100 / 100)** | 100% | ✅ PASS |
| **Dropped / Failed Requests** | **0 Requests** | 0 Requests | ✅ PASS |
| **Average End-to-End Latency** | **328.9 ms** | < 1000 ms | ✅ PASS |
| **95th Percentile (p95) Latency**| **433 ms** | < 2000 ms | ✅ PASS |

---

## 🧪 Automated Test Verification

To run the full enterprise automated test harness:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File Tests\Run-All-Tests.ps1
```

### Verified Test Scorecard:
```
==============================================================================
 MASTER VERIFICATION SUMMARY SCORECARD
==============================================================================

Suite                                       Status Duration
-----                                       ------ --------
Publisher Engine (Validation & Atomic Sync) PASSED 2.04 s  
Client Engine (Win32 API & Local Cache)     PASSED 2.05 s  
Host Server (Routes, Tokens & RBAC)         PASSED 6.08 s  
Security Penetration (Traversal & Bypass)   PASSED 6.06 s  
100-Client Concurrency Load Benchmark       PASSED 8.07 s  

Total Suites Run     : 5
Total Suites Passed  : 5 (100% Success Rate)
Total Suites Failed  : 0
Total Execution Time : 24.36 seconds
==============================================================================
FINAL VERDICT: PASS - 100% of test suites verified successfully.
```

---

## 🗑️ Clean Uninstallation

### On Client Workstations:
1. Close the client console window if running.
2. Remove the auto-start entry from the Windows registry:
   ```powershell
   Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "LAN-Dynamic-Wallpaper-Client" -ErrorAction SilentlyContinue
   ```
3. Delete `%LOCALAPPDATA%\LAN-Dynamic-Wallpaper-Client`.

### On the Host PC:
1. Close the host console window.
2. Delete the SMB share:
   ```cmd
   net share LAN-Dynamic-Wallpaper /delete /y
   ```

---

## 👨‍💻 Engineering Author

<table border="0" itemscope itemtype="https://schema.org/Person">
  <tr>
    <td width="130" align="center" valign="middle">
      <img src="https://github.com/Tharun4743.png" width="105" style="border-radius: 6px;" alt="Tharunkumar K — Full Stack Developer & AI Systems Engineer at V.S.B. Engineering College" title="Tharunkumar K — V.S.B. Engineering College (VSBEC)" itemprop="image" />
    </td>
    <td>
      <h3 itemprop="name">Tharunkumar K</h3>
      <p>
        <b itemprop="jobTitle">Full Stack Developer & AI Systems Engineer</b> | <b>V.S.B. Engineering College (VSBEC)</b><br/>
        🎓 <b>B.Tech in Information Technology</b> — <b>V.S.B. Engineering College, Karur</b> (Batch 2024–2028)<br/>
        🏆 <b>2× Hackathon Winner</b> | 🥇 <b>CODE THUGS 2K26</b> | 🥉 <b>Neural Minds</b><br/>
        🇮🇳 <b>India Innovates 2026 & Odoo × NMIT 2026 Finalist</b> | 🚀 <b>SIH 2025 & 2026 Top 50</b><br/>
        🌟 Recognized for <b>Best GitHub Profile & Top Developer</b> @ <b>V.S.B. ENGINEERING COLLEGE</b>
      </p>
      <p>
        🚀 <b>Top Flagship Engineering Projects:</b><br/>
        • 🏛️ <b>TaskManager (VSBEC IT Vault)</b> — Institutional Task Governance & LeetCode/GitHub Sync &nbsp;<a href="https://github.com/Tharun4743/Taskmanager"><img src="https://img.shields.io/badge/Code-181717?style=flat-square&logo=github&logoColor=white" alt="Code" /></a>&nbsp;<a href="https://it-taskmanager.vercel.app/"><img src="https://img.shields.io/badge/Live_Demo-10B981?style=flat-square&logo=vercel&logoColor=white" alt="Live Demo" /></a><br/>
        • 🧠 <b>AURA</b> — Air-Gapped Local Multimodal RAG Engine & Offline AI Assistant &nbsp;<a href="https://github.com/Tharun4743/AURA"><img src="https://img.shields.io/badge/Code-181717?style=flat-square&logo=github&logoColor=white" alt="Code" /></a><br/>
        • 🪖 <b>Smart Helmet IoT</b> — SIH Top 50 Dual-Unit Motorcycle Accident Prevention System &nbsp;<a href="https://github.com/Tharun4743/AGILE-INNOVATORS-smart-helmet-"><img src="https://img.shields.io/badge/Code-181717?style=flat-square&logo=github&logoColor=white" alt="Code" /></a>
      </p>
      <p>
        <a href="https://tharunkumark4743.netlify.app/"><img src="https://img.shields.io/badge/Portfolio-0284c7?style=flat-square&logo=googlechrome&logoColor=white" alt="Portfolio" /></a>&nbsp;
        <a href="https://github.com/Tharun4743"><img src="https://img.shields.io/badge/GitHub-181717?style=flat-square&logo=github&logoColor=white" alt="GitHub" /></a>&nbsp;
        <a href="https://www.linkedin.com/in/tharunkumark4743"><img src="https://img.shields.io/badge/LinkedIn-0A66C2?style=flat-square&logo=linkedin&logoColor=white" alt="LinkedIn" /></a>&nbsp;
        <a href="https://leetcode.com/u/Tharunkumar__K/"><img src="https://img.shields.io/badge/LeetCode-FFA116?style=flat-square&logo=leetcode&logoColor=white" alt="LeetCode" /></a>&nbsp;
        <a href="mailto:tharunkumark42007@gmail.com"><img src="https://img.shields.io/badge/Email-EA4335?style=flat-square&logo=gmail&logoColor=white" alt="Email" /></a>
      </p>
    </td>
  </tr>
</table>

<!-- =========================================================================
   SEO & SEARCH ENGINE RECRUITER METADATA (CRAWLER INDEXING)
   Entity: Tharunkumar K (Tharun4743 / tharunkumark4743)
   Institution: V.S.B. Engineering College, Karur (VSBEC)
   Department: Information Technology (Batch 2024-2028)
   Distinctions: Best GitHub Profile VSBEC, Top Developer Karur, National Hackathon Winner
   Keywords: Tharunkumar K, Tharunkumar VSBEC, Tharun4743, VSB Engineering College Karur, VSBEC IT, LAN Dynamic Wallpaper, Windows 11 Slideshow
   Canonical URL: https://github.com/Tharun4743/LAN-Dynamic-Wallpaper
========================================================================= -->
