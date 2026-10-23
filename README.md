# 🖼️ LAN Dynamic Wallpaper Slideshow System

[![Platform](https://img.shields.io/badge/Platform-Windows%2011%20%7C%20Windows%2010-0078D6.svg?logo=windows)](https://microsoft.com)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20(Pure)-5391FE.svg?logo=powershell)](https://microsoft.com/powershell)
[![Architecture](https://img.shields.io/badge/Architecture-Host%20%2F%20Client%20RBAC-107C41.svg)]()
[![Dependencies](https://img.shields.io/badge/Dependencies-Zero%20(Built--in%20Only)-success.svg)]()
[![Fleet Capacity](https://img.shields.io/badge/Fleet%20Capacity-30--100%20Client%20Nodes-blueviolet.svg)]()
[![Test Verdict](https://img.shields.io/badge/Automated%20Tests-100%25%20PASS%20(5%2F5%20Suites)-brightgreen.svg)]()

A high-performance, enterprise-grade, **pure PowerShell-only** LAN Dynamic Wallpaper Slideshow System designed for Windows 11 and Windows 10 computer fleets on local Ethernet networks.

---

## ⚡ Quick Start: Exactly What You Need to Do (Easy 2-Step Setup)

Setting up and running the dynamic wallpaper slideshow across your office, school, or computer lab network takes **less than 1 minute**. No installation packages, no third-party runtimes, and no manual command typing needed.

The entire user-facing system is controlled with **exactly two batch files**:

```
Step 1: Host Administrator PC                          Step 2: Client Workstations (30–100 PCs)
+------------------------------------+                 +------------------------------------+
| Right-click Start-Host.bat         |      LAN        | Right-click Start-Client.bat       |
| Select "Run as administrator"      |   Sync Stream   | Select "Run as administrator"      |
| -> Drops photos into Wallpapers/   | --------------> | -> Auto-discovers Host on LAN      |
| -> Starts Host Server & Slideshow  |                 | -> Syncs photos & sets desktop     |
+------------------------------------+                 +------------------------------------+
```

---

### 🖥️ Step 1: On the Host PC (The Administrator Computer)

1. Right-click **`Start-Host.bat`** and select **Run as administrator**.
2. If prompted by Windows User Account Control (UAC), click **Yes**.
3. The launcher automatically:
   - Configures the Windows Defender Firewall rules for TCP `8765` and UDP `8766`.
   - Idempotently reserves the HTTP.sys URL ACL (`http://+:8765/`).
   - Automatically opens the **`Wallpapers/`** folder in Windows Explorer on your screen!
4. **Drop your photos** into this `Wallpapers/` folder:
   - Supported formats: **JPG, JPEG, PNG, BMP, GIF, WEBP, TIFF** (and HEIC if the Windows HEIF extension is present).
5. The Host immediately sets its own desktop wallpaper and rotates through all images every **5 seconds**!
6. **Keep `Start-Host.bat` open** (you can minimize the window).

---

### 💻 Step 2: On Client PCs (All 30–100 Lab/Office Computers)

1. Copy the project folder to the client computer (via USB drive or LAN network share).
2. Right-click **`Start-Client.bat`** and select **Run as administrator** for initial setup.
3. **That's all!**
   - You do **NOT** need to edit JSON files or type any IP addresses.
   - The client automatically scans the LAN, discovers the Host PC, registers itself, receives its provisioned client token, downloads all photos, and immediately updates the desktop wallpaper.
   - **Automatic Daily Startup**: The launcher registers background startup for the logged-in user in `HKCU:\Software\Microsoft\Windows\CurrentVersion\Run`. Users do **NOT** need to run the launcher as administrator every day—after initial setup, the wallpaper agent starts automatically upon user logon.

---

### 💡 Frequently Asked Actions

| What You Want to Do | How to Do It in 1 Step |
| :--- | :--- |
| **Add a new photo** | Just drop the photo file into `Wallpapers/` on the Host PC. Within 10 seconds, all client computers will automatically start showing it! |
| **Remove a photo** | Delete the file from `Wallpapers/` on the Host PC. All client computers immediately stop showing it. |
| **Change the 5-second timer** | Open `Host\HostConfig.json` in Notepad, change `"DefaultIntervalSeconds": 5` to any number you want (e.g. `10` or `30`), and save. |
| **Check connected clients** | Open PowerShell and run `powershell -File Tools\Deployment-Report.ps1` to view live client workstations. |
| **Run verification tests** | Open PowerShell and run `powershell -ExecutionPolicy Bypass -File Tests\Run-All-Tests.ps1`. |

---

## ⚡ Key Highlights & Architecture

- **Zero External Dependencies**: Operates exclusively using built-in Windows PowerShell 5.1+, Windows APIs via Win32 P/Invoke (`SystemParametersInfoW`), and the Windows Firewall. **No Python, Node.js, Java, databases, or cloud services required**.
- **Exactly Two User-Facing Launchers**: Eliminates confusing multiple scripts or installers. The system exposes strictly `Start-Host.bat` and `Start-Client.bat`.
- **1 Host to 30–100 Clients**: Scales smoothly to 100+ concurrent Windows workstations with sub-second synchronization and zero dropped requests.
- **Dynamic Content Lifecycle**: Automatically detects when wallpapers are added, modified, renamed, or deleted in the host directory, recalculates cryptographic SHA-256 hashes, and publishes versioned atomic manifests.
- **Role-Based Access Control (RBAC)**:
  - **`SuperAdmin / HostAdmin`**: Full control over host synchronization, fleet management, client roster audits, and system configuration via `AdminSecret`.
  - **`ClientNode`**: Restricted access to authenticated manifest retrieval, binary asset streaming, and heartbeat telemetry via provisioned `clientToken`.
  - **`Monitor / Auditor`**: Unauthenticated read-only health probe access (`/api/v1/health`) for network monitoring tools.
- **Zero Hardcoded Secrets in Git**: No production credentials, tokens, or personal passwords are committed to source control. Secrets are generated cryptographically on first run and stored locally with strict Windows ACLs.
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
├── Start-Host.bat               # 🖥️ 1-CLICK HOST LAUNCHER (Run as administrator on Host PC)
├── Start-Client.bat             # 💻 1-CLICK CLIENT LAUNCHER (Run as administrator for initial setup on Client PCs)
├── Host/
│   ├── Host.ps1                 # Multi-threaded HTTP listener & UDP discovery daemon
│   ├── Publisher.ps1            # Format converter, magic-byte validator, SHA-256 hasher, manifest generator
│   └── HostConfig.json          # Host network, port, security, and slideshow settings
├── Client/
│   ├── Client.ps1               # Client background synchronization and health agent
│   ├── Wallpaper.ps1            # Win32 P/Invoke desktop wallpaper rotation engine
│   └── ClientConfig.json        # Client network, host IP, secret, and interval settings
├── Wallpapers/                  # 📂 SINGLE PHOTO VAULT (Drop photos here; manifest & distribution managed here)
├── Tools/
│   ├── Find-Host.ps1            # LAN UDP broadcast discovery utility
│   ├── Test-Connection.ps1      # End-to-end network & auth verification tool
│   ├── Diagnose.ps1             # Comprehensive system, port, firewall & task inspector
│   └── Deployment-Report.ps1    # Fleet telemetry and online client roster viewer
├── Tests/
│   ├── Run-All-Tests.ps1        # Master test harness executing all 5 suites with summary scorecard
│   ├── Test-Host.ps1            # Automated suite for host endpoints, tokens & RBAC (17 tests)
│   ├── Test-Publisher.ps1       # Automated suite for file watcher, magic bytes & hashing (13 tests)
│   ├── Test-Client.ps1          # Automated suite for Win32 API, rotation & mutex (10 tests)
│   ├── Test-Security.ps1        # Penetration suite for path traversal & auth bypass (15 tests)
│   └── Test-100Clients.ps1      # 100-client concurrent load benchmark simulation (100 nodes, 400 reqs)
├── README.md                    # Primary system architecture, quickstart, and reference
├── INSTALLATION-GUIDE.md        # Comprehensive host and client deployment manual
├── TROUBLESHOOTING.md           # Diagnostic flowcharts and remediation guide
└── SECURITY.md                  # Threat model, RBAC policies and defense mechanisms
```

---

## 🖥️ Supported Operating Systems & Prerequisites

- **Operating System**: Windows 11 (all editions) or Windows 10 (Version 1809 or newer, 64-bit/32-bit).
- **PowerShell**: Windows PowerShell 5.1 (built into Windows) or PowerShell 7.x.
- **Host Permissions**: Administrator elevation required on the Host PC to bind port `8765` and register scoped Windows Firewall rules.
- **Client Permissions**: Administrator elevation is required only during initial setup (`Start-Client.bat`) to configure auto-start. Normal ongoing wallpaper rotation runs as a **standard user** in the interactive desktop session.
- **Network**: Wired Ethernet LAN or stable private Wi-Fi network on the same IP subnet.
- **Supported Formats**: `.jpg`, `.jpeg`, `.png`, `.bmp`, `.gif`, `.webp`, `.tiff`. Video files (`.mp4`, `.mov`) are supported for snapshot wallpaper extraction when the Windows Media Foundation codecs are installed.

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

For exhaustive threat modeling and defensive details, see [SECURITY.md](SECURITY.md).

---

## 📊 Measured Benchmark Results (100 Concurrent Clients)

The system includes an automated stress simulation suite (`Tests\Test-100Clients.ps1`) executing real end-to-end multi-step client transactions (Registration, Manifest retrieval, Binary download, Heartbeat telemetry) concurrently:

| Metric | Measured Value | Target Standard | Status |
| :--- | :--- | :--- | :--- |
| **Fleet Scale** | **100 Concurrent Workstations** | 30–100 Clients | ✅ PASS |
| **Total HTTP Transactions** | **400 Requests** | 400 Requests | ✅ PASS |
| **Wall-Clock Duration** | **1.09 seconds** | < 15 seconds | ✅ PASS |
| **Fleet Throughput** | **365.5 requests / sec** | > 50 req/sec | ✅ PASS |
| **Workflow Success Rate** | **100% (100 / 100)** | 100% | ✅ PASS |
| **Dropped / Failed Requests** | **0 Requests** | 0 Requests | ✅ PASS |
| **Average End-to-End Latency** | **176 ms** | < 1000 ms | ✅ PASS |
| **95th Percentile (p95) Latency**| **259 ms** | < 2000 ms | ✅ PASS |

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
Publisher Engine (Validation & Atomic Sync) PASSED 1.03 s  
Client Engine (Win32 API & Local Cache)     PASSED 1.02 s  
Host Server (Routes, Tokens & RBAC)         PASSED 4.03 s  
Security Penetration (Traversal & Bypass)   PASSED 4.06 s  
100-Client Concurrency Load Benchmark       PASSED 5.04 s  

Total Suites Run     : 5
Total Suites Passed  : 5
Total Suites Failed  : 0
Total Execution Time : 15.21 seconds
==============================================================================
FINAL VERDICT: PASS - 100% of test suites verified successfully.
```

---

## 🗑️ Uninstallation & Safe Cleanup

To remove the system from a computer:

### On Client Workstations:
1. Close the client console window if running.
2. Remove the auto-start entry from the Windows registry:
   ```powershell
   Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "LAN-Dynamic-Wallpaper-Client" -ErrorAction SilentlyContinue
   ```
3. Delete the local `Cache/` folder and project files.

### On the Host PC:
1. Close the host console window.
2. Remove the Windows Defender Firewall rules:
   ```powershell
   Remove-NetFirewallRule -DisplayName "LAN-Dynamic-Wallpaper-Host-*" -ErrorAction SilentlyContinue
   ```
3. Remove the HTTP.sys URL ACL reservation:
   ```cmd
   netsh http delete urlacl url=http://+:8765/
   ```

---

## ⚠️ Known Limitations

1. **Subnet Boundaries**: UDP auto-discovery relies on LAN broadcast packets (`port 8766`). If client computers reside on a different subnet or VLAN where routers drop UDP broadcast, configure the Host IP address in `Client\ClientConfig.json` under `"HostAddress"`.
2. **Network Profiles**: Windows Firewall blocks inbound connections on the **Public** network category. Ensure the Host computer's Ethernet connection is configured as **Private** or **Domain**.
3. **HTTP on Local LAN**: By default, communication across the local network uses plain HTTP on port `8765`. For untrusted or public networks, configure IPsec transport or HTTPS with an enterprise certificate.

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
