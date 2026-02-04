## 🚀 Complete PowerShell and VBScript Toolkit

### ITSM Compliance for Windows 10/11 Workstations and Windows Server 2019/2022

Welcome to **Windows-SysAdmin-ProSuite** — a comprehensive and enterprise-grade collection of **PowerShell** and **VBScript** automation tools by [`@brazilianscriptguy`](https://github.com/brazilianscriptguy), designed for **secure**, **compliant**, and **scalable** Windows infrastructure management.

> ✨ Most tools include intuitive **graphical user interfaces (GUI)**, generate structured `.log` files for auditing, and many also export `.csv` reports to support compliance, forensics, and ITSM workflows.

---

## 🧭 Scope & Target Audience

This toolkit is purpose-built for:

* 🏛️ **Public-sector IT environments** (courts, universities, government agencies)
* 🏢 **Enterprise Windows domains** (on-prem and hybrid)
* 🛡️ **Blue Team / DFIR operations** (event logs, artifacts, investigations)
* 📋 **ITSM-aligned provisioning** of servers and workstations
* 📑 **Compliance-driven automation** (auditability, repeatability, governance)

---

## 🛠️ Toolkit Overview

**Organized by critical IT service domains:**

| Folder                                                                                                                                                                                                                                           | Description                                                                                                                                                          |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [![BlueTeam Tools](https://img.shields.io/badge/BlueTeam%20Tools-Forensics-orange?style=for-the-badge\&logo=protonmail\&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/BlueTeam-Tools)              | PowerShell forensic tooling for DFIR, including **Event Log monitoring**, **incident response**, and investigative workflows aligned with digital evidence handling. |
| [![Core ScriptLibrary](https://img.shields.io/badge/Core%20ScriptLibrary-Modules-red?style=for-the-badge\&logo=visualstudiocode\&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/Core-ScriptLibrary) | Foundational scripting modules for **reusability**, **helper functions**, **GUI backends**, CI/CD integration, and **NuGet packaging** automation.                   |
| [![ITSM SVR](https://img.shields.io/badge/ITSM%20Templates-SVR-purple?style=for-the-badge\&logo=windows11\&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-SVR)                       | Standardized **Windows Server 2019/2022** baselines: DNS, AD CS, GPO, DHCP, IIS, WSUS, and institutional compliance automation.                                      |
| [![ITSM WKS](https://img.shields.io/badge/ITSM%20Templates-WKS-green?style=for-the-badge\&logo=windows\&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-WKS)                          | ITSM automation for **Windows 10/11**: `BeforeJoinDomain`, `AfterJoinDomain`, asset tagging, security hardening, and workstation standardization routines.           |
| [![SysAdmin Tools](https://img.shields.io/badge/SysAdmin%20Tools-Management-blue?style=for-the-badge\&logo=microsoft\&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools)                | Centralized **PowerShell + VBScript GUIs** for AD, GPO, WSUS, DNS, DHCP, CA, and infrastructure orchestration, organized into multiple operational categories.       |

---

## 💻 Core Features

* 🧪 **Forensic readiness:** Artifact collection, Event Log parsing, timeline support, and breach detection
* ⚡ **PowerShell-driven automation:** Secure scripting patterns with modularity and CI/CD support
* 🔐 **Server & workstation hardening:** Enforcement of institutional baselines (firewall, DNS, GPOs, services)
* 👤 **IAM & domain readiness:** AD objects, logon behavior analysis, SID tracking, offline logon controls
* 📋 **Registry + GPO integration:** Native use of `.reg`, `.vbs`, `.hta`, and PowerShell for policy enforcement

---

## 🌟 Key Highlights & Engineering Principles

* 🖼️ **GUI-driven interfaces:** User-friendly tools with guided execution
* 📝 **Standardized logging model:** Deterministic `.log` outputs in predefined directories
* 📊 **CSV audit reports:** BIOS, SID, OS posture, update status, and software inventory exports
* 🧩 **Modular architecture:** Reusable components, consistent naming, and parameterization
* 🔁 **Release automation:** GitHub Actions for linting, SARIF analysis, packaging, and NuGet publishing
* 🛡️ **Native Windows tooling only:** No bundled third-party binaries

---

## 🏛️ Governance, Quality & Security

This repository follows **enterprise-grade governance standards**:

* Semantic versioning (`vMAJOR.MINOR.PATCH`)
* Tag- and release-based distribution
* CI pipelines with PowerShell & VBScript SARIF analysis
* Documented **Security Policy**, **Code of Conduct**, and **Contribution Guidelines**
* Responsible vulnerability disclosure process
* MIT License (SPDX compatible)

---

## ⚙️ Requirements & Environment Setup

| Requirement              | Minimum Version / Notes                                        |
| ------------------------ | -------------------------------------------------------------- |
| **PowerShell**           | Windows PowerShell **5.1** or **PowerShell 7.x** (recommended) |
| **Operating System**     | Windows **10/11**, Windows Server **2019/2022**                |
| **Execution Policy**     | Recommended: `RemoteSigned`                                    |
| **Administrator Rights** | Required for most automation tasks                             |
| **.NET Framework**       | **4.8** recommended (legacy GUI compatibility)                 |
| **Optional Tools**       | Git, Visual Studio Code, Task Scheduler                        |

---

## 🚀 Quick Start

```powershell
git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
cd Windows-SysAdmin-ProSuite
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
.\ITSM-Templates-WKS\BeforeJoinDomain\Initialize-WKSBaseline.ps1
```

> ⚠️ Always review scripts before running them in production environments.

---

## ▶️ How to Use

### Run scripts

| File Type | Execution Method                                                        |
| --------- | ----------------------------------------------------------------------- |
| `.ps1`    | Right-click → **Run with PowerShell** or execute from elevated terminal |
| `.vbs`    | Run via `cscript.exe` (recommended) or `wscript.exe`                    |
| `.hta`    | Double-click (run as administrator when required)                       |

### Logs and reports

| Path                              | Purpose                                                                 |
|-----------------------------------|-------------------------------------------------------------------------|
| `C:\ITSM-Logs-WKS\`               | Workstation automation execution logs                                   |
| `C:\ITSM-Logs-SVR\`               | Server-side automation and execution logs                                |
| `C:\Scripts-LOGS\`                | GPO synchronization, agents, and security tooling logs                  |
| `C:\Logs-TEMP\`                   | General-purpose, transient, and legacy script outputs                    |
| `%USERPROFILE%\Documents\`        | CSV and exported reports for compliance, forensics, and ITSM workflows  |

---

## 🤝 Support & Contributions

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com)
[![Patreon](https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge&logo=patreon)](https://www.patreon.com/brazilianscriptguy)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-blue?style=for-the-badge&logo=kofi)](https://ko-fi.com/brazilianscriptguy)
[![GoFundMe](https://img.shields.io/badge/GoFundMe-green?style=for-the-badge&logo=gofundme)](https://www.gofundme.com/f/brazilianscriptguy)

---

💼 Thank you for using **Windows-SysAdmin-ProSuite** — a professional toolkit for automating administrative tasks, enforcing security baselines, and sustaining ITSM excellence in enterprise and public-sector Windows environments.

© 2026 Luiz Hamilton Silva. All rights reserved.
