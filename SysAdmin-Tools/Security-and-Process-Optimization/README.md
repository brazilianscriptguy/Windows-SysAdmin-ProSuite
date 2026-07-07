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
|-------------|-------------|
| **Check-ServicesPort-Connectivity.ps1** | Tests real-time TCP connectivity to specified service ports for diagnostics and troubleshooting. |
| **Cleanup-CertificateAuthority.ps1** | Removes obsolete certificate records from Microsoft AD CS Certificate Authority databases based on configurable retention policies. |
| **Cleanup-Repository-ExpiredCertificates.ps1** | Removes expired certificate files from repository locations according to configurable retention policies. |
| **Initiate-MultipleRDPSessions.ps1** | Launches multiple Remote Desktop (RDP) sessions simultaneously to streamline administrative access. |
| **Manage-PKICertificateLifecycle.ps1** | Manages Microsoft AD CS certificate lifecycle, automated revocation, CA database maintenance, CRL publication, and governance reporting. |
| **Organize-CERTs-Repository.ps1** | Organizes SSL/TLS certificate repositories by issuer, expiration date, and certificate metadata. |
| **Purge-ExpiredInstalledCertificates-viaGPO.ps1** | Automates enterprise-wide removal of expired certificates through Group Policy deployment. |
| **Purge-ExpiredInstalledCertificates.ps1** | Removes expired certificates from local Windows certificate stores. |
| **Remove-EmptyFiles-or-DateRange.ps1** | Removes empty files or files older than a specified age from selected directories. |
| **Retrieve-Windows-ProductKey.ps1** | Retrieves the installed Windows product key for inventory, auditing, and asset management. |
| **Shorten-LongFileNames.ps1** | Renames excessively long file and folder paths to improve compatibility with backup, synchronization, and legacy applications. |
| **Unjoin-ADComputer-and-Cleanup.ps1** | Securely removes computers from Active Directory and performs post-unjoin cleanup operations. |

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
