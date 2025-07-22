# ⚙️ GroupPolicyObjects-Templates

## 📝 Overview

The **GroupPolicyObjects-Templates** folder provides a robust collection of reusable **GPO templates** designed to streamline administrative tasks across **Windows Server Forest and Domain** environments.  
These templates focus on security, performance, user experience, and compliance, offering out-of-the-box configurations for both workstation and server infrastructure.

### 🔑 Key Features

- **Preconfigured GPOs:** Ready-to-import templates for typical enterprise scenarios.
- **Cross-Domain Compatibility:** Applicable to both domain-level and forest-wide deployments.
- **Script-Driven Automation:** Integrated with import/export tools and log generation.
- **Security and Compliance:** Templates implement best practices for account policies, firewall, RDS, and more.

---

## 🛠️ Prerequisites

1. **🖥️ Domain or Forest Controller**  
   Ensure you have a properly configured Windows Server with Domain Controller or Global Catalog role.

2. **📦 Import Script**  
   Use the following script to import/export GPOs:  
   ```powershell
   SysAdmin-Tools\ActiveDirectory-Management\Export-n-Import-GPOsTool.ps1
   ```

3. **📂 Deployment Path**  
   Templates are deployed to:  
   ```
   \\your-forest-domain\SYSVOL\your-domain\Policies\
   ```

4. **📝 Log Output**  
   Logs are saved to:  
   ```
   C:\Logs-TEMP\
   ```

---

## 📄 Template Descriptions (Alphabetical Order)

| **Template Name**                            | **Description**                                                                 |
|---------------------------------------------|-----------------------------------------------------------------------------|
| **admin-entire-Forest-LEVEL3**              | Elevated GPO for Forest-level administrative access (ITSM Level 3).        |
| **admin-local-Workstations-LEVEL1-2**       | Grants local admin rights for support staff (Level 1 and 2).              |
| **deploy-printer-template**                 | Deploys preconfigured printers to user workstations via GPO.              |
| **disable-firewall-domain-workstations**    | Disables built-in Windows Firewall for managed domains.                   |
| **enable-audit-logs-DC-servers**            | Enables auditing on Domain Controllers.                                   |
| **enable-audit-logs-FILE-servers**          | Activates audit logs on file servers.                                     |
| **enable-biometrics-logon**                 | Enables fingerprint or facial recognition.                                |
| **enable-ldap-bind-servers**                | Configures secure LDAP binding policies.                                  |
| **enable-licensing-RDS**                    | Sets up Remote Desktop licensing.                                          |
| **enable-logon-message-workstations**       | Displays disclaimer or welcome message at logon.                          |
| **enable-network-discovery**                | Enables Network Discovery for trusted networks.                           |
| **enable-RDP-configs-users-RPC-gpos**       | Applies RDP settings for specific users or OUs.                           |
| **enable-WDS-ports**                        | Opens required ports for WDS.                                             |
| **enable-WinRM-service**                    | Enables WinRM for remote management.                                      |
| **enable-zabbix-ports-servers**             | Allows Zabbix monitoring communication.                                   |
| **install-certificates-forest**            | Deploys SSL/internal PKI certificates to domain members.                  |
| **install-cmdb-fusioninventory-agent**      | Installs FusionInventory agents.                                          |
| **install-forticlient-vpn**                 | Distributes FortiClient VPN client.                                       |
| **install-kasperskyfull-workstations**      | Installs Kaspersky on workstations.                                       |
| **install-powershell7**                     | Deploys PowerShell 7 to client machines.                                  |
| **install-update-winget-apps**              | Schedules software updates using Winget.                                  |
| **install-zoom-workplace-32bits**           | Installs 32-bit Zoom client.                                              |
| **itsm-disable-monitor-after-06hours**      | Turns off inactive displays after 6 hours.                                |
| **itsm-template-ALL-servers**               | Base template for all servers.                                            |
| **itsm-template-ALL-workstations**          | Standard configuration for workstations.                                  |
| **itsm-VMs-dont-shutdown**                  | Prevents VM shutdown on idle.                                             |
| **mapping-storage-template**                | Applies mapped network drives.                                            |
| **password-policy-all-domain-users**        | Enforces password policy domain-wide.                                     |
| **password-policy-all-servers-machines**    | Sets stricter password rules for servers.                                 |
| **password-policy-only-IT-TEAM-users**      | Custom password settings for IT team.                                     |
| **purge-expired-certificates**              | Removes expired certificates via task.                                    |
| **remove-shared-local-folders-workstations**| Removes unauthorized shared folders.                                      |
| **remove-softwares-non-compliance**         | Uninstalls flagged software.                                              |
| **rename-disks-volumes-workstations**       | Enforces disk volume naming (e.g., “OS”, “DATA”).                         |
| **wsus-update-servers-template**            | WSUS update settings for servers.                                         |
| **wsus-update-workstation-template**        | WSUS update policies for workstations.                                    |

---

## 🚀 Usage Instructions

1. **Run Import Tool:**  
   Launch `Export-n-Import-GPOsTool.ps1` with elevated PowerShell.

2. **Select Mode:**  
   Choose *Import Templates* option in the tool interface.

3. **Confirm Import:**  
   Review CLI or GUI feedback to verify success.

4. **Validate Results:**  
   Inspect `C:\Logs-TEMP\` for log output and status codes.

---

## 📝 Logging and Reports

- **📄 Logs:** Stored as `.log` files in `C:\Logs-TEMP\`
- **📊 Reports:** Exported as `.csv` for audits and tracking

---

## 💡 Optimization Tips

- **Schedule Policy Reviews:** Regularly validate GPO application across OUs.
- **Version Control:** Use Git to back up exported GPOs.
- **Tag Critical GPOs:** Apply naming tags like `[SEC]`, `[CORE]`, or `[AUDIT]` to improve traceability.

