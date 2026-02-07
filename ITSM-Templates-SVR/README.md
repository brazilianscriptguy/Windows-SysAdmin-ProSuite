## 🖥️ ITSM-Templates-SVR Suite  
### Windows Server Standardization · Domain Compliance · ITSM Automation

![Suite](https://img.shields.io/badge/Suite-ITSM%20Templates%20SVR-0A66C2?style=for-the-badge&logo=windowsserver&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows%20Server-0078D6?style=for-the-badge&logo=windows&logoColor=white)
![Automation](https://img.shields.io/badge/Automation-PowerShell%20%7C%20VBScript-success?style=for-the-badge)
![Ops](https://img.shields.io/badge/Target-L2%20%7C%20L3%20Infrastructure-informational?style=for-the-badge)
![Compliance](https://img.shields.io/badge/Focus-ITSM%20%7C%20Security-critical?style=for-the-badge)

---

## 🧭 Overview

Welcome to **ITSM-Templates-SVR** — a standardized automation framework built with **PowerShell and VBScript** to enforce **baseline configuration, security hardening, and operational compliance** across **Windows Server environments**.

This suite mirrors the structure and governance model of **ITSM-Templates-WKS**, adapted for **server-class workloads**, including **member servers, infrastructure roles, and domain services**.

---

## 🌟 Key Features

- 🖼️ **Admin-Friendly Execution** — Scripts designed for Infrastructure and Server teams (L2/L3)  
- 📝 **Structured Logging** — Logs saved to `C:\ITSM-Logs-SVR\`  
- 📊 **CSV & Audit Reports** — Inventories and compliance outputs  
- 🔒 **Security & Baseline Enforcement** — Hardened defaults aligned with enterprise policy  
- 📦 **Role-Oriented Templates** — Ready for File Servers, Application Servers, and Infrastructure roles  

---

## 📄 Script Overview

### Folder: `/BeforeJoinDomain/`

| Script Name | Purpose |
|------------|---------|
| **ITSM-BeforeJoinDomain-SVR.ps1** | Pre-join server preparation: hostname, time sync, firewall baseline, WSUS, registry and role prerequisites. |

### Folder: `/AfterJoinDomain/`

| Script Name | Purpose |
|------------|---------|
| **ITSM-AfterJoinDomain-SVR.ps1** | Post-join automation: DNS registration, GPO refresh, service validation, and domain alignment. |

### Folder: `/Assets/AdditionalSupportScripts/`

| Script Name | Purpose |
|------------|---------|
| **CheckServerRoles.ps1** | Lists installed roles/features for validation. |
| **ExportServerConfig.ps1** | Exports server configuration to CSV. |
| **FixNTFSPermissions.ps1** | Repairs NTFS permission inconsistencies. |
| **InventoryServerSoftware.ps1** | Generates inventory of installed software. |
| **ITSM-HardenServer.ps1** | Applies security hardening (SMB, accounts, protocols). |
| **ResetGPOSettings.ps1** | Forces reapplication of domain GPOs. |
| **ServerTimeSync.ps1** | Syncs server time with domain controllers. |
| **UnjoinADServer-and-Cleanup.ps1** | Safely removes server from domain and cleans metadata. |

---

## 🧭 Execution Order Summary

1. Prepare OS and patch baseline  
2. Execute **ITSM-BeforeJoinDomain-SVR.ps1**  
3. Rename disks and validate storage layout  
4. Join domain using delegated account  
5. Execute **ITSM-AfterJoinDomain-SVR.ps1**  
6. Validate logs and compliance reports  

---

## 🏷️ Hostname Format (Servers)

```text
<LOC><ROLE><UNIT><ASSET>
Example: MIASRVFILEO23017
```

| Component | Meaning |
|----------|---------|
| LOC | Location code (e.g., MIA, BOS) |
| ROLE | SRVFILE, SRVAPP, SRVDC |
| UNIT | Organizational unit |
| ASSET | Asset ID |

---

## 🚀 Getting Started

```bash
git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
```

```powershell
cd Windows-SysAdmin-ProSuite/ITSM-Templates-SVR/
.\ScriptName.ps1
```

---

## 📝 Logging & Reporting

- **Logs:** `C:\ITSM-Logs-SVR\`  
- **Reports:** CSV exports per execution  

---

## 💡 Optimization Tips

- 🔁 Schedule enforcement via Task Scheduler or GPO  
- 🗂️ Centralize logs to secured network share  
- 🧩 Clone templates per server role  

---

## 📌 Document Classification

**RESTRICTED:** Internal use only. Confidential to Infrastructure and Security teams.

---

© 2026 Luiz Hamilton Silva. All rights reserved.
