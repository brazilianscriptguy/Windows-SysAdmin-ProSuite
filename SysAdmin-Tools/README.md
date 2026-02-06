## 🔧 SysAdmin-Tools Suite  
### Windows Administration · Active Directory · Infrastructure Automation

![Suite](https://img.shields.io/badge/Suite-SysAdmin%20Tools-0A66C2?style=for-the-badge&logo=windows&logoColor=white) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207.x-5391FE?style=for-the-badge&logo=powershell&logoColor=white) ![Scope](https://img.shields.io/badge/Scope-AD%20%7C%20Servers%20%7C%20Network-informational?style=for-the-badge) ![Focus](https://img.shields.io/badge/Focus-Automation%20%7C%20Compliance-critical?style=for-the-badge)

---

## 🧭 Overview

Welcome to the **SysAdmin-Tools Suite** — a curated collection of **PowerShell automation tools** designed to centralize and standardize administration across:

- **Active Directory (AD)**
- **Windows Server roles**
- **Network and infrastructure services**
- **Workstation and server configuration baselines**

These tools are engineered to **reduce manual effort**, **improve operational visibility**, and **support security, governance, and compliance** in enterprise and public-sector environments.

---

## 🌟 Key Features

- 🖼️ **GUI-first experience** — Guided, user-friendly interfaces for daily operations  
- 📝 **Structured logging** — Each execution generates `.log` files for auditing and troubleshooting  
- 📊 **Export-ready reporting** — Many tools produce `.csv` outputs for compliance and analysis  

---

## 📁 Folder Structure

| Folder | Coverage | Documentation |
|------|----------|---------------|
| **ActiveDirectory-Management** | User, computer, group, OU, and GPO operations | [![Docs](https://img.shields.io/badge/Docs-AD%20Management-0A66C2?style=for-the-badge&logo=github)](ActiveDirectory-Management/README.md) |
| **ActiveDirectory-SSO-Integrations** | LDAP and SSO integration patterns | [![Docs](https://img.shields.io/badge/Docs-SSO%20Integrations-0A66C2?style=for-the-badge&logo=github)](ActiveDirectory-SSO-Integrations/README.md) |
| **GroupPolicyObjects-Templates** | Ready-to-import GPO templates | [![Docs](https://img.shields.io/badge/Docs-GPO%20Templates-0A66C2?style=for-the-badge&logo=github)](GroupPolicyObjects-Templates/README.md) |
| **Network-and-Infrastructure-Management** | DNS, DHCP, WSUS, and infrastructure utilities | [![Docs](https://img.shields.io/badge/Docs-Network%20Management-0A66C2?style=for-the-badge&logo=github)](Network-and-Infrastructure-Management/README.md) |
| **Security-and-Process-Optimization** | Security hardening and governance tooling | [![Docs](https://img.shields.io/badge/Docs-Security%20Optimization-0A66C2?style=for-the-badge&logo=github)](Security-and-Process-Optimization/README.md) |
| **SystemConfiguration-and-Deployment** | System baselines and deployment consistency | [![Docs](https://img.shields.io/badge/Docs-System%20Deployment-0A66C2?style=for-the-badge&logo=github)](SystemConfiguration-and-Deployment/README.md) |
| **WSUS-Management-Tools** | WSUS maintenance, cleanup, and reporting | [![Docs](https://img.shields.io/badge/Docs-WSUS%20Tools-0A66C2?style=for-the-badge&logo=github)](WSUS-Management-Tools/README.md) |

---

## 🛠️ Prerequisites

- **🖥️ RSAT Tools** — Required for AD, DNS, and DHCP administration  
  ```powershell
  Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online
  ```

- **⚙️ PowerShell** — Version **5.1 or later** (PowerShell 7.x supported)  
  ```powershell
  $PSVersionTable.PSVersion
  ```

- **🔑 Administrative Privileges** — Required for system-level operations  

- **🔧 Execution Policy** — Session-scoped execution  
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
  ```

- **📦 Modules** — Ensure availability of modules such as `ActiveDirectory`, `DhcpServer`, `DnsServer`, etc.

---

## 🚀 Getting Started

```bash
git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
```

1. Navigate to:  
   `Windows-SysAdmin-ProSuite/SysAdmin-Tools/`

2. Review the local `README.md` inside each folder  

3. Execute a script:  
   ```powershell
   .\ScriptName.ps1
   ```

4. Review outputs:
   - Logs: `C:\Logs-TEMP\`, `C:\ITSM-Logs-WKS\`, or `C:\ITSM-Logs-SVR\`
   - Reports: `.csv` files generated per tool

---

## 📝 Logging & Reporting

- **Logs** — `.log` files provide full execution traceability  
- **Reports** — `.csv` exports support compliance reviews and audits  

---

## ❓ Support & Customization

All scripts are modular and designed for adaptation to institutional policies.  
Refer to the documentation within each folder or reach out via the channels below:

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr%40gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com) [![Patreon](https://img.shields.io/badge/Support-Patreon-red?style=for-the-badge&logo=patreon)](https://www.patreon.com/brazilianscriptguy) [![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy) [![Ko-fi](https://img.shields.io/badge/Ko--fi-blue?style=for-the-badge&logo=kofi)](https://ko-fi.com/brazilianscriptguy) [![GoFundMe](https://img.shields.io/badge/GoFundMe-green?style=for-the-badge&logo=gofundme)](https://gofund.me/4599d3e6) [![WhatsApp](https://img.shields.io/badge/Community-WhatsApp-25D366?style=for-the-badge&logo=whatsapp)](https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c) [![GitHub Issues](https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/ISSUE_TEMPLATE/CUSTOM_ISSUE_TEMPLATE.md)

---

© 2026 Luiz Hamilton Silva. All rights reserved.
