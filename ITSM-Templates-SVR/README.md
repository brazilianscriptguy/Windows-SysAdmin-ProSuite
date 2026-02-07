## 🖥️ ITSM-Templates-SVR Suite — Windows Server Management & Compliance

### 📝 Overview

The **ITSM-Templates-SVR** folder provides a suite of **PowerShell** and **VBScript** tools for Windows Server operations. These scripts automate provisioning, enforce IT compliance, and streamline routine administrative tasks in enterprise server environments.

- 🔧 **Server Hardening & Setup:** Automate secure baseline configurations and domain-ready deployments.  
- ⚙️ **Registry & DNS Fixes:** Correct registry entries and enforce DNS re-registration.  
- 📊 **Logging & Reports:** Scripts generate `.log` files and export `.csv` audit reports.  
- 📦 **Reusable Templates:** Easily adaptable for new roles, time sync, and GPO resets.

---

## 🛠️ Prerequisites

1. ⚙️ **PowerShell Version:** PowerShell 5.1 or later  
   ```powershell
   $PSVersionTable.PSVersion
   ```

2. 🔑 **Administrator Privileges:** Required for domain changes, registry editing, and service control.

3. 🖥️ **RSAT Tools:** Remote Server Administration Tools are required  
   ```powershell
   Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online
   ```

4. 🔧 **Execution Policy:**  
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope Process
   ```

5. 📦 **Dependencies:** Ensure modules such as `ActiveDirectory` and `DHCPServer` are installed.

---

## 📄 Script Descriptions (Alphabetical Order)

| Script Name | Description |
|-------------|-------------|
| **CheckServerRoles.ps1** | Lists installed roles/features for validation. |
| **ExportServerConfig.ps1** | Exports server config to `.csv` for documentation. |
| **FixNTFSPermissions.ps1** | Repairs NTFS permission inconsistencies. |
| **InventoryServerSoftware.ps1** | Generates inventory of installed software. |
| **ITSM-DefaultServerConfig.ps1** | Applies secure standard configs (e.g., NTP, firewall). |
| **ITSM-DNSRegistration.ps1** | Forces DNS re-registration for AD. |
| **ITSM-HardenServer.ps1** | Hardens server post-domain join (SMBv1, local accounts, lockout). |
| **ITSM-ModifyServerRegistry.ps1** | Adjusts registry for compliance/security. |
| **ResetGPOSettings.ps1** | Restores default GPO-controlled settings. |
| **ServerTimeSync.ps1** | Syncs server time with DCs to prevent replication/auth issues. |

---

## 🚀 Getting Started

```bash
git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
```

1. **Navigate to:**  
   `Windows-SysAdmin-ProSuite/ITSM-Templates-SVR/`

2. **Read the Docs:**  
   Each script has usage notes in comments or a `README.md`.

3. **Run the Script:**  
   ```powershell
   .\ScriptName.ps1
   ```

4. **Review Logs and Reports:**  
   Output files include `.log` and `.csv` formats for auditing and tracking.

---

## 📝 Logging and Output

- 📄 **Logs:**  
  Each script outputs structured `.log` files for traceability and troubleshooting.

- 📊 **Reports:**  
  Configuration states and inventories are exported to `.csv`.

---

## 💡 Optimization Tips

- ⏱️ **Automate with Task Scheduler:** Schedule script execution to enforce drift remediation.  
- 🗂️ **Centralize Output:** Redirect logs and `.csv` reports to shared storage for compliance auditing.  
- 🧩 **Customize Templates:** Modify hardening profiles per role (e.g., file server, domain controller).

---

## ❓ Additional Assistance

These scripts are highly adaptable for custom infrastructures. Check embedded script headers and comments for configurable variables and behavior explanations.

---

## 📂 Document Classification

**RESTRICTED:** For internal use within the organization's network only.

© 2026 Luiz Hamilton Silva. All rights reserved.
