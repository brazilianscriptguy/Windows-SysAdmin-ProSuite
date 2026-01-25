## 🚀 Complete PowerShell and VBScript Toolkit 

### ITSM Compliance for Windows 10/11 Workstations and Windows Server 2019/2022

Welcome to the **PowerShell Toolset for Windows Server Administration** and **VBScript Repository** — a curated collection of automation scripts by [`@brazilianscriptguy`](https://github.com/brazilianscriptguy) for secure, compliant, and scalable Windows infrastructure management.

> ✨ Most tools include intuitive **graphical user interfaces (GUI)**, generate structured `.log` files, and many also export `.csv` audit reports.

---

## 🛠️ Toolkit Overview

**Purpose-built for critical IT service domains:**

| Folder | Description |
|--------|-------------|
| [![BlueTeam Tools](https://img.shields.io/badge/BlueTeam%20Tools-Forensics-orange?style=for-the-badge&logo=protonmail&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/BlueTeam-Tools) | PowerShell forensic tooling for DFIR, including **Event Log monitoring** and **incident response** modules for triage, analysis, and digital evidence workflows. |
| [![Core ScriptLibrary](https://img.shields.io/badge/Core%20ScriptLibrary-Modules-red?style=for-the-badge&logo=visualstudiocode&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/Core-ScriptLibrary) | Core scripting modules for CI/CD pipelines, helper functions, and reusable logic blocks — including **NuGet packaging** support. |
| [![ITSM SVR](https://img.shields.io/badge/ITSM%20Templates-SVR-purple?style=for-the-badge&logo=windows11&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-SVR) | Standardized **Windows Server 2019/2022** baseline templates: DNS, AD CS, GPO, DHCP, IIS, and institutional compliance automation. |
| [![ITSM WKS](https://img.shields.io/badge/ITSM%20Templates-WKS-green?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-WKS) | Institutional ITSM automation for **Windows 10/11**: `BeforeJoinDomain`, `AfterJoinDomain`, and workstation standardization routines. |
| [![SysAdmin Tools](https://img.shields.io/badge/SysAdmin%20Tools-Management-blue?style=for-the-badge&logo=microsoft&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools) | Centralized **PowerShell + VBScript** GUIs for AD, GPO, WSUS, DNS, DHCP, CA, and infrastructure orchestration — organized into 7 categories. |

---

## 💻 Core Features

- 🧪 **Forensic readiness:** Artifact collection, Event Log parsing, and breach detection support  
- ⚡ **PowerShell-driven automation:** Secure scripting patterns with reusability and CI support  
- 🔐 **Server & workstation hardening:** Enforces institutional baselines, including firewall, DNS, and GPO policies  
- 👤 **IAM & domain readiness:** Tools for AD objects, logon behavior, SID tracking, and offline logon caching  
- 📋 **Registry + GPO integration:** Leverages native Windows `.reg`, `.vbs`, and `.hta` to maintain compliance  

---

## 🌟 Key Highlights & Core Competencies

- 🖼️ **GUI-driven interfaces:** Interactive tools with guided automation  
- 📝 **Standardized logging:** Detailed `.log` outputs stored in consistent directories  
- 📊 **CSV audit reports:** BIOS, SID, OS posture, update status, and software inventory exports  
- 🧩 **Modular design:** Reusable components with parameters and consistent conventions  
- 🔁 **Release automation:** GitHub Actions for linting, packaging, and NuGet publishing  
- 🛡️ **Zero third-party binaries:** Built to remain native to the Windows ecosystem  

---

## ⚙️ Requirements & Environment Setup 

| Requirement | Minimum Version / Notes |
|-------------|--------------------------|
| **PowerShell** | **Windows PowerShell 5.1** (built-in) or **PowerShell 7.x** recommended |
| **Operating System** | **Windows 10/11** (Workstation), **Windows Server 2019/2022** |
| **Execution Policy** | Recommended: `RemoteSigned` (avoid `Unrestricted` unless required by your environment) |
| **Administrator Rights** | Required for many `.ps1`, `.hta`, and registry-modifying `.vbs` tasks |
| **.NET Framework** | **4.8** recommended (for legacy GUI components); Windows 11 commonly includes modern runtimes |
| **Optional Tools** | Git (for `git clone`), VS Code (recommended), Task Scheduler for automation |

---

## ▶️ How to Use

### Run scripts

| File Type | Execution Method |
|----------|-------------------|
| `.ps1` | Right-click → **Run with PowerShell** (or run from an elevated terminal) |
| `.vbs` | Run via `cscript.exe` (recommended) or double-click for `wscript.exe` |
| `.hta` | Double-click (run as administrator when required) |

### View logs and reports

| Path | Purpose |
|------|---------|
| `C:\ITSM-Logs-WKS\` | Workstation automation logs |
| `C:\ITSM-Logs-SVR\` | Server-side execution logs |
| `C:\Scripts-LOGS\` | GPO sync, agent deployment, antivirus logs |
| `C:\Logs-TEMP\` | General-purpose and legacy script output |

---

## 🤝 Support & Contributions

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr%40gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com)
[![Patreon](https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge&logo=patreon)](https://www.patreon.com/brazilianscriptguy)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-blue?style=for-the-badge&logo=kofi)](https://ko-fi.com/brazilianscriptguy)
[![GoFundMe](https://img.shields.io/badge/GoFundMe-green?style=for-the-badge&logo=gofundme)](https://www.gofundme.com/f/brazilianscriptguy)
[![GitHub Issues](https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/issues)
[![WhatsApp](https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp)](https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c)

---

💼 Thank you for using **Windows-SysAdmin-ProSuite** — your trusted toolkit for automating administrative tasks, enforcing security policies, and supporting ITSM excellence across public-sector or enterprise infrastructure.

© 2026 Luiz Hamilton. All rights reserved.
