## 🛠️ Active Directory Management Tools

### 📝 Overview

The **Active Directory Management** suite contains advanced PowerShell scripts for automating key tasks related to **Active Directory (AD)**. These tools streamline domain operations like user/computer account creation, OU organization, policy enforcement, and auditing.

#### 🔑 Key Features

- **Graphical Interfaces** — Several tools include GUIs to simplify user interaction and configuration  
- **Comprehensive Logging** — All scripts generate structured `.log` files for traceability and diagnostics  
- **Exportable Reports** — Many tools export `.csv` files for documentation and compliance  
- **Efficient AD Automation** — Eliminates repetitive manual operations across domains

---

### 🛠️ Prerequisites

1. ⚙️ **PowerShell 5.1 or later**  
   Check version:  
   ```powershell
   $PSVersionTable.PSVersion
   ```

2. 📦 **Active Directory Module**  
   Import it where needed:  
   ```powershell
   Import-Module ActiveDirectory
   ```

3. 🔑 **Administrator Privileges**  
   Required to modify AD objects and apply changes

4. 🖥️ **RSAT (Remote Server Administration Tools)**  
   Must be installed and configured

5. 🔧 **Execution Policy**  
   Temporarily allow local scripts:  
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
   ```

---

### 📄 Script Descriptions (Alphabetical)

| Script Name | Description |
|-------------|-------------|
| **Add-ADComputers-GrantPermissions.ps1** | Adds AD computers to OUs and grants domain join permissions |
| **Add-ADInetOrgPerson.ps1** | Creates `InetOrgPerson` objects with detailed attributes |
| **Add-ADUserAccount.ps1** | GUI-based AD user creation in specific OUs |
| **Adjust-ExpirationDate-ADUserAccount.ps1** | Updates expiration dates for AD user accounts |
| **Check-Shorter-ADComputerNames.ps1** | Flags computer accounts with short/non-compliant names |
| **Cleanup-Inactive-ADComputerAccounts.ps1** | Deletes stale computer objects from AD |
| **Cleanup-MetaData-ADForest-Tool.ps1** | Cleans orphaned metadata and synchronizes AD forest |
| **Create-OUsDefaultADStructure.ps1** | Builds standard OU layout for a new or existing domain |
| **Enforce-Expiration-ADUserPasswords.ps1** | Enables expiration policy for user passwords |
| **Export-n-Import-GPOsTool.ps1** | GUI tool for GPO import/export |
| **Fix-ADForest-DNSDelegation.ps1** | Resolves DNS delegation problems in the forest |
| **Inventory-ADComputers-and-OUs.ps1** | GUI tool to export computers and OU structure |
| **Inventory-ADDomainComputers.ps1** | Exports a flat list of domain-joined computers |
| **Inventory-ADGroups-their-Members.ps1** | Lists all AD groups and their members |
| **Inventory-ADMemberServers.ps1** | Gathers info on all member servers in the domain |
| **Inventory-ADUserAttributes.ps1** | Exports all attributes for users into CSV |
| **Inventory-ADUserLastLogon.ps1** | Tracks user logon times |
| **Inventory-ADUserWithNonExpiringPasswords.ps1** | Detects accounts without password expiration |
| **Inventory-InactiveADComputerAccounts.ps1** | Finds unused computer accounts |
| **Manage-Disabled-Expired-ADUserAccounts.ps1** | Disables expired user accounts |
| **Manage-FSMOs-Roles.ps1** | View or transfer FSMO roles |
| **Move-ADComputer-betweenOUs.ps1** | Moves computers across OUs based on logic |
| **Move-ADUser-betweenOUs.ps1** | Moves users to other OUs with filtering |
| **Reset-ADUserPasswordsToDefault.ps1** | Resets passwords in bulk to a secure default |
| **Retrieve-ADComputer-SharedFolders.ps1** | Gets shared folders from AD computers |
| **Retrieve-ADDomain-AuditPolicy-Configuration.ps1** | Extracts current domain audit settings |
| **Retrieve-Elevated-ADForestInfo.ps1** | Lists admin groups, roles, and critical forest info |
| **Synchronize-ADForestDCs.ps1** | Triggers replication across domain controllers |
| **Unlock-SMBShareADUserAccess.ps1** | Restores SMB share access for users |
| **Update-ADComputer-Descriptions.ps1** | Populates description fields with asset details |
| **Update-ADUserDisplayName.ps1** | Applies naming format to user display names |

---

### 🚀 Usage Instructions

1. **Run the Script**  
   Use context menu → *Run with PowerShell* or launch in elevated console

2. **Provide Inputs**  
   Enter required data or interact via GUI (varies by script)

3. **Review Outputs**  
   Logs and `.csv` files will be saved in:
   - Working folder  
   - Or: `C:\Logs-TEMP\`

---

### 📄 Complementary Files

- `GPO-Template-Backup.zip` — Sample GPO export archive  
- `Default-AD-OUs.csv` — Reference list of default OUs used in provisioning  
- `Password-Reset-Log.log` — Example log for password reset operations

---

### 💡 Optimization Tips

- **Automate Execution** — Use Windows Task Scheduler or GPO to run scripts regularly  
- **Centralize Logs** — Forward logs to shared path or SIEM agent  
- **Domain Customization** — Edit OU paths, naming logic, and group policies to reflect enterprise structure
