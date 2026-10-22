# 🛡️ LAN Dynamic Wallpaper: Security Architecture & Threat Model

This document outlines the security architecture, threat model, authorization mechanics, defensive controls, and operational guidelines for the LAN Dynamic Wallpaper Slideshow System.

---

## 🔒 Security Principles & Objectives

1. **Least Privilege**: The client agent operates strictly within the non-elevated interactive user session and never requires permanent administrator rights.
2. **Defensive Input Handling**: Strict rejection of path traversal, directory escaping, spoofed file formats, and high-entropy malicious payloads.
3. **Role-Based Access Control (RBAC)**: Enforced segregation of duties between Administrators, Client Workstations, and Health Monitors.
4. **Zero Command Execution**: Client nodes never accept or execute arbitrary remote scripts or shell commands. Downloaded data is treated exclusively as static image binaries.
5. **Zero Secret Exposure**: Authentication credentials must never be committed to source control or logged in console/file telemetry.

---

## 👥 Role-Based Access Control (RBAC) Matrix

The system implements a multi-tier RBAC architecture:

| Role | Permitted Endpoints | Authentication Required | Purpose |
| :--- | :--- | :--- | :--- |
| **`SuperAdmin / HostAdmin`** | `/api/v1/admin/clients`<br>`/api/v1/admin/sync`<br>All Client endpoints | **Yes** (`AdminSecret` / Bearer token) | Full administrative oversight, client roster telemetry, manual force-sync trigger. |
| **`ClientNode`** | `/api/v1/auth/register`<br>`/api/v1/manifest`<br>`/api/v1/wallpaper/{file}`<br>`/api/v1/heartbeat` | **Yes** (`AuthSecret` / `X-Auth-Token`) | Enrolling client workstations, fetching manifests, streaming verified image binaries, reporting heartbeat telemetry. |
| **`Monitor / Auditor`** | `/api/v1/health` | **No** (Public / Intranet) | Health probes, Prometheus/Nagios integration, uptime monitoring, collection version status. |

---

## 🛑 Defensive Controls & Countermeasures

### 1. Path Traversal & Out-of-Bounds File Protection
Malicious clients or network attackers might attempt to craft HTTP requests like `/api/v1/wallpaper/../../../../windows/system32/cmd.exe` or URL-encoded variations like `%2e%2e%2f` to exfiltrate system files.

**Countermeasures Implemented in `Host.ps1`**:
1. **URL Decoding**: The request path is unescaped using `[System.Uri]::UnescapeDataString()`.
2. **Regex Guard**: Any string matching directory separators (`/`, `\`), path traversal patterns (`..`), or Windows invalid filename characters (`:`, `*`, `?`, `"`, `<`, `>`, `|`) is instantly blocked with HTTP 400 Bad Request.
3. **Canonical Path Resolution**: The target path is converted to a canonical full path using `[System.IO.Path]::GetFullPath()`.
4. **Boundary Verification**: The canonical path is verified using `StartsWith()` against the absolute `Wallpapers\` directory path. If an attacker bypasses filters, the boundary check rejects the request with HTTP 403 Forbidden.

### 2. Magic-Byte Image Validation (Anti-Malware & Anti-Spoofing)
Attackers might rename malicious executables (`.exe`), scripts (`.ps1`, `.bat`), or exploit payloads with `.jpg` extensions.

**Countermeasures Implemented in `Publisher.ps1`**:
- The host reads the leading bytes of every file before publication and validates magic numbers:
  - **JPEG**: Must begin with `FF D8 FF`.
  - **PNG**: Must begin with `89 50 4E 47 0D 0A 1A 0A`.
  - **BMP**: Must begin with `42 4D` (`BM`).
- Files with zero bytes, unsupported formats, or disguised executables are rejected with explicit audit warnings and never published to the manifest.

### 3. Cryptographic Image Hashing (SHA-256)
- The host calculates the SHA-256 cryptographic hash of every published image.
- The hash is transmitted in the signed `manifest.json` and in the `X-Image-Sha256` HTTP header.
- The client verifies the SHA-256 hash of the downloaded payload before moving it into the active cache. Corrupted downloads or MITM altered files are discarded immediately.

### 4. Single-Instance Mutex Protection
To prevent race conditions, disk lockup, or rogue background processes, the client agent acquires a named system mutex:
`Global\LAN_Dynamic_Wallpaper_Client_Mutex`
If a duplicate client process attempts to launch, it detects the active mutex and terminates cleanly within 500 milliseconds.

### 5. Windows Firewall Rules Scoping
The host installer creates narrowly scoped firewall rules using Windows Firewall APIs:
- Protocol: `TCP` (Port `8765`), `UDP` (Port `8766`).
- Profiles: **Private and Domain only**.
- Public network profile is explicitly excluded.
- Global disabling of the Windows Firewall is strictly prohibited.

---

## 🌐 Network Transport Security (HTTP vs HTTPS)

### Current Architecture: High-Performance Plain HTTP on Trusted LANs
This solution defaults to lightweight .NET `HttpListener` over plain HTTP on port `8765`.
- **Advantages**: Built into all Windows installations without requiring PKI infrastructure, Active Directory Certificate Services (AD CS), internal root CAs, or custom certificate trust stores across 100 client workstations.
- **Trade-off**: Traffic is unencrypted on the local Ethernet cable. An attacker with a physical tap or executing ARP spoofing on an unmanaged switch could view the wallpaper images and sniff the authentication token.

### Recommendations for High-Security / Untrusted Environments
If the local LAN is shared with untrusted guests or unmanaged BYOD devices:
1. **802.1X Port Authentication**: Enforce network access control (NAC) on physical switch ports.
2. **Dedicated VLAN**: Isolate the Host PC and Client workstations into a dedicated management or presentation VLAN.
3. **IPsec Transport Mode**: Enable Windows IPsec domain isolation to encrypt all peer-to-peer traffic transparently at the Windows kernel level without application modifications.
4. **HTTPS via URL ACL & SSL Cert**:
   If internal TLS certificates are available, bind a certificate to port `8765` using `netsh http add sslcert`:
   ```cmd
   netsh http add sslcert ipport=0.0.0.0:8765 certhash=<CERT_THUMBPRINT> appid={00112233-4455-6677-8899-AABBCCDDEEFF}
   ```

---

## 🔑 Git & Credential Hygiene Guidelines

- **Zero Hardcoded Secrets**: Real API tokens, personal passwords, or private encryption keys must never be hardcoded in git-tracked code, tests, or documentation.
- **Environment Isolation**: `.gitignore` must strictly exclude all active configuration files, `.env` files, and local log directories containing operational telemetry.
- **Pre-Commit Audit**: Prior to staging commits, inspect the diff (`git diff --cached`) for high-entropy strings or leaked connection credentials.
