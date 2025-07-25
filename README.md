## 🚀 Complete PowerShell and VBScript Toolkit

### ITSM Compliance for Windows 10/11 Workstations and Windows Server 2019/2022

Welcome to the **PowerShell Toolset for Windows Server Administration** and **VBScript Repository** — a curated and fully documented suite of automation tools by [`@brazilianscriptguy`](https://github.com/brazilianscriptguy) for managing secure, standardized, and scalable infrastructures across enterprise environments.

✨ All tools include intuitive **graphical user interfaces (GUI)**, structured `.log` generation, and exportable `.csv` audit reports — fully aligned with domain authentication policies, ITSM governance, and lifecycle management requirements.

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

- 🧪 **Forensic Readiness:** Artifacts, Event Log parsing, breach detection.  
- ⚡ **PowerShell-Driven Automation:** Secure scripting with reusability and CI support.  
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
- 🛡️ **Zero Third-Party Binaries:** 100% native to Windows OS ecosystem.  

---

## 🚀 Getting Started

```bash
git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
````

1. **Explore folders and toolsets:**
   Navigate through the structured directories to access categorized tools:

   * `BlueTeam-Tools/`

     * `EventLogMonitoring/`: Automated Event Log parsing for incident detection
     * `IncidentResponse/`: Forensic triage, file tracing, and threat diagnostics

   * `Core-ScriptLibrary/`

     * `Modular-PS1-Scripts/`: Functions for script reusability and logic abstraction
     * `Nuget-Package-Publisher/`: NuSpec-based packaging and GitHub Actions automation

   * `ITSM-Templates-SVR/`

     * Server compliance templates for AD CS, DNS, DHCP, WSUS, GPOs, IIS

   * `ITSM-Templates-WKS/`

     * `BeforeJoinDomain/`: Executes 20 pre-domain compliance configurations
     * `AfterJoinDomain/`: Post-domain join cleanup and integration
     * `Assets/Certificates/`: Internal CA certificates for ADCS, WSUS, RDS
     * `Assets/ModifyReg/`: Themes, backgrounds, registry configs, lock screen
     * `Assets/AdditionalSupportScripts/`: System maintenance, SID, Kaspersky, unjoin tools
     * `MainDocs/`: Full guide (`JUNE-19-2025-ITSM-Templates.pdf`) and editable checklist

   * `SysAdmin-Tools/`

     * GUI-driven automation categorized into 7 folders:

       * ActiveDirectory-Management
       * GroupPolicyObjects-Templates
       * Network-and-Infrastructure-Management
       * Security-and-Process-Optimization
       * SystemConfiguration-and-Deployment
       * WSUS-Management-Tools
       * ActiveDirectory-SSO-Integrations

2. **Run scripts:**

   * `.ps1` → Right-click → “Run with PowerShell”
   * `.vbs` → Right-click → “Open with Command Prompt”
   * `.hta` → Double-click with admin rights

3. **View logs and reports:**

   * `C:\ITSM-Logs-WKS\` → Workstation actions
   * `C:\ITSM-Logs-SVR\` → Server-specific operations
   * `C:\Scripts-LOGS\` → GPO sync, antivirus installs, printers, agents
   * `C:\Logs-TEMP\` → Standalone tools and test outputs

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
