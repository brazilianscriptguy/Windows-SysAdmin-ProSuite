## 🚀 Complete PowerShell and VBScript Toolkit

### ITSM Compliance for Windows 10/11 Workstations and Windows Server 2019/2022

Welcome to the **PowerShell Toolset for Windows Server Administration** and **VBScript Repository** — a curated and fully documented suite of automation tools by [`@brazilianscriptguy`](https://github.com/brazilianscriptguy) for managing secure, standardized, and scalable infrastructures across enterprise environments.

✨ All tools include intuitive **graphical user interfaces (GUI)**, structured `.log` generation, and exportable `.csv` audit reports — fully aligned with domain authentication policies, ITSM governance, and lifecycle management requirements.

---

## 🛠️ Toolkit Overview

The **Windows-SysAdmin-ProSuite** is segmented into specialized modules tailored for key operational domains across public sector and enterprise infrastructures:

- **Blue Team Tools:**  
  Digital forensics, incident triage, event log monitoring, and threat traceability for DFIR operations.

- **Core ScriptLibrary:**  
  Foundational modules and CI/CD helpers — modular PowerShell functions and NuGet-based packaging logic.

- **ITSM Templates (Server & Workstation):**  
  Institutional configuration and deployment templates for Windows 10/11 and Windows Server 2019/2022 — including pre-join scripts, layout normalization, and security compliance.

- **SysAdmin Tools:**  
  GUI-driven administration for Active Directory, GPOs, WSUS, DNS, DHCP, Certificate Services, and SSO — organized into seven functional directories.

---

## 💻 Core Features

- 🧪 **Forensic Readiness:** Artifacts, event log parsing, and breach detection.  
- ⚡ **PowerShell-Driven Automation:** Secure scripting with reusability and CI/CD support.  
- 🔐 **Server & Workstation Hardening:** Enforces institutional configurations and firewall, DNS, and GPO policies.  
- 👤 **IAM & Domain Prep:** Tools for AD objects, logon behavior, SID tracking, and offline login caching.  
- 📋 **Registry + GPO Integration:** Uses native Windows `.reg`, `.vbs`, and `.hta` to maintain compliance.  

---

## 🌟 Key Highlights & Core Competencies

- 🖼️ **GUI-Driven Interfaces:** Interactive scripts with guided automation.  
- 📝 **Standardized Logging:** Detailed `.log` outputs in structured directories.  
- 📊 **CSV Audit Reports:** BIOS, SID, OS state, update status, software inventory.  
- 🧩 **Modular Design:** All scripts are reusable, adaptable, and parameterized.  
- 🔁 **Release Automation:** GitHub Actions for linting, packaging, NuGet publishing.  
- 🛡️ **Zero Third-Party Binaries:** 100% native to the Windows OS ecosystem.  

---

## 🚀 Getting Started

```bash
git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
````

---

### 1. 📁 Explore folders and toolsets

Navigate through the structured directories to access categorized tools:

| Folder                | Contents                                                                                                                                                                                                                                                                                           |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `BlueTeam-Tools/`     | 🔍 `EventLogMonitoring/`, 🧪 `IncidentResponse/` — Event log parsing, incident triage, digital evidence collection                                                                                                                                                                                 |
| `Core-ScriptLibrary/` | 📦 `Modular-PS1-Scripts/`, 🚀 `Nuget-Package-Publisher/` — Shared functions, CI/CD helpers, NuSpec logic                                                                                                                                                                                           |
| `ITSM-Templates-SVR/` | 🛠️ Server baseline templates for DNS, GPO, DHCP, WSUS, IIS, and AD CS — institutional hardening and compliance                                                                                                                                                                                    |
| `ITSM-Templates-WKS/` | 🖥️ `BeforeJoinDomain/`, `AfterJoinDomain/`, `Assets/` — Standardization for Windows 10/11 workstations                                                                                                                                                                                            |
| `SysAdmin-Tools/`     | 🧩 GUI tools across 7 domains:<br> • ActiveDirectory-Management<br> • GroupPolicyObjects-Templates<br> • Network-and-Infrastructure-Management<br> • Security-and-Process-Optimization<br> • SystemConfiguration-and-Deployment<br> • WSUS-Management-Tools<br> • ActiveDirectory-SSO-Integrations |

---

### 2. ▶️ Run scripts

| File Type | Execution Method                         |
| --------- | ---------------------------------------- |
| `.ps1`    | Right-click → “Run with PowerShell”      |
| `.vbs`    | Right-click → “Open with Command Prompt” |
| `.hta`    | Double-click (Run as Administrator)      |

---

### 3. 📂 View logs and reports

| Path                | Description                                                         |
| ------------------- | ------------------------------------------------------------------- |
| `C:\ITSM-Logs-WKS\` | Logs from workstation standardization, domain join, profile imprint |
| `C:\ITSM-Logs-SVR\` | Logs from server configuration and domain services                  |
| `C:\Scripts-LOGS\`  | GPO sync, agent deployment, AV install routines                     |
| `C:\Logs-TEMP\`     | General-purpose logs for standalone scripts                         |

---

## 🤝 Support & Contributions

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge\&logo=gmail)](mailto:luizhamilton.lhr@gmail.com)
[![Patreon](https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge\&logo=patreon)](https://www.patreon.com/brazilianscriptguy)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge\&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-blue?style=for-the-badge\&logo=kofi)](https://ko-fi.com/brazilianscriptguy)
[![GoFundMe](https://img.shields.io/badge/GoFundMe-green?style=for-the-badge\&logo=gofundme)](https://www.gofundme.com/f/brazilianscriptguy)
[![GitHub Issues](https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge\&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/issues)
[![WhatsApp](https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge\&logo=whatsapp)](https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c)

---

💼 Thank you for using **Windows-SysAdmin-ProSuite** — your trusted toolkit for automating administrative tasks, enforcing security policies, and achieving ITSM excellence across public or enterprise infrastructure.

© 2025 Luiz Hamilton. All rights reserved.
