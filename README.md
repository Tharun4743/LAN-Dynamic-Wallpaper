# 🖼️ LAN Dynamic Wallpaper Slideshow System

[![Platform](https://img.shields.io/badge/Platform-Windows%2011%20%7C%20Windows%2010-0078D6.svg?logo=windows)](https://microsoft.com)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20(Pure)-5391FE.svg?logo=powershell)](https://microsoft.com/powershell)
[![Architecture](https://img.shields.io/badge/Architecture-Host%20%2F%20Client%20RBAC-107C41.svg)]()
[![Dependencies](https://img.shields.io/badge/Dependencies-Zero%20(Built--in%20Only)-success.svg)]()
[![Fleet Capacity](https://img.shields.io/badge/Fleet%20Capacity-30--100%20Client%20Nodes-blueviolet.svg)]()
[![Test Verdict](https://img.shields.io/badge/Automated%20Tests-100%25%20PASS%20(7%2F7%20Suites)-brightgreen.svg)]()

An enterprise-grade, high-performance, **pure Windows PowerShell** LAN Dynamic Wallpaper Slideshow System built for 30–100+ Windows 11 and Windows 10 computers in labs, classrooms, and corporate offices.

The central Host manages all client wallpapers dynamically without server restarts, and every PC in the lab changes photos at the **exact same second**.

---

## ⚡ The Five-Launcher Workflow

The system provides **five clean batch scripts** managing two independent services:

| # | Launcher | Where to Run | Administrator Required? | Primary Action |
| :- | :--- | :--- | :--- | :--- |
| **1** | **`1-Host-Network-Start.bat`** | Host PC (Teacher/Server) | ✅ **Yes (Auto-prompts UAC)** | Creates read-only SMB share `LAN-WP-ClientPkg` (exposing only `Client\` folder). Auto-writes host IP for client discovery. **Stays open until you stop it manually.** |
| **2** | **`2-Host-Wallpaper-Start.bat`** | Host PC (Teacher/Server) | ✅ **Yes (Auto-prompts UAC)** | Starts central HTTP wallpaper delivery server (port 8765) and UDP discovery beacon (port 8766). Drop wallpapers into `Wallpapers/` anytime. |
| **3** | **`3-Client-Download-Start.bat`** | Each Client PC (Student) | ❌ **STRICTLY NO (Normal User)** | **Zero manual configuration.** Auto-discovers host, downloads client files to `%USERPROFILE%\Downloads\LAN-Dynamic-Wallpaper`, and starts wallpaper agent. |
| **4** | **`4-Host-Network-Stop.bat`** | Host PC (Teacher/Server) | ✅ **Yes (Auto-prompts UAC)** | **Stops the network SMB share only.** Does NOT affect the wallpaper service or any running client wallpapers. |
| **5** | **`5-Stop-All.bat`** | Host PC (Teacher/Server) | ✅ **Yes (Auto-prompts UAC)** | One-click total shutdown. Stops network share, terminates wallpaper service (port 8765), and removes firewall rules. |

> [!IMPORTANT]
> **Independent Services:** Stopping network sharing via `4-Host-Network-Stop.bat` closes the distribution share after all students have downloaded the client, but **does NOT affect the wallpaper service**. Connected clients continue receiving new photos smoothly over HTTP.

---

## ⚡ Quick Reference Run Order

### 🖥️ On the Host PC (Teacher / Lab Server)
**Step 1 — Open the Share:**
- Double-click **`1-Host-Network-Start.bat`** *(Click Yes at UAC)*.
- *(Opens client package share so student PCs can download the files).*

**Step 2 — Start Wallpaper Service:**
- Double-click **`2-Host-Wallpaper-Start.bat`** *(Click Yes at UAC)*.
- Drop your photos into the **`Wallpapers/`** folder.
- *(Keep this window open during your lab session).*

### 💻 On Each Client PC (Students)
**Step 3 — Run the Client:**
- Open **File Explorer** ➔ click **Network** ➔ open **Host PC** ➔ open **`LAN-WP-ClientPkg`**
- Double-click **`3-Client-Download-Start.bat`** *(No Admin Needed!)*

### 🛑 When Done (Host PC)
**Step 4 — Stop Sharing (Optional):**
- Run **`4-Host-Network-Stop.bat`** *(Closes share; wallpapers keep running)*.

**Step 5 — Stop Everything:**
- Run **`5-Stop-All.bat`** *(Stops all services and cleans up)*.

---

## 🚀 100% Automatic Client Setup (Zero Manual IP Editing)

Students and lab users **never** have to edit batch files or configure IP addresses manually:

### 🌟 Way 1: Open File Explorer & Network (Recommended)
1. On student computer, press **`Win + E`** (File Explorer).
2. Click **Network** in the left sidebar.
3. Double-click the **Host PC Name** (or press `Win + R` and enter `\\<HOST_IP>\LAN-WP-ClientPkg`).
4. Open the shared folder: **`LAN-WP-ClientPkg`**.
5. Double-click **`3-Client-Download-Start.bat`** directly from the share.
   - It detects the share path automatically, copies files to `%USERPROFILE%\Downloads\LAN-Dynamic-Wallpaper`, and launches the agent!
   - **Zero admin rights required. No password asked.**

### ⚡ Way 2: Distribute `3-Client-Download-Start.bat` via USB or Shared Drive
1. Copy `3-Client-Download-Start.bat` to a USB drive or public folder.
2. Students run it from their computer.
3. The launcher uses a 5-tier auto-discovery engine:
   - **Tier 1 (UNC Path):** Detects if launched directly from the network share.
   - **Tier 2 (UDP Beacon):** Probes port 8766; host wallpaper server responds with IP in < 1 second.
   - **Tier 3 (ARP / LAN Neighbor):** Checks active subnet nodes for `LAN-WP-ClientPkg`.
   - **Tier 4 (Workgroup Scan):** Scans visible computers for the client package share.
   - **Tier 5 (Interactive Prompt):** If automatic broadcast is blocked by complex VLAN switches, prompts the user to enter the host IP.

### 🌐 Way 3: 1-Click Remote PowerShell Setup (Zero File Copy)
On any client PC, press `Win + R`, type `powershell`, and run:
```powershell
irm http://<HOST_IP>:8765/setup | iex
```
*(Example: `irm http://192.168.31.20:8765/setup | iex`)*

---

## 🔄 Dynamic Zero-Restart Operation & Instant Sync

- **Add Photos Without Server Restarts**:
  Drop any photo (`.jpg`, `.png`, `.webp`, `.bmp`, `.gif`, `.tiff`) into the `Wallpapers/` folder on the Host PC.
  Within **2 seconds**, the Host generates a new atomic manifest, and all 100+ client workstations download the photo and add it to the rotation cycle without stopping or restarting!
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

## 💡 Quick Command Reference

| Action | How to Do It |
| :--- | :--- |
| **Open client package share** | Run `1-Host-Network-Start.bat` (Admin). |
| **Start wallpaper service** | Run `2-Host-Wallpaper-Start.bat` (Admin). |
| **Install & run client agent** | Run `3-Client-Download-Start.bat` on client (Normal User). |
| **Stop sharing client files** | Run `4-Host-Network-Stop.bat` (Admin). Wallpaper is unaffected! |
| **Stop everything & cleanup** | Run `5-Stop-All.bat` (Admin). |
| **Add a new photo** | Drop image into `Wallpapers/`. Syncs in 2 seconds automatically. |
| **Run verification tests** | Run `powershell -ExecutionPolicy Bypass -File Tests\Run-All-Tests.ps1`. |

---

## ⚡ Key Highlights & Architecture

- **Zero External Dependencies**: Operates exclusively using built-in Windows PowerShell 5.1+, Windows APIs via Win32 P/Invoke (`SystemParametersInfoW`), and the Windows Defender Firewall. **No Python, Node.js, Java, databases, or cloud services required**.
- **Five Dedicated Launchers**: Clean separation between share management, wallpaper delivery, client installation, selective stop, and complete shutdown.
- **1 Host to 30–100+ Clients**: Scales smoothly to 100+ concurrent Windows workstations with sub-second latency and zero dropped requests.
- **Role-Based Access Control (RBAC)**:
  - **`SuperAdmin / HostAdmin`**: Full control over host synchronization, fleet management, client roster audits, and system configuration via `AdminSecret`.
  - **`ClientNode`**: Restricted access to authenticated manifest retrieval, binary asset streaming, and heartbeat telemetry via provisioned `clientToken`.
  - **`Monitor / Auditor`**: Unauthenticated read-only health probe access (`/api/v1/health`) for network monitoring tools.
- **Zero Hardcoded Secrets in Git**: No credentials, tokens, or personal passwords are committed to source control. Secrets are generated cryptographically on first run and stored locally with strict Windows ACLs.
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
├── 1-Host-Network-Start.bat     # 🌐 Step 1: Open temporary client-package SMB share (Admin)
├── 2-Host-Wallpaper-Start.bat   # 🖼️ Step 2: Start central wallpaper HTTP server (Admin)
├── 3-Client-Download-Start.bat   # 💻 Step 3: Client download & launcher (Normal User - No Admin!)
├── 4-Host-Network-Stop.bat      # 🛑 Step 4: Stop client-package SMB share only (Admin)
├── 5-Stop-All.bat               # ⚡ Step 5: Stop all services & clean up (Admin)
├── Host/
│   ├── Host.ps1                 # Multi-threaded HTTP listener & UDP discovery daemon
│   ├── Publisher.ps1            # Magic-byte validator, SHA-256 hasher, atomic manifest generator
│   └── HostConfig.json          # Host network, port, security, and slideshow settings
├── Client/
│   ├── Client.ps1               # Client background synchronization and health agent
│   ├── Wallpaper.ps1            # Win32 P/Invoke desktop wallpaper rotation engine
│   └── ClientConfig.json        # Client network, host IP, secret, and interval settings
├── Wallpapers/                  # 📂 PHOTO VAULT (Drop photos here; auto-distributed across LAN)
├── Tests/
│   ├── Run-All-Tests.ps1        # Master test harness executing all 7 suites with scorecard
│   ├── Diagnose-Network.ps1     # Diagnostic tool for network sharing, SMB & firewall issues
│   ├── Test-Host.ps1            # Host endpoints, tokens & RBAC (17 tests)
│   ├── Test-Publisher.ps1       # File watcher, magic bytes & hashing (13 tests)
│   ├── Test-Client.ps1          # Win32 API, rotation & mutex (16 tests)
│   ├── Test-Security.ps1        # Penetration suite for path traversal & auth bypass (15 tests)
│   ├── Test-LiveIntegration.ps1 # Dynamic reload, manifest & bootstrap (20 tests)
│   ├── Test-100Clients.ps1      # 100-client concurrent load benchmark simulation (100 nodes, 400 reqs)
│   └── Test-Sharing.ps1         # Service separation, share lifecycle & stop-all verification (31 tests)
├── README.md                    # Primary system architecture, quickstart, and reference
└── INSTALLATION-GUIDE.md        # Comprehensive deployment and troubleshooting manual
```

---

## 🖥️ Supported Operating Systems & Prerequisites

- **Operating System**: Windows 11 (all editions, including Home) or Windows 10 (Version 1809 or newer).
- **PowerShell**: Windows PowerShell 5.1 (built into Windows) or PowerShell 7.x.
- **Host Permissions**: Administrator elevation required for Host scripts (`1`, `2`, `4`, `5`) to bind ports and manage SMB shares. Handled automatically via UAC prompts.
- **Client Permissions**: **Zero Administrator Rights Needed**. Standard user accounts can run `3-Client-Download-Start.bat`. Changing desktop wallpaper operates entirely within the logged-in user's interactive session (`HKEY_CURRENT_USER`).
- **Network**: Wired Ethernet LAN or private Wi-Fi network on the same IP subnet.
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
4. **Isolated Share Exposure**:
   - `1-Host-Network-Start.bat` shares **only** the `Client\` subdirectory. Host configuration, admin secrets, and server scripts are never exposed over SMB.
5. **Interactive Desktop Session Isolation**:
   - The desktop wallpaper is applied using Win32 `SystemParametersInfoW` within the logged-in user's interactive session. Non-interactive background SYSTEM services cannot update the user desktop.

---

## 📊 Measured Benchmark Results (100 Concurrent Clients)

The system includes an automated stress simulation suite (`Tests\Test-100Clients.ps1`) executing real end-to-end multi-step client transactions concurrently:

| Metric | Measured Value | Target Standard | Status |
| :--- | :--- | :--- | :--- |
| **Fleet Scale** | **100 Concurrent Workstations** | 30–100 Clients | ✅ PASS |
| **Total HTTP Transactions** | **400 Requests** | 400 Requests | ✅ PASS |
| **Wall-Clock Duration** | **1.89 seconds** | < 15 seconds | ✅ PASS |
| **Fleet Throughput** | **211.3 requests / sec** | > 50 req/sec | ✅ PASS |
| **Workflow Success Rate** | **100% (100 / 100)** | 100% | ✅ PASS |
| **Dropped / Failed Requests** | **0 Requests** | 0 Requests | ✅ PASS |
| **Average End-to-End Latency** | **300.2 ms** | < 1000 ms | ✅ PASS |
| **95th Percentile (p95) Latency**| **479 ms** | < 2000 ms | ✅ PASS |

---

## 🧪 Automated Test Verification

To run the complete automated test suite:
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
Publisher Engine (Validation & Atomic Sync) PASSED 2.05 s  
Client Engine (Win32 API & Local Cache)     PASSED 2.05 s  
Host Server (Routes, Tokens & RBAC)         PASSED 5.05 s  
Security Penetration (Traversal & Bypass)   PASSED 5.07 s  
Live Integration & Dynamic Reload Calls     PASSED 7.11 s  
100-Client Concurrency Load Benchmark       PASSED 7.08 s  
Service Separation & Stop-All Verification  PASSED 7.09 s  

Total Suites Run     : 7
Total Suites Passed  : 7 (100% Success Rate)
Total Suites Failed  : 0
Total Execution Time : 35.56 seconds
==============================================================================
FINAL VERDICT: PASS - 100% of test suites verified successfully.
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
