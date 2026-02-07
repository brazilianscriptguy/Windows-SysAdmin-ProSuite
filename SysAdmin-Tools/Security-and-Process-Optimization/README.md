## 🛡️ Security and Process Optimization Tools  
### Certificate Hygiene · Compliance Audits · Privileged Operations

![Suite](https://img.shields.io/badge/Suite-Security%20%26%20Process%20Optimization-0A66C2?style=for-the-badge&logo=windows&logoColor=white) ![Scope](https://img.shields.io/badge/Scope-Certificates%20%7C%20Access%20%7C%20Storage-informational?style=for-the-badge) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207.x-5391FE?style=for-the-badge&logo=powershell&logoColor=white) ![Focus](https://img.shields.io/badge/Focus-Security%20Posture%20%7C%20Compliance-critical?style=for-the-badge)

---

## 🧭 Overview

The **Security and Process Optimization** suite provides a focused collection of **PowerShell automation tools** designed to improve **certificate hygiene**, **file system compliance**, **licensing visibility**, and **privileged access control**.

These scripts enable **safe automation of sensitive operations**, reduce manual administrative overhead, and strengthen the overall **security posture** of Windows enterprise environments.

---

## 🌟 Key Features

- 🔐 **Certificate Management** — Cleanup of expired certificates and organization of shared repositories  
- 📋 **Access & Compliance Audits** — Inventory of product keys, elevated accounts, shared folders, and software  
- 🗄️ **Storage & File Optimization** — Cleanup of empty, aged, or non-compliant files and long paths  
- 🧹 **Safe Offboarding** — Secure domain unjoin with cleanup of AD, DNS, and metadata  

---

## 🛠️ Prerequisites

- **⚙️ PowerShell** — Version **5.1 or later** (PowerShell 7.x supported)  
  ```powershell
  $PSVersionTable.PSVersion
  ```

- **🔑 Administrative Privileges** — Required for certificate stores, registry, disk, and AD operations  

- **🔧 Execution Policy** — Session-scoped execution  
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
  ```

---

## 📄 Script Catalog (Alphabetical)

| Script Name | Description |
|------------|-------------|
| **Check-ServicesPort-Connectivity.ps1** | Tests real-time connectivity for specified service ports |
| **Cleanup-CertificateAuthority-Tool.ps1** | Removes expired certificate data from CA servers |
| **Cleanup-Repository-ExpiredCertificates-Tool.ps1** | Deletes expired certificates from shared repositories |
| **Initiate-MultipleRDPSessions.ps1** | Initiates multiple RDP sessions on supported systems |
| **Organize-CERTs-Repository.ps1** | Organizes SSL/TLS certificates by issuer or expiration |
| **Purge-ExpiredInstalledCertificates-Tool.ps1** | Removes expired certificates from the local machine store |
| **Purge-ExpiredInstalledCertificates-viaGPO.ps1** | GPO-compatible cleanup of expired certificates |
| **Remove-EmptyFiles-or-DateRange.ps1** | Deletes empty or aged files based on defined criteria |
| **Retrieve-Windows-ProductKey.ps1** | Extracts the local Windows product key for auditing |
| **Shorten-LongFileNames-Tool.ps1** | Shortens long file paths to avoid backup or sync failures |
| **Unjoin-ADComputer-and-Cleanup.ps1** | Securely unjoins systems from AD and cleans metadata |

---

## 🚀 Usage Instructions

1. Run scripts using **Run with PowerShell** or from an **elevated PowerShell console**  
2. Provide required parameters or respond to input prompts (script-dependent)  
3. Review generated outputs and logs  

### 📂 Logs and Reports Locations

| Path | Purpose |
|------|---------|
| `C:\Scripts-LOGS\` | GPO synchronization, agents, and security tooling logs |
| `C:\Logs-TEMP\` | General-purpose, transient, and legacy script outputs |
| `%USERPROFILE%\Documents\` | CSV and exported reports for compliance and audits |

---

## 💡 Optimization Tips

- 🏷️ Prefer **GPO-compatible scripts** for domain-wide enforcement  
- 🔁 Schedule periodic cleanup using **Task Scheduler**  
- 🗂️ Maintain structured repositories for certificates and shared files  

---

© 2026 Luiz Hamilton Silva. All rights reserved.
