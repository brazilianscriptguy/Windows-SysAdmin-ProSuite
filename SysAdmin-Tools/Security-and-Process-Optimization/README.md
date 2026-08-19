## 🛡️ Security and Process Optimization Tools  

## 🧭 Overview

The **Security and Process Optimization** suite provides a focused collection of **PowerShell automation tools** designed to improve **certificate hygiene**, **file system compliance**, **licensing visibility**, and **privileged access control**.

These scripts enable **safe automation of sensitive operations**, reduce manual administrative overhead, and strengthen the overall **security posture** of Windows enterprise environments.

---

## 🌟 Key Features

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
| **Initiate-MultipleRDPSessions.ps1** | Launches multiple Remote Desktop (RDP) sessions simultaneously to streamline administrative access. |
| **Remove-EmptyFiles-or-DateRange.ps1** | Removes empty files or files older than a specified age from selected directories. |
| **Repair-CyberArkIdentityConnector-DCReArm.ps1** | Re-arms the CyberArk Identity Connector service on selected Active Directory Domain Controllers. |
| **Retrieve-Windows-ProductKey.ps1** | Retrieves the installed Windows product key for inventory, auditing, and asset management. |
| **Shorten-LongFileNames-Tool.ps1** | Renames excessively long file and folder paths to improve compatibility with backup, synchronization, and legacy applications. |
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
