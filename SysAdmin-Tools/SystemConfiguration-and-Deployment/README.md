## ⚙️ System Configuration and Deployment Tools  
### Software Deployment · GPO Enforcement · Environment Standardization

![Suite](https://img.shields.io/badge/Suite-System%20Configuration%20%26%20Deployment-0A66C2?style=for-the-badge&logo=windows&logoColor=white) ![Scope](https://img.shields.io/badge/Scope-Workstations%20%7C%20Servers-informational?style=for-the-badge) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207.x-5391FE?style=for-the-badge&logo=powershell&logoColor=white) ![Focus](https://img.shields.io/badge/Focus-Automation%20%7C%20Compliance-critical?style=for-the-badge)

---

## 🧭 Overview

The **System Configuration and Deployment** suite provides a comprehensive set of **PowerShell automation tools** for **software deployment**, **GPO enforcement**, and **system baseline configuration** across **Windows workstations and servers** joined to **Active Directory (AD)**.

These tools are designed to support **large-scale deployments**, **secure configuration enforcement**, and **repeatable operational workflows**, ensuring consistency across environments while reducing manual administrative effort.

All scripts align with the engineering standards used throughout **Windows-SysAdmin-ProSuite**, including **GUI-first usability**, **structured logging**, and **audit-ready outputs**.

---

## 🌟 Key Features

- 🖼️ **GUI-First Experience** — Interactive tools suitable for administrators and support teams  
- 📝 **Centralized Logging** — Structured `.log` files generated on every execution  
- 🚀 **Streamlined Deployment** — Automated installation, update, and removal of software via GPO  
- 📐 **Configuration Baselines** — Enforces naming standards, volume labels, policies, and system settings  
- 🔐 **Policy Compliance** — Removes unauthorized software and reapplies domain policies consistently  

---

## 🛠️ Prerequisites

- **⚙️ PowerShell** — Version **5.1 or later** (PowerShell 7.x supported)  
  ```powershell
  $PSVersionTable.PSVersion
  ```

- **🔑 Administrative Privileges** — Required for deployment, registry, GPO, and system configuration tasks  

- **🖥️ RSAT Tools** — Required for Group Policy administration  
  ```powershell
  Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online
  ```

- **📦 Required Modules**
  - `GroupPolicy`
  - `PSWindowsUpdate` (when applicable)

- **🔧 Execution Policy** — Session-scoped execution  
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
  ```

---

# 📄 Script Catalog

---

## 🟦 PowerShell Automation Suite (.ps1)

| Script Name | Function |
|------------|----------|
| **Broadcast-ADUser-LogonMessage-viaGPO.ps1** | Displays customized logon messages to domain users via GPO |
| **Cleanup-WebBrowsers-Tool.ps1** | Clears browser cache, cookies, and session data |
| **Clear-and-ReSyncGPOs-ADComputers.ps1** | Resets and reapplies GPOs across all domain-joined machines |
| **Copy-and-Sync-Folder-to-ADComputers-viaGPO.ps1** | Synchronizes folders from network shares using GPO |
| **Deploy-FortiClientVPN-viaGPO.ps1** | Deploys FortiClient VPN across endpoints |
| **Deploy-FusionInventoryAgent-viaGPO.ps1** | Installs FusionInventory Agent for inventory tracking |
| **Deploy-GLPI-Agent-viaGPO.ps1** | Deploys GLPI Agent for asset and lifecycle management |
| **Deploy-JavaJRE-viaGPO.ps1** | Installs Java Runtime Environment silently |
| **Deploy-KasperskyAV-viaGPO.ps1** | Deploys Kaspersky Endpoint Security |
| **Deploy-LibreOfficeFullPackage-viaGPO.ps1** | Installs LibreOffice suite silently |
| **Deploy-PowerShell-viaGPO.ps1** | Ensures PowerShell runtime is installed and updated |
| **Deploy-ZoomWorkplace-viaGPO.ps1** | Deploys Zoom Workplace for enterprise communication |
| **Enhance-BGInfoDisplay-viaGPO.ps1** | Applies BGInfo overlays with system metadata |
| **Install-KMSLicensingServer-Tool.ps1** | Installs and configures a KMS licensing server |
| **Install-RDSLicensingServer-Tool.ps1** | Configures RDS Licensing Server and CAL management |
| **Install-Winget-on-Windows-Servers-viaGPO.ps1** | Installs `winget` CLI on Windows Server systems |
| **Remove-ReaQtaHive-Services-Tool.ps1** | Removes ReaQta services and residual components |
| **Remove-SharedFolders-and-Drives-viaGPO.ps1** | Removes non-compliant shared folders and mapped drives |
| **Remove-Softwares-NonCompliance-Tool.ps1** | Uninstalls specified non-compliant software locally |
| **Remove-Softwares-NonCompliance-viaGPO.ps1** | Automates software removal across domain machines |
| **Rename-DiskVolumes-viaGPO.ps1** | Enforces standardized disk volume labels |
| **Reset-and-Sync-DomainGPOs-viaGPO.ps1** | Forces full reapplication of all domain GPOs |
| **Retrieve-LocalMachine-InstalledSoftwareList.ps1** | Exports installed software list to `.csv` (ANSI encoded) |
| **Uninstall-SelectedApp-Tool.ps1** | GUI tool for selecting and removing applications |
| **Update-ADComputer-Winget-Explicit.ps1** | Updates selected packages via `winget` locally |
| **Update-ADComputer-Winget-viaGPO.ps1** | Pushes scheduled `winget` updates via GPO |

---

## 🟨 VBScript Maintenance Suite (.vbs)

| Script Name | Function |
|------------|----------|
| **Baseline-Maintenance-Server.vbs** | Automates server health checks (SFC/DISM), light Windows Update reset, controlled reboot handling, and structured logging — optimized for Scheduled Task deployment via GPO |
| **Baseline-Maintenance-Workstation.vbs** | Automates workstation remediation including Windows Update reset, local GPO baseline cleanup, SFC/DISM repair, and structured logging — optimized for Scheduled Task deployment via GPO |

---

## 🚀 Usage Instructions

1. Run scripts using **Run with PowerShell** or from an **elevated PowerShell console**  
2. Provide required parameters or interact via GUI (script-dependent)  
3. Review generated logs and reports  

### 📂 Logs and Reports Locations

| Path | Purpose |
|------|---------|
| `C:\Logs-TEMP\` | General-purpose deployment and execution logs |
| `C:\Scripts-LOGS\` | GPO synchronization and automation logs |
| `%USERPROFILE%\Documents\` | CSV and exported compliance reports |

---

## 📁 Complementary Files

- **Broadcast-ADUser-LogonMessage-viaGPO.hta** — GUI editor for domain logon messages  
- **Enhance-BGInfoDisplay-viaGPO.bgi** — BGInfo template for system metadata overlay  
- **Remove-Softwares-NonCompliance-Tool.txt** — Software removal definition list  

---

## 💡 Optimization Tips

- 🔁 Use **GPO startup scripts** for consistent deployment timing  
- 🗓️ Schedule maintenance with **Task Scheduler** where appropriate  
- 🗂️ Centralize logs for auditing and compliance review  
- 🧩 Parameterize scripts for reuse across environments  

---

© 2026 Luiz Hamilton Silva. All rights reserved.
