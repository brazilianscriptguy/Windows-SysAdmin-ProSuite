### 🚀 Enterprise Windows Automation · IAM · Cybersecurity · Forensic Readiness

[![GitHub Repo](https://img.shields.io/badge/GitHub-Windows--SysAdmin--ProSuite-181717?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite) [![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-5391FE?style=for-the-badge&logo=powershell&logoColor=white)](#) [![Windows](https://img.shields.io/badge/Windows-Server%20%7C%2010%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)](#) [![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge&logo=open-source-initiative)](LICENSE) [![CI - PowerShell Linting](https://img.shields.io/badge/CI-PowerShell%20Linting-2088FF?style=for-the-badge&logo=githubactions)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/actions)
[![Code Scanning SARIF](https://img.shields.io/badge/SARIF-Code%20Scanning-brightgreen?style=for-the-badge)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/security/code-scanning)

---

## 🧭 Executive Overview

**Windows-SysAdmin-ProSuite** is an **enterprise-grade, research-aligned automation platform** for **Windows infrastructures**, authored and maintained by **Luiz Hamilton Silva (@brazilianscriptguy)**.

The repository consolidates **production-tested PowerShell and VBScript toolchains** designed for:

- Identity & Access Management (IAM)
- Secure Windows administration
- Cybersecurity and forensic readiness
- ITSM-aligned provisioning and compliance
- Auditability and operational traceability

> All tooling is engineered with **runtime safety**, **deterministic logging**, and **PowerShell 5.1 compatibility** as first-class requirements.

---

## 🎯 Scope & Intended Use

This repository targets **real-world Windows environments**, including:

- 🏛️ Public sector and judicial institutions  
- 🏢 Enterprise and hybrid infrastructures  
- 🛡️ Blue Team / DFIR operations  
- 📋 Governance, risk, and compliance workflows  

> It is **not** a collection of demos or isolated scripts, but a **cohesive automation suite** designed to operate safely across **large Windows realms**.

---

## 💻 My Repository Packages

**Enterprise-grade automation, security, and compliance solutions — designed for real-world IT operations**

| Repository | Description | Key Features |
|------------|-------------|--------------|
| [![SysAdmin Tools](https://img.shields.io/badge/SysAdmin--Tools-Automation-blue?style=for-the-badge&logo=microsoft&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools) | Comprehensive PowerShell toolset for **Windows Server, Active Directory, network services, and WSUS** administration. | - Active Directory & OU lifecycle management<br>- GPO export/import & baseline enforcement<br>- WSUS maintenance, cleanup & SUSDB optimization<br>- DNS, DHCP, CA, RDS & infrastructure automation |
| [![BlueTeam Tools](https://img.shields.io/badge/BlueTeam--Tools-DFIR-orange?style=for-the-badge&logo=protonmail&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/BlueTeam-Tools) | Defensive security and **digital forensics** PowerShell utilities for investigation and incident response. | - DFIR data collection modules<br>- Event Log & credential audit parsers<br>- Threat hunting & incident response helpers |
| [![Core ScriptLibrary](https://img.shields.io/badge/Core--ScriptLibrary-Framework-red?style=for-the-badge&logo=visualstudiocode&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/Core-ScriptLibrary) | Foundational **modular PowerShell framework** and packaging engine used by all other suites. | - Reusable PowerShell helpers & UI components<br>- Centralized logging & execution patterns<br>- NuGet packaging & release automation |
| [![ITSM WKS](https://img.shields.io/badge/ITSM--Templates-WKS-green?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-WKS) | Standardized **Windows 10/11 workstation lifecycle** automation aligned with ITSM practices. | - Pre-join & post-join domain automation<br>- User profile, printer & layout standardization<br>- Compliance hardening, logging & CSV reporting |
| [![ITSM SVR](https://img.shields.io/badge/ITSM--Templates-SVR-purple?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-SVR) | Server-side counterpart to ITSM-WKS for **Windows Server provisioning and compliance**. | - Server baseline & hardening templates<br>- DNS, DHCP, time sync & role configuration<br>- GPO reset, drift remediation & audit logs |
| [![GPO Templates](https://img.shields.io/badge/GPO--Templates-Policies-ffcc00?style=for-the-badge&logo=matrix&logoColor=black)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools/GroupPolicyObjects-Templates) | Ready-to-import **Group Policy Objects** for domain and forest environments. | - Security, UX & infrastructure GPOs<br>- Domain-level and forest-wide templates<br>- Export/import automation & versioning |
| [![AD SSO APIs](https://img.shields.io/badge/AD--SSO--Integrations-SSO-8A2BE2?style=for-the-badge&logo=auth0&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools/ActiveDirectory-SSO-Integrations) | Cross-platform **Active Directory LDAP / SSO integration patterns** for applications and services. | - PHP, .NET, Flask, Node.js & Spring Boot examples<br>- Secure bind via environment variables<br>- Modular, documented, and enterprise-ready architecture |


---

## 🛡️ Engineering & Safety Principles

- ✅ **PowerShell 5.1 first**, PowerShell 7.x compatible where applicable  
- ✅ No destructive action without explicit intent (`ShouldProcess` enforced in core logic)  
- ✅ GUI-driven execution for operator safety when appropriate  
- ✅ Structured logging (`.log`) and exportable reports (`.csv`)  
- ✅ No hidden state, no silent failure patterns  

> The suite is continuously evaluated using **PSScriptAnalyzer**, **SARIF reporting**, and CI pipelines configured in **report-only mode** to ensure **visibility without delivery interruption**.

---

## 🔍 Quality, CI & Static Analysis

- PowerShell linting via **PSScriptAnalyzer**
- SARIF output integrated with **GitHub Code Scanning**
- Runtime-safety focused rule profile (low noise, high signal)
- PowerShell 5.1 compatibility validation
- Non-blocking CI: reports inform action, not gatekeeping

> Findings are surfaced as **artifacts and dashboards**, enabling controlled remediation cycles.

---

## 📚 Research, Governance & Citation

[![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.18487320-blue?style=for-the-badge&logo=zenodo)](https://doi.org/10.5281/zenodo.18487320) [![CITATION.cff](https://img.shields.io/badge/CITATION.cff-Available-informational?style=for-the-badge)]()

This repository is suitable for **academic, technical, and policy-oriented citation**, particularly in areas involving:

- Cybersecurity engineering
- Digital forensics (DFIR)
- Identity governance
- IT governance and compliance

---

## 👤 Author & Stewardship

**Luiz Hamilton Silva**  
Senior IAM Analyst | Identity & Access Management | AD & Azure AD | Windows Server Architect | PowerShell Automation  
GitHub: `@brazilianscriptguy`

> This project reflects **long-term stewardship**, real operational use, and continuous refinement.

---

## 🤝 Contribution & Reuse

- Contributions are welcome via pull requests
- Attribution is required under the MIT License
- Reuse in academic or institutional contexts should cite the repository or DOI

---

## 📬 Contact & Support

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr%40gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com) [![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Support-yellow?style=for-the-badge&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy) [![Ko--fi](https://img.shields.io/badge/Ko--fi-Support-blue?style=for-the-badge&logo=kofi)](https://ko-fi.com/brazilianscriptguy) [![Patreon](https://img.shields.io/badge/Patreon-Support-red?style=for-the-badge&logo=patreon)](https://www.patreon.com/brazilianscriptguy)

---

> **Engineering secure, auditable, and scalable Windows automation for enterprise and public-sector environments.**

© 2026 Luiz Hamilton Silva
