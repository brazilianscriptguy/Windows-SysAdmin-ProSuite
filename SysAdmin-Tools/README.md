## 🔧 SysAdmin-Tools Suite

Welcome to the **SysAdmin-Tools** suite — a powerful collection of **PowerShell automation scripts** crafted to streamline and centralize the management of Active Directory (AD), Windows Server roles, network infrastructure, and workstation configurations. These tools simplify complex administrative tasks, improve operational efficiency, and enforce compliance and security across enterprise IT environments.

---

## 🌟 Key Features

- 🖼️ **User-Friendly Interfaces:** All scripts include GUI-driven usability.  
- 📝 **Detailed Logging:** Each run produces structured `.log` files for diagnostics.  
- 📊 **Exportable Reports:** Most tools output `.csv` for auditing and data analysis.

---

## 📁 Folder Structure and Categories

| Folder | Description | Documentation |
|--------|-------------|----------------|
| **ActiveDirectory-Management** | Tools to manage users, computers, GPOs, and sync in AD. | [![AD Management](https://img.shields.io/badge/AD%20Management-README-blue?style=for-the-badge&logo=github)](ActiveDirectory-Management/README.md) |
| **ActiveDirectory-SSO-Integrations** | SSO integration models via LDAP for AD. | [![SSO Integrations](https://img.shields.io/badge/SSO%20Integrations-README-blue?style=for-the-badge&logo=github)](ActiveDirectory-SSO-Integrations/README.md) |
| **GroupPolicyObjects-Templates** | Ready-to-import GPO templates. | [![GPO Templates](https://img.shields.io/badge/GPO%20Templates-README-blue?style=for-the-badge&logo=github)](GroupPolicyObjects-Templates/README.md) |
| **Network-and-Infrastructure-Management** | DNS, DHCP, WSUS tools and health checks. | [![Network Management](https://img.shields.io/badge/Network%20Management-README-blue?style=for-the-badge&logo=github)](Network-and-Infrastructure-Management/README.md) |
| **Security-and-Process-Optimization** | Tools for security hardening and compliance. | [![Security Optimization](https://img.shields.io/badge/Security%20Optimization-README-blue?style=for-the-badge&logo=github)](Security-and-Process-Optimization/README.md) |
| **SystemConfiguration-and-Deployment** | Ensures system consistency across deployments. | [![System Deployment](https://img.shields.io/badge/System%20Deployment-README-blue?style=for-the-badge&logo=github)](SystemConfiguration-and-Deployment/README.md) |
| **WSUS-Management-Tools** | Tools for WSUS cleanup, reporting, and optimization. | [![WSUS Tools](https://img.shields.io/badge/WSUS%20Tools-README-blue?style=for-the-badge&logo=github)](WSUS-Management-Tools/README.md) |

---

## 🛠️ Prerequisites

1. 🖥️ **RSAT Tools:**  
   Required to manage AD, DNS, DHCP, etc.  
   ```powershell
   Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online
   ```

2. ⚙️ **PowerShell Version:**  
   PowerShell 5.1 or later  
   ```powershell
   $PSVersionTable.PSVersion
   ```

3. 🔑 **Administrator Privileges:**  
   Required for elevated system changes.

4. 🔧 **Execution Policy:**  
   Enable script execution locally  
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
   ```

5. 📦 **Dependencies:**  
   Modules like `ActiveDirectory` and `DHCPServer` must be present.

---

## 🚀 Getting Started

```bash
git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
```

1. **Navigate to:**  
   `Windows-SysAdmin-ProSuite/SysAdmin-Tools/`

2. **Review Documentation:**  
   Each folder contains a `README.md` with usage guidance.

3. **Run the Script:**  
   ```powershell
   .\ScriptName.ps1
   ```

4. **Review Logs and Reports:**  
   - General logs → `C:\Logs-TEMP\` or script directory  
   - ITSM logs → `C:\ITSM-Logs-WKS\` or `C:\ITSM-Logs-SVR\`  
   - Outputs: `.log` for diagnostics, `.csv` for reports

---

## 📝 Logging and Reporting

- 📄 **Logs:**  
  All scripts generate `.log` files for auditing and debugging.

- 📊 **Reports:**  
  Many scripts export `.csv` reports for compliance and analysis.

---

## ❓ Support & Customization

All scripts are modular and can be adapted to your IT architecture. For help or feedback, consult each folder’s `README.md` or use the contact links below:

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com)
[![Patreon](https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge&logo=patreon)](https://www.patreon.com/brazilianscriptguy)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20Me-blue?style=for-the-badge&logo=kofi)](https://ko-fi.com/brazilianscriptguy)
[![GoFundMe](https://img.shields.io/badge/GoFundMe-Donate-green?style=for-the-badge&logo=gofundme)](https://gofund.me/4599d3e6)
[![WhatsApp](https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp)](https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c)
[![GitHub Issues](https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/ISSUE_TEMPLATE/CUSTOM_ISSUE_TEMPLATE.md)

---

© 2025 Luiz Hamilton. All rights reserved.
