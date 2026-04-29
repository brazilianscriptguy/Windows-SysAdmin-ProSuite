## 🛠️ Active Directory Management Tools  
### Identity Administration · Domain Automation · AD Governance

![Suite](https://img.shields.io/badge/Suite-Active%20Directory%20Management-0A66C2?style=for-the-badge&logo=windows&logoColor=white) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207.x-5391FE?style=for-the-badge&logo=powershell&logoColor=white) ![Scope](https://img.shields.io/badge/Scope-Users%20%7C%20Computers%20%7C%20GPOs-informational?style=for-the-badge) ![Focus](https://img.shields.io/badge/Focus-AD%20Automation%20%7C%20Compliance-critical?style=for-the-badge)

---

## 🧭 Overview

The **Active Directory Management Tools** suite provides **enterprise-grade PowerShell automation** for managing and governing **Active Directory (AD)** environments.

These tools are designed to streamline and standardize operations such as:

- User and computer provisioning  
- OU structure creation and maintenance  
- Password, expiration, and lifecycle enforcement  
- GPO management and auditing  
- Inventory, reporting, and compliance validation  

All scripts follow the same engineering standards used across **Windows-SysAdmin-ProSuite**, ensuring **deterministic execution, structured logging, and audit-ready outputs**.

---

## 🌟 Key Features

- 🖼️ **GUI-Enabled Tools** — Simplified workflows for complex AD operations  
- 📝 **Comprehensive Logging** — Structured `.log` files for traceability and diagnostics  
- 📊 **Exportable Reports** — `.csv` outputs for documentation, audits, and compliance  
- ⚙️ **Efficient AD Automation** — Eliminates repetitive and error-prone manual tasks  

---

## 🛠️ Prerequisites

- **⚙️ PowerShell** — Version **5.1 or later** (PowerShell 7.x supported)  
  ```powershell
  $PSVersionTable.PSVersion
  ```

- **📦 Active Directory Module** — Required for most scripts  
  ```powershell
  Import-Module ActiveDirectory
  ```

- **🖥️ RSAT Tools** — Required for AD administration  
  ```powershell
  Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online
  ```

- **🔑 Administrative Privileges** — Required to modify AD objects and policies  

- **🔧 Execution Policy** — Session-scoped execution  
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
  ```

---

## 📄 Script Catalog (Alphabetical)

| Script Name | Description |
|------------|-------------|
| **Add-ADComputers-GrantPermissions.ps1** | Adds AD computers to OUs and grants domain join permissions |
| **Add-ADInetOrgPerson.ps1** | Creates `InetOrgPerson` objects with detailed attributes |
| **Add-ADUserAccount.ps1** | GUI-based AD user creation in specific OUs |
| **Adjust-ExpirationDate-ADUserAccount.ps1** | Updates expiration dates for AD user accounts |
| **Check-Shorter-ADComputerNames.ps1** | Flags computer accounts with short or non-compliant names |
| **Cleanup-Inactive-ADComputerAccounts.ps1** | Deletes stale computer objects from AD |
| **Cleanup-MetaData-ADForest-Tool.ps1** | Cleans orphaned metadata and synchronizes the AD forest |
| **Create-OUsDefaultADStructure.ps1** | Builds a standard OU layout for a domain |
| **Enforce-Expiration-ADUserPasswords.ps1** | Enforces password expiration policies |
| **Export-n-Import-GPOsTool.ps1** | GUI tool for GPO export and import |
| **Fix-ADForest-DNSDelegation.ps1** | Resolves DNS delegation issues in the forest |
| **Inventory-ADComputers-and-OUs.ps1** | GUI inventory of computers and OU structure |
| **Inventory-ADDomainComputers.ps1** | Exports a flat list of domain-joined computers |
| **Inventory-ADGroups-their-Members.ps1** | Lists all AD groups and their members |
| **Inventory-ADMemberServers.ps1** | Collects information on all member servers |
| **Inventory-ADUserAttributes.ps1** | Exports full AD user attributes to CSV |
| **Inventory-ADUserLastLogon.ps1** | Tracks last logon timestamps |
| **Inventory-ADUserWithNonExpiringPasswords.ps1** | Identifies accounts with non-expiring passwords |
| **Inventory-InactiveADComputerAccounts.ps1** | Detects unused computer accounts |
| **Manage-Disabled-Expired-ADUserAccounts.ps1** | Manages expired and disabled user accounts |
| **Manage-FSMOs-Roles.ps1** | Views and transfers FSMO roles |
| **Manage-SMBShare-And-NTFSPermissions.ps1** | Manages SMB share access and audits NTFS permissions for AD groups across enterprise environments |
| **Move-ADComputer-betweenOUs.ps1** | Moves computers between OUs |
| **Move-ADUser-betweenOUs.ps1** | Moves users between OUs with filtering |
| **Reset-ADUserPasswordsToDefault.ps1** | Bulk password reset to secure defaults |
| **Retrieve-ADComputer-SharedFolders.ps1** | Retrieves shared folders from AD computers |
| **Retrieve-ADDomain-AuditPolicy-Configuration.ps1** | Extracts domain audit policy configuration |
| **Retrieve-Elevated-ADForestInfo.ps1** | Retrieves privileged forest and role information |
| **Synchronize-n-HealthCheck-ADForestDCs.ps1** | Forces replication across domain controllers and checks DCs and Forest health |
| **Update-ADComputer-Descriptions.ps1** | Updates computer object descriptions |
| **Update-ADUserDisplayName.ps1** | Applies standardized display name formats |

---

## 🚀 Usage Instructions

1. Run scripts using **Run with PowerShell** or from an **elevated PowerShell console**  
2. Provide the required parameters or interact via the GUI (script-dependent)  
3. Review the generated outputs  

### 📂 Logs and Reports Locations

| Path                        | Purpose                                                                 |
|-----------------------------|-------------------------------------------------------------------------|
| `C:\Scripts-LOGS\`          | GPO synchronization, agents, and security tooling logs                  |
| `C:\Logs-TEMP\`             | General-purpose, transient, and legacy script outputs                   |
| `%USERPROFILE%\Documents\`  | CSV and exported reports for compliance, forensics, and ITSM workflows  |

---

## 📄 Complementary Files

- `GPO-Template-Backup.zip` — Sample GPO export archive  
- `Default-AD-OUs.csv` — Reference OU structure used in provisioning  
- `Password-Reset-Log.log` — Example password reset audit log  

---

## 💡 Optimization Tips

- 🔁 Automate execution using Task Scheduler or GPOs  
- 🗂️ Centralize logs to a network share or SIEM pipeline  
- 🧩 Customize OU paths, naming standards, and policies to match enterprise design  

---

© 2026 Luiz Hamilton Silva. All rights reserved.
