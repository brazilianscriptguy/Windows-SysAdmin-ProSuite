## ⚙️ System Configuration and Deployment Tools

### 📝 Overview

The **System Configuration and Deployment** folder contains a curated set of **PowerShell scripts** for deploying and configuring software, enforcing GPO policies, and applying consistent system settings. These tools are optimized for scalable, secure, and automated management of workstations and servers in Active Directory (AD) environments.

### ✅ Key Features

- **Graphical Interface**: GUI-based scripts simplify use for administrators and support staff  
- **Centralized Logging**: Each execution logs results in structured `.log` files  
- **Streamlined Deployment**: Automates software installs, policy updates, and environment standardization  
- **Policy Compliance**: Removes unauthorized software and enforces configuration baselines

---

## 🛠️ Prerequisites

1. **⚙️ PowerShell**  
   - Requires PowerShell version 5.1 or later  
   - Check version:
     ```powershell
     $PSVersionTable.PSVersion
     ```

2. **🔑 Administrator Privileges**  
   All scripts require elevated permissions to execute configuration and deployment actions

3. **📦 Required Modules**  
   Ensure modules such as `GroupPolicy` and `PSWindowsUpdate` are available

---

## 📜 Script Descriptions (Alphabetical Order)

| **Script Name**                                     | **Function**                                                                   |
|-----------------------------------------------------|---------------------------------------------------------------------------------|
| **Broadcast-ADUser-LogonMessage-viaGPO.ps1**        | Displays custom logon messages via GPO to domain users                         |
| **Cleanup-WebBrowsers-Tool.ps1**                    | Clears browser cache, cookies, and session data                                |
| **Clear-and-ReSyncGPOs-ADComputers.ps1**            | Resets and re-applies GPOs across all domain-joined machines                   |
| **Copy-and-Sync-Folder-to-ADComputers-viaGPO.ps1**  | Synchronizes folders via GPO from a network share                              |
| **Deploy-FortiClientVPN-viaGPO.ps1**                | Installs FortiClient VPN across endpoints via GPO                              |
| **Deploy-FusionInventoryAgent-viaGPO.ps1**          | Deploys FusionInventory Agent for inventory tracking                           |
| **Deploy-GLPI-Agent-viaGPO.ps1**                    | Installs GLPI Agent for asset management                                       |
| **Deploy-JavaJRE-viaGPO.ps1**                       | Installs Java Runtime Environment silently via GPO                             |
| **Deploy-KasperskyAV-viaGPO.ps1**                   | Deploys Kaspersky Endpoint Security via GPO                                    |
| **Deploy-LibreOfficeFullPackage-viaGPO.ps1**        | Installs LibreOffice suite silently on domain machines                         |
| **Deploy-PowerShell-viaGPO.ps1**                    | Ensures PowerShell runtime is correctly installed and updated                  |
| **Deploy-ZoomWorkplace-viaGPO.ps1**                 | Deploys Zoom app via GPO for enterprise communication                          |
| **Enhance-BGInfoDisplay-viaGPO.ps1**                | Applies BGInfo to show system metadata on desktop                              |
| **Install-KMSLicensingServer-Tool.ps1**             | Sets up a KMS server for centralized licensing                                 |
| **Install-RDSLicensingServer-Tool.ps1**             | Configures RDS Licensing Server for CAL management                             |
| **Install-Winget-on-Windows-Servers-viaGPO.ps1**    | Installs `winget` CLI on Windows Server systems                                |
| **Remove-ReaQtaHive-Services-Tool.ps1**             | Removes ReaQta services and related files                                      |
| **Remove-SharedFolders-and-Drives-viaGPO.ps1**      | Deletes non-compliant shares and drives via GPO                                |
| **Remove-Softwares-NonCompliance-Tool.ps1**         | Uninstalls specified non-compliant software from local machine                 |
| **Remove-Softwares-NonCompliance-viaGPO.ps1**       | Automates software removal via GPO                                             |
| **Rename-DiskVolumes-viaGPO.ps1**                   | Applies consistent volume labels across systems                                |
| **Reset-and-Sync-DomainGPOs-viaGPO.ps1**            | Forces reapplication of all domain GPOs                                        |
| **Retrieve-LocalMachine-InstalledSoftwareList.ps1** | Exports a clean list of installed software to `.csv` (ANSI encoded)            |
| **Uninstall-SelectedApp-Tool.ps1**                  | GUI tool for selecting and removing installed applications                     |
| **Update-ADComputer-Winget-Explicit.ps1**           | Updates selected packages via `winget` on local machine                        |
| **Update-ADComputer-Winget-viaGPO.ps1**             | Pushes scheduled `winget` updates via GPO                                      |

---

## 🚀 Usage Instructions

1. **Run the Script**: Right-click on the `.ps1` file and choose _Run with PowerShell_  
2. **Input Parameters**: Follow GUI prompts or set variables in the script  
3. **Check Results**: Logs saved to `C:\Logs-TEMP\` or custom path; `.csv` reports may be generated

---

## 📁 Complementary Files

- **Broadcast-ADUser-LogonMessage-viaGPO.hta**: GUI editor for customizing domain logon messages  
- **Enhance-BGInfoDisplay-viaGPO.bgi**: BGInfo template to overlay system metadata  
- **Remove-Softwares-NonCompliance-Tool.txt**: Config file listing software names to remove

---

## 💡 Optimization Tips

- **Leverage GPO Scheduling**: Use GPO scripts during system startup  
- **Use Task Scheduler**: Automate periodic maintenance tasks  
- **Centralize Logs**: Store logs on a shared path for unified auditing  
- **Parameterize for Reuse**: Adjust arguments and variables for different deployment needs
