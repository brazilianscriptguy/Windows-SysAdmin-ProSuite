## 🔧 SysAdmin-Tools Suite

Welcome to the **SysAdmin-Tools** suite—a curated collection of **PowerShell automation scripts** designed to streamline and centralize administration across **Active Directory (AD)**, **Windows Server roles**, **network infrastructure**, and **workstation configuration**. These tools help reduce manual effort, standardize operations, improve visibility, and support security and compliance in enterprise environments.

---

## 🌟 Key Features

- 🖼️ **GUI-first experience:** Most scripts provide a guided, user-friendly interface  
- 📝 **Structured logging:** Each run generates `.log` files to support troubleshooting and audits  
- 📊 **Export-ready reporting:** Many tools export `.csv` output for review, compliance, and analysis

---

## 📁 Folder Structure

| Folder | What it covers | Documentation |
|--------|-----------------|---------------|
| **ActiveDirectory-Management** | Manage users, computers, GPOs, and AD sync workflows | [![AD Management](https://img.shields.io/badge/AD%20Management-README-blue?style=for-the-badge&logo=github)](ActiveDirectory-Management/README.md) |
| **ActiveDirectory-SSO-Integrations** | LDAP-based SSO integration patterns for AD | [![SSO Integrations](https://img.shields.io/badge/SSO%20Integrations-README-blue?style=for-the-badge&logo=github)](ActiveDirectory-SSO-Integrations/README.md) |
| **GroupPolicyObjects-Templates** | Ready-to-import Group Policy (GPO) templates | [![GPO Templates](https://img.shields.io/badge/GPO%20Templates-README-blue?style=for-the-badge&logo=github)](GroupPolicyObjects-Templates/README.md) |
| **Network-and-Infrastructure-Management** | DNS/DHCP/WSUS utilities, checks, and operational tooling | [![Network Management](https://img.shields.io/badge/Network%20Management-README-blue?style=for-the-badge&logo=github)](Network-and-Infrastructure-Management/README.md) |
| **Security-and-Process-Optimization** | Security hardening, governance, and compliance-focused tools | [![Security Optimization](https://img.shields.io/badge/Security%20Optimization-README-blue?style=for-the-badge&logo=github)](Security-and-Process-Optimization/README.md) |
| **SystemConfiguration-and-Deployment** | Baselines and configuration consistency across deployments | [![System Deployment](https://img.shields.io/badge/System%20Deployment-README-blue?style=for-the-badge&logo=github)](SystemConfiguration-and-Deployment/README.md) |
| **WSUS-Management-Tools** | WSUS cleanup, reporting, maintenance, and optimization | [![WSUS Tools](https://img.shields.io/badge/WSUS%20Tools-README-blue?style=for-the-badge&logo=github)](WSUS-Management-Tools/README.md) |

---

## 🛠️ Prerequisites

1. **🖥️ RSAT (Remote Server Administration Tools)**  
   Required for AD/DNS/DHCP and related administration
   ```powershell
   Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online
   ```

2. **⚙️ PowerShell Version**  
   Recommended: **PowerShell 7.0+** (many scripts remain compatible with **Windows PowerShell 5.1**)
   ```powershell
   $PSVersionTable.PSVersion
   ```

3. **🔑 Administrator Privileges**  
   Some actions require elevated permissions to apply system-level changes

4. **🔧 Execution Policy (local session)**  
   Enables script execution for the current PowerShell process
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
   ```

5. **📦 Dependencies / Modules**  
   Ensure required modules are available (for example: `ActiveDirectory`, `DhcpServer`, etc.)

---

## 🚀 Getting Started

Clone the repository:

```bash
git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
```

Then:

1. **Navigate to**  
   `Windows-SysAdmin-ProSuite/SysAdmin-Tools/`

2. **Read the documentation**  
   Each folder includes a `README.md` with usage details and examples

3. **Run a script**
   ```powershell
   .\ScriptName.ps1
   ```

4. **Review logs and reports**
   - General logs: `C:\Logs-TEMP\` (or the script directory, depending on the tool)
   - ITSM logs: `C:\ITSM-Logs-WKS\` or `C:\ITSM-Logs-SVR\`
   - Outputs: `.log` (diagnostics/audit) and `.csv` (reporting)

---

## 📝 Logging and Reporting

- **📄 Logs**  
  Scripts generate `.log` files to support troubleshooting, auditing, and traceability

- **📊 Reports**  
  Many tools export `.csv` reports for compliance, review, and analysis

---

## ❓ Support & Customization

Scripts are modular and intended to be adaptable to your environment. For help or feedback, refer to the `README.md` in each folder or use the links below:

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr%40gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com)
[![Patreon](https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge&logo=patreon)](https://www.patreon.com/brazilianscriptguy)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20Me-blue?style=for-the-badge&logo=kofi)](https://ko-fi.com/brazilianscriptguy)
[![GoFundMe](https://img.shields.io/badge/GoFundMe-Donate-green?style=for-the-badge&logo=gofundme)](https://gofund.me/4599d3e6)
[![WhatsApp](https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp)](https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c)
[![GitHub Issues](https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/ISSUE_TEMPLATE/CUSTOM_ISSUE_TEMPLATE.md)

---

© 2026 Luiz Hamilton. All rights reserved.
