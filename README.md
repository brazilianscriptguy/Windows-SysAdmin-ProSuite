
# 🚀 Windows-SysAdmin-ProSuite  
### Enterprise Automation · IAM · Cybersecurity · Forensic Readiness

[![GitHub Repo](https://img.shields.io/badge/GitHub-Windows--SysAdmin--ProSuite-181717?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite) [![Zenodo DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.18487320-blue?style=for-the-badge&logo=zenodo)](https://doi.org/10.5281/zenodo.18487320) [![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge&logo=open-source-initiative)](LICENSE) [![PowerShell](https://img.shields.io/badge/PowerShell-Primary-5391FE?style=for-the-badge&logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell) [![Windows](https://img.shields.io/badge/Windows-Server%20%7C%2010%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)](https://www.microsoft.com/windows)

**Windows-SysAdmin-ProSuite** is an **enterprise-grade**, **research-aligned**, and **auditable** collection of **PowerShell** and **VBScript** automation tools authored by **Luiz Hamilton Silva (@brazilianscriptguy)**.

The project delivers **secure**, **compliant**, and **scalable** automation for **Windows Server (2019/2022)** and **Windows 10/11**, with strong focus on:

- 🔐 Identity & Access Management (IAM)
- 🛡️ Cybersecurity & Digital Forensics
- 📋 ITSM & Governance
- 📊 Auditability, reproducibility, and traceability

> ✨ Most tools include **GUI-driven execution**, generate structured `.log` files, and export `.csv` reports suitable for **audits, investigations, and compliance workflows**.

---

## 🇺🇸 National Interest & Research Alignment

[![Public Sector](https://img.shields.io/badge/Focus-Public%20Sector-blue?style=for-the-badge&logo=unitedstates)]() [![Cybersecurity](https://img.shields.io/badge/Domain-Cybersecurity-critical?style=for-the-badge&logo=security)]() [![Forensics](https://img.shields.io/badge/Domain-Digital%20Forensics-black?style=for-the-badge&logo=datadog)]() [![Governance](https://img.shields.io/badge/Domain-IT%20Governance-purple?style=for-the-badge&logo=databricks)]()

This repository represents an **independent, ongoing engineering and research initiative** addressing **systemic challenges** in Windows-based infrastructures, particularly in:

- 🏛️ Courts, universities, and government agencies  
- 🏢 Enterprise and hybrid environments  
- 🛡️ Blue Team / DFIR operations  

The toolkit contributes to **national-scale objectives** related to:

- Cybersecurity resilience  
- Digital trust and auditability  
- Secure identity governance  
- Infrastructure reliability  

---

## 🧭 Scope & Target Audience

[![Audience](https://img.shields.io/badge/Audience-Public%20Sector-0047AB?style=for-the-badge)]() [![Audience](https://img.shields.io/badge/Audience-Enterprise%20IT-2E8B57?style=for-the-badge)]() [![Audience](https://img.shields.io/badge/Audience-DFIR%20Teams-8B0000?style=for-the-badge)]() [![Audience](https://img.shields.io/badge/Audience-Researchers-6A5ACD?style=for-the-badge)]()

Designed for professionals working with:

- IT infrastructure administration
- Identity & Access Management
- Security operations and investigations
- ITSM-aligned provisioning
- Compliance and audit preparation

---

## 🛠️ Repository Architecture

[![BlueTeam](https://img.shields.io/badge/BlueTeam-Forensics-orange?style=for-the-badge&logo=protonmail)](BlueTeam-Tools) [![Core](https://img.shields.io/badge/Core-ScriptLibrary-red?style=for-the-badge&logo=visualstudiocode)](Core-ScriptLibrary) [![SysAdmin](https://img.shields.io/badge/SysAdmin-Tools-blue?style=for-the-badge&logo=microsoft)](SysAdmin-Tools) [![ITSM WKS](https://img.shields.io/badge/ITSM-WKS-green?style=for-the-badge&logo=windows)](ITSM-Templates-WKS) [![ITSM SVR](https://img.shields.io/badge/ITSM-SVR-purple?style=for-the-badge&logo=windows11)](ITSM-Templates-SVR)

| Component | Description |
|---------|-------------|
| **BlueTeam-Tools** | DFIR tooling for Event Logs, artifacts, timelines |
| **Core-ScriptLibrary** | Reusable modules, GUIs, helpers, NuGet engine |
| **SysAdmin-Tools** | AD, GPO, WSUS, DNS, DHCP, PKI automation |
| **ITSM-Templates-WKS** | Windows 10/11 baseline & lifecycle scripts |
| **ITSM-Templates-SVR** | Windows Server 2019/2022 compliance tooling |

---

## 💻 Core Capabilities

[![IAM](https://img.shields.io/badge/IAM-Automation-4682B4?style=for-the-badge)]() [![Forensics](https://img.shields.io/badge/Forensics-Ready-black?style=for-the-badge)]() [![Logs](https://img.shields.io/badge/Logging-Structured-success?style=for-the-badge)]() [![CSV](https://img.shields.io/badge/Reports-CSV-informational?style=for-the-badge)]()

- Event Log parsing and correlation  
- AD object and logon behavior analysis  
- GPO, registry, and baseline enforcement  
- Modular PowerShell orchestration  
- Audit-oriented outputs  

---

## 🌟 Engineering Principles

[![GUI](https://img.shields.io/badge/GUI-Driven-blueviolet?style=for-the-badge)]() [![Modular](https://img.shields.io/badge/Architecture-Modular-008080?style=for-the-badge)]() [![CI/CD](https://img.shields.io/badge/CI%2FCD-Automated-2088FF?style=for-the-badge&logo=githubactions)]() [![SARIF](https://img.shields.io/badge/SARIF-Integrated-brightgreen?style=for-the-badge)]()

- GUI-driven safe execution  
- Deterministic logging model  
- Modular, reusable design  
- CI pipelines with linting & SARIF  
- Native Windows tooling only  

---

## 🏛️ Governance, Quality & Security

[![Versioning](https://img.shields.io/badge/Versioning-Semantic-blue?style=for-the-badge)]() [![Releases](https://img.shields.io/badge/Releases-Tagged-success?style=for-the-badge)]() [![Security](https://img.shields.io/badge/Security-Policy-red?style=for-the-badge)]() [![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)]()

- Semantic versioning (`vMAJOR.MINOR.PATCH`)
- Release-based distribution
- CI for PowerShell, VBScript, Markdown
- SARIF security reporting
- MIT License

---

## ⚙️ Requirements

[![PS](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-5391FE?style=for-the-badge&logo=powershell)]() [![OS](https://img.shields.io/badge/OS-Windows%2010%2F11%20%7C%20Server-0078D6?style=for-the-badge&logo=windows)]() [![Admin](https://img.shields.io/badge/Privileges-Administrator-critical?style=for-the-badge)]()

---

## 🚀 Quick Start

```powershell
git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
cd Windows-SysAdmin-ProSuite

Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
.\ITSM-Templates-WKS\BeforeJoinDomain\Initialize-WKSBaseline.ps1
```

> ⚠️ Review scripts before execution in production environments.

---

## 📘 Research Software & Citation

[![DOI](https://img.shields.io/badge/DOI-Zenodo-blue?style=for-the-badge\&logo=zenodo)](https://doi.org/10.5281/zenodo.18487320) [![CFF](https://img.shields.io/badge/CITATION.cff-Available-informational?style=for-the-badge)]()

This repository may be cited in **academic**, **technical**, and **policy-oriented** works related to:

* Cybersecurity engineering
* Digital forensics (DFIR)
* IT governance & compliance
* Identity & Access Management

---

## 🎓 Academic & Professional Use

[![Academic](https://img.shields.io/badge/Use-Academic-6A5ACD?style=for-the-badge)]() [![Recruiters](https://img.shields.io/badge/Use-Technical%20Reviewers-2F4F4F?style=for-the-badge)]()

The project emphasizes:

* Explainability
* Operational realism
* Engineering discipline
* Reproducibility and auditability

---

## 🤝 Collaboration & Attribution

[![Contributions](https://img.shields.io/badge/Contributions-Welcome-success?style=for-the-badge)]() [![Attribution](https://img.shields.io/badge/Attribution-Required-blue?style=for-the-badge)]()

When reusing or referencing:

* Preserve attribution to **Luiz Hamilton Silva (@brazilianscriptguy)**
* Respect license and security policy
* Cite repository URL or DOI when applicable

---

## 🤝 Support

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge\&logo=gmail)](mailto:luizhamilton.lhr@gmail.com) [![Patreon](https://img.shields.io/badge/Patreon-Support-red?style=for-the-badge\&logo=patreon)](https://www.patreon.com/brazilianscriptguy) [![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge\&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy) [![Ko-fi](https://img.shields.io/badge/Ko--fi-blue?style=for-the-badge\&logo=kofi)](https://ko-fi.com/brazilianscriptguy) [![GoFundMe](https://img.shields.io/badge/GoFundMe-green?style=for-the-badge\&logo=gofundme)](https://www.gofundme.com/f/brazilianscriptguy)

---

> 🚀 *Engineering secure, scalable, and auditable Windows automation for enterprise and public-sector environments.*

© 2026 Luiz Hamilton Silva. All rights reserved.
