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
|-------------|-------------|
| **Add-ADComputers-Pre-Staging.ps1** | Pre-stages Active Directory computer accounts in designated OUs, supporting controlled domain joins and delegated permissions. |
| **Add-ADInetOrgPerson.ps1** | Creates Active Directory `inetOrgPerson` objects with extended enterprise attributes. |
| **Add-ADUserAccount.ps1** | Provides GUI-based Active Directory user account provisioning within designated OUs. |
| **Adjust-ExpirationDate-ADUserAccount.ps1** | Configures and updates Active Directory user account expiration dates. |
| **Check-Shorter-ADComputerNames.ps1** | Identifies computer names that violate established naming conventions or length requirements. |
| **Cleanup-InactiveADComputersAccounts.ps1** | Identifies and removes eligible inactive Active Directory workstation accounts using controlled DRY-RUN and COMMIT modes. |
| **Cleanup-MetaData-ADForest-Tool.ps1** | Removes orphaned Active Directory metadata and supports forest consistency remediation. |
| **Create-OUsDefaultADStructure.ps1** | Creates standardized Organizational Unit (OU) hierarchies across Active Directory domains. |
| **Enforce-Expiration-ADUserPasswords.ps1** | Applies password expiration governance controls to Active Directory user accounts. |
| **Export-n-Import-GPOsTool.ps1** | Provides GUI-based backup, export, and import operations for Group Policy Objects (GPOs). |
| **Fix-ADForest-DNSDelegation.ps1** | Detects and repairs DNS delegation inconsistencies across Active Directory forest domains. |
| **Inventory-ADComputers-by-Domain.ps1** | Discovers and inventories Active Directory computers across all forest domains, providing detailed account, operating system, OU, DNS, and connectivity information. |
| **Inventory-ADComputers-Collector.ps1** | Collects live hardware, operating system, logged-on user, BIOS, and network configuration details from remote Windows computers using CIM/WMI. |
| **Inventory-ADGroups-their-Members.ps1** | Enumerates Active Directory security and distribution groups and their associated memberships. |
| **Inventory-ADMemberServers.ps1** | Collects inventory and operational information from Active Directory member servers. |
| **Inventory-ADUserAttributes.ps1** | Exports comprehensive Active Directory user account attributes to CSV reports. |
| **Inventory-ADUserLastLogon.ps1** | Retrieves and analyzes Active Directory user logon timestamps. |
| **Inventory-ADUserWithNonExpiringPasswords.ps1** | Identifies Active Directory user accounts configured with non-expiring passwords. |
| **Inventory-InactiveADComputerAccounts.ps1** | Detects and reports stale or inactive Active Directory computer accounts. |
| **Manage-Disabled-Expired-ADUserAccounts.ps1** | Audits and manages disabled, expired, and inactive Active Directory user accounts. |
| **Manage-FSMOs-Roles.ps1** | Displays, validates, and transfers Flexible Single Master Operations (FSMO) roles across domain controllers. |
| **Manage-SMBShare-And-NTFSPermissions.ps1** | Manages SMB share permissions and audits NTFS access control entries. |
| **Move-ADComputer-betweenOUs.ps1** | Moves Active Directory computer accounts between Organizational Units (OUs). |
| **Move-ADUser-betweenOUs.ps1** | Moves Active Directory user accounts between Organizational Units (OUs) with filtering controls. |
| **Reset-ADUserPasswordsToDefault.ps1** | Performs controlled bulk password resets using standardized initial credentials. |
| **Retrieve-ADComputer-SharedFolders.ps1** | Retrieves and reports shared folder configurations from Active Directory computers. |
| **Retrieve-ADDomain-AuditPolicy-Configuration.ps1** | Collects and reports Active Directory domain audit policy configurations. |
| **Retrieve-Elevated-ADForestInfo.ps1** | Retrieves detailed Active Directory forest topology, privileged configuration, and infrastructure information. |
| **Synchronize-n-HealthCheck-ADForestDCs.ps1** | Initiates domain controller replication and validates Active Directory forest health. |
| **Update-ADComputer-Descriptions.ps1** | Updates and standardizes Active Directory computer object descriptions. |
| **Update-ADUserDisplayName.ps1** | Standardizes Active Directory user account display names. |
| **Update-ADUserLoginIdentity.ps1** | Updates and aligns `sAMAccountName` and `userPrincipalName` using an external identity mapping file. |

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
