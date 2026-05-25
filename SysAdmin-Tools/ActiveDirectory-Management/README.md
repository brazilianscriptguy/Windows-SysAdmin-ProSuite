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
| **Add-ADComputers-GrantPermissions.ps1** | Adds Active Directory computers to organizational units and delegates domain join permissions |
| **Add-ADInetOrgPerson.ps1** | Creates `InetOrgPerson` directory objects with extended enterprise attributes |
| **Add-ADUserAccount.ps1** | Provides GUI-based Active Directory user provisioning for organizational units |
| **Adjust-ExpirationDate-ADUserAccount.ps1** | Modifies expiration dates for Active Directory user accounts |
| **Check-Shorter-ADComputerNames.ps1** | Identifies short, invalid or non-compliant computer naming standards |
| **Cleanup-MetaData-ADForest-Tool.ps1** | Removes orphaned metadata objects and reconciles Active Directory forest consistency |
| **Create-OUsDefaultADStructure.ps1** | Creates a standardized organizational unit hierarchy for Active Directory domains |
| **Enforce-Expiration-ADUserPasswords.ps1** | Enforces password expiration governance policies for Active Directory users |
| **Export-n-Import-GPOsTool.ps1** | Provides GUI-based backup, export and import management for Group Policy Objects |
| **Fix-ADForest-DNSDelegation.ps1** | Detects and repairs DNS delegation inconsistencies across the Active Directory forest |
| **Inventory-ADComputers-and-OUs.ps1** | Generates graphical inventory reports for computers and organizational units |
| **Inventory-ADDomainComputers.ps1** | Exports inventory data for all domain-joined computer accounts |
| **Inventory-ADGroups-their-Members.ps1** | Enumerates Active Directory groups and their associated memberships |
| **Inventory-ADMemberServers.ps1** | Collects inventory and operational information from Active Directory member servers |
| **Inventory-ADUserAttributes.ps1** | Exports comprehensive Active Directory user attributes to CSV reports |
| **Inventory-ADUserLastLogon.ps1** | Retrieves and analyzes Active Directory user last logon timestamps |
| **Inventory-ADUserWithNonExpiringPasswords.ps1** | Identifies user accounts configured with non-expiring passwords |
| **Inventory-InactiveADComputerAccounts.ps1** | Detects stale and inactive Active Directory computer accounts |
| **Invoke-ADComputerGovernanceLifecycle.ps1** | Discovers, classifies, orchestrates and governs inactive AD computer lifecycle states across the enterprise forest |
| **Manage-Disabled-Expired-ADUserAccounts.ps1** | Manages disabled, expired and inactive Active Directory user accounts |
| **Manage-FSMOs-Roles.ps1** | Displays, validates and transfers FSMO role ownership across domain controllers |
| **Manage-SMBShare-And-NTFSPermissions.ps1** | Manages SMB share permissions and audits NTFS access rights for Active Directory groups |
| **Move-ADComputer-betweenOUs.ps1** | Relocates Active Directory computer accounts between organizational units |
| **Move-ADUser-betweenOUs.ps1** | Moves Active Directory user accounts between organizational units with filtering controls |
| **Reset-ADUserPasswordsToDefault.ps1** | Performs bulk password reset operations using standardized secure defaults |
| **Retrieve-ADComputer-SharedFolders.ps1** | Retrieves shared folder configuration data from Active Directory computers |
| **Retrieve-ADDomain-AuditPolicy-Configuration.ps1** | Extracts and reports Active Directory domain audit policy configurations |
| **Retrieve-Elevated-ADForestInfo.ps1** | Retrieves privileged Active Directory forest topology and infrastructure information |
| **Synchronize-n-HealthCheck-ADForestDCs.ps1** | Forces domain controller replication and performs Active Directory forest health validation |
| **Update-ADComputer-Descriptions.ps1** | Updates and standardizes Active Directory computer object descriptions |
| **Update-ADUserDisplayName.ps1** | Applies standardized display name formatting to Active Directory user accounts |

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
