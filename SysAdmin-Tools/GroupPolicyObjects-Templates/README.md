## ⚙️ GroupPolicyObjects-Templates  
### GPO Automation · Security Baselines · Domain & Forest Governance

![Suite](https://img.shields.io/badge/Suite-GPO%20Templates-0A66C2?style=for-the-badge&logo=windows&logoColor=white)
![Scope](https://img.shields.io/badge/Scope-Domain%20%7C%20Forest-informational?style=for-the-badge)
![Focus](https://img.shields.io/badge/Focus-Security%20%7C%20Compliance-critical?style=for-the-badge)
![Automation](https://img.shields.io/badge/Automation-GPO%20%7C%20PowerShell-success?style=for-the-badge)

---

## 🧭 Overview

The **GroupPolicyObjects-Templates** suite provides a comprehensive collection of **reusable Group Policy Object (GPO) templates** designed to standardize administration across **Windows Server domain and forest environments**.

These templates address **security hardening**, **operational consistency**, **performance optimization**, and **ITSM compliance**, delivering ready-to-import configurations for both **workstations** and **servers**.

All templates are designed to integrate seamlessly with automated import/export tooling and structured logging workflows.

---

## 🌟 Key Features

- 🧩 **Preconfigured GPOs** — Ready-to-import templates for common enterprise scenarios  
- 🌐 **Cross-Scope Compatibility** — Applicable at domain or forest level  
- ⚙️ **Script-Driven Automation** — Integrated with PowerShell import/export tools  
- 🔐 **Security & Compliance** — Implements best practices for authentication, auditing, RDS, firewall, and more  

---

## 🛠️ Prerequisites

- **🖥️ Domain or Forest Controller**  
  A properly configured Windows Server acting as a **Domain Controller** or **Global Catalog**

- **📦 Import / Export Tool**  
  Use the following PowerShell tool to manage GPO templates:  
  ```powershell
  SysAdmin-Tools\ActiveDirectory-Management\Export-n-Import-GPOsTool.ps1
  ```

- **📂 Deployment Path**  
  GPOs are imported into:  
  ```text
  \\your-forest-domain\SYSVOL\your-domain\Policies\
  ```

- **📝 Logging Path**  
  Execution logs are stored in:  
  ```text
  C:\Logs-TEMP\
  ```

---

## 📄 Template Catalog (Alphabetical)

| Template Name | Description |
|--------------|-------------|
| **admin-entire-Forest-LEVEL3** | Forest-level administrative access (ITSM Level 3) |
| **admin-local-Workstations-LEVEL1-2** | Local admin rights for Level 1 and 2 support |
| **deploy-printer-template** | Printer deployment via GPO |
| **disable-firewall-domain-workstations** | Disables Windows Firewall on managed workstations |
| **enable-audit-logs-DC-servers** | Enables auditing on Domain Controllers |
| **enable-audit-logs-FILE-servers** | Enables auditing on file servers |
| **enable-biometrics-logon** | Enables biometric authentication |
| **enable-ldap-bind-servers** | Configures secure LDAP binding |
| **enable-licensing-RDS** | Configures Remote Desktop licensing |
| **enable-logon-message-workstations** | Displays logon disclaimer or banner |
| **enable-network-discovery** | Enables network discovery on trusted networks |
| **enable-RDP-configs-users-RPC-gpos** | Applies RDP settings for specific users or OUs |
| **enable-WDS-ports** | Opens required ports for Windows Deployment Services |
| **enable-WinRM-service** | Enables WinRM for remote administration |
| **enable-zabbix-ports-servers** | Allows Zabbix monitoring traffic |
| **install-certificates-forest** | Deploys internal PKI certificates |
| **install-cmdb-fusioninventory-agent** | Installs FusionInventory agents |
| **install-forticlient-vpn** | Deploys FortiClient VPN |
| **install-kasperskyfull-workstations** | Deploys Kaspersky on workstations |
| **install-powershell7** | Installs PowerShell 7 |
| **install-update-winget-apps** | Schedules software updates via Winget |
| **install-zoom-workplace-32bits** | Installs Zoom (32-bit) |
| **itsm-disable-monitor-after-06hours** | Turns off inactive displays after 6 hours |
| **itsm-template-ALL-servers** | Baseline configuration for all servers |
| **itsm-template-ALL-workstations** | Baseline configuration for all workstations |
| **itsm-VMs-dont-shutdown** | Prevents idle VM shutdown |
| **mapping-storage-template** | Applies mapped network drives |
| **password-policy-all-domain-users** | Enforces password policy for all users |
| **password-policy-all-servers-machines** | Stronger password policy for servers |
| **password-policy-only-IT-TEAM-users** | Custom password policy for IT staff |
| **purge-expired-certificates** | Removes expired certificates |
| **remove-shared-local-folders-workstations** | Removes unauthorized local shares |
| **remove-softwares-non-compliance** | Uninstalls non-compliant software |
| **rename-disks-volumes-workstations** | Enforces disk volume naming standards |
| **wsus-update-servers-template** | WSUS configuration for servers |
| **wsus-update-workstation-template** | WSUS configuration for workstations |

---

## 🚀 Usage Instructions

1. Launch **Export-n-Import-GPOsTool.ps1** with elevated PowerShell  
2. Select **Import Templates** mode  
3. Confirm import status via GUI or console feedback  
4. Review logs in `C:\Logs-TEMP\`  

---

## 📝 Logging & Reporting

| Path                       | Purpose                                                                |
| -------------------------- | ---------------------------------------------------------------------- |
| `C:\Scripts-LOGS\`         | GPO synchronization, agents, and security tooling logs                 |
| `C:\Logs-TEMP\`            | General-purpose, transient, and legacy script outputs                  |
| `%USERPROFILE%\Documents\` | CSV and exported reports for compliance, forensics, and ITSM workflows |

---

## 💡 Optimization Tips

- 🔁 Schedule periodic GPO validation across OUs  
- 🗂️ Version-control exported GPO backups using Git  
- 🏷️ Tag critical GPOs with prefixes such as `[SEC]`, `[CORE]`, or `[AUDIT]`  

---

© 2026 Luiz Hamilton Silva. All rights reserved.
