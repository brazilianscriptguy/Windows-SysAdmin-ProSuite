## 🚀 Complete PowerShell and VBScript Toolkit

### ITSM Compliance for Windows 10/11 Workstations and Windows Server 2019/2022

Welcome to the **PowerShell Toolset for Windows Server Administration** and **VBScript Repository** — a curated collection of automation scripts by [`@brazilianscriptguy`](https://github.com/brazilianscriptguy) for secure, compliant, and scalable Windows infrastructure management.

>✨ All tools include intuitive **graphical user interfaces (GUI)**, generate structured `.log` files, and many also export `.csv` audit reports.

---

## 🛠️ Toolkit Overview

**Purpose-built for critical IT service domains:**

| Folder | Description |
|--------|-------------|
| [![BlueTeam Tools](https://img.shields.io/badge/BlueTeam%20Tools-Forensics-orange?style=for-the-badge&logo=protonmail&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/BlueTeam-Tools) | PowerShell forensic tools for DFIR: EventLogMonitoring and IncidentResponse modules for breach triage, log analysis, and digital evidence. |
| [![Core ScriptLibrary](https://img.shields.io/badge/Core%20ScriptLibrary-Modules-red?style=for-the-badge&logo=visualstudiocode&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/Core-ScriptLibrary) | Core scripting modules for CI/CD pipelines, helper functions, and reusable logic blocks — includes NuGet packaging support. |
| [![ITSM SVR](https://img.shields.io/badge/ITSM%20Templates-SVR-purple?style=for-the-badge&logo=windows11&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-SVR) | Standardized Windows Server 2019/2022 baseline templates: DNS, AD CS, GPO, DHCP, IIS, and institutional compliance automation. |
| [![ITSM WKS](https://img.shields.io/badge/ITSM%20Templates-WKS-green?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-WKS) | Institutional ITSM for Windows 10/11: BeforeJoinDomain, AfterJoinDomain, and detailed workstation standardization routines. |
| [![SysAdmin Tools](https://img.shields.io/badge/SysAdmin%20Tools-Management-blue?style=for-the-badge&logo=microsoft&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools) | Centralized PowerShell + VBS GUIs for AD, GPO, WSUS, DNS, DHCP, CA, and infrastructure orchestration — organized into 7 categories. |

---

## 💻 Core Features

- 🧪 **Forensic Readiness:** Artifacts, Event Log parsing, breach detection  
- ⚡ **PowerShell-Driven Automation:** Secure scripting with reusability and CI support  
- 🔐 **Server & Workstation Hardening:** Enforces institutional configurations and firewall, DNS, and GPO policies  
- 👤 **IAM & Domain Prep:** Tools for AD objects, logon behavior, SID tracking, and offline login caching  
- 📋 **Registry + GPO Integration:** Uses native Windows `.reg`, `.vbs`, and `.hta` to maintain compliance  

---

## 🌟 Key Highlights & Core Competencies

- 🖼️ **GUI-Driven Interfaces:** Interactive scripts with guided automation  
- 📝 **Standardized Logging:** Detailed `.log` outputs in structured directories  
- 📊 **CSV Audit Reports:** BIOS, SID, OS state, update status, software inventory  
- 🧩 **Modular Design:** All scripts are reusable, adaptable, and parameterized  
- 🔁 **Release Automation:** GitHub Actions for linting, packaging, NuGet publishing  
- 🛡️ **Zero Third-Party Binaries:** 100% native to Windows OS ecosystem  

---

## ⚙️ Requirements & Environment Setup

| **Requirement** | Minimum Version / Notes |
|-------------|--------------------------|
| **PowerShell** | 5.1 (Windows built-in) or 7.x for cross-platform CLI |
| **Operating System** | Windows 10/11 (Workstation), Windows Server 2019/2022 |
| **Execution Policy** | Scripts require `RemoteSigned` or `Unrestricted` |
| **Administrator Rights** | Required for most `.ps1`, `.hta`, and registry-modifying `.vbs` files |
| **.NET Framework** | 4.7.2 or later (some GUIs depend on WPF/.NET UI elements) |
| **Optional Tools** | Git (for `git clone`), Notepad++ or VSCode for editing, Task Scheduler for automation |

---

## ▶️ How to Use

### Run scripts:

| **File Type** | Execution Method |
|-----------|------------------|
| `.ps1`    | Right-click → “Run with PowerShell” |
| `.vbs`    | Right-click → “Open with Command Prompt” |
| `.hta`    | Double-click (run as administrator) |

### View logs and reports:

| **Path** | Purpose |
|------|---------|
| `C:\ITSM-Logs-WKS\` | Workstation automation logs |
| `C:\ITSM-Logs-SVR\` | Server-side script execution logs |
| `C:\Scripts-LOGS\`  | GPO sync, agent deployment, antivirus logs |
| `C:\Logs-TEMP\`     | General-purpose and legacy script output |

---

## 🤝 Support & Contributions

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com)
[![Patreon](https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge&logo=patreon)](https://www.patreon.com/brazilianscriptguy)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-blue?style=for-the-badge&logo=kofi)](https://ko-fi.com/brazilianscriptguy)
[![GoFundMe](https://img.shields.io/badge/GoFundMe-green?style=for-the-badge&logo=gofundme)](https://www.gofundme.com/f/brazilianscriptguy)
[![GitHub Issues](https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/issues)
[![WhatsApp](https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp)](https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c)

---

💼 Thank you for using **Windows-SysAdmin-ProSuite** — your trusted toolkit for automating administrative tasks, enforcing security policies, and achieving ITSM excellence across public or enterprise infrastructure.

© 2025 Luiz Hamilton. All rights reserved.
_
