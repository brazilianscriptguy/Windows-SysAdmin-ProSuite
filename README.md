# 🚀 Windows-SysAdmin-ProSuite

### Enterprise Windows Automation · IAM · Cybersecurity · Forensic Readiness

[![GitHub Repo](https://img.shields.io/badge/GitHub-Windows--SysAdmin--ProSuite-181717?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-5391FE?style=for-the-badge&logo=powershell&logoColor=white)](#) [![Windows](https://img.shields.io/badge/Windows-Server%20%7C%2010%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)](#) [![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge&logo=open-source-initiative)](LICENSE) 
[![CI - PowerShell Linting](https://img.shields.io/badge/CI-PowerShell%20Linting-2088FF?style=for-the-badge&logo=githubactions)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/actions) [![Code Scanning SARIF](https://img.shields.io/badge/SARIF-Code%20Scanning-brightgreen?style=for-the-badge)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/security/code-scanning)

---

## 🧭 Executive Overview

**Windows-SysAdmin-ProSuite** is an **enterprise-grade, research-aligned automation platform** for **Windows infrastructures**, authored and maintained by **Luiz Hamilton Silva (@brazilianscriptguy)**.

The repository consolidates **production-tested PowerShell and VBScript toolchains** designed for:

- Identity & Access Management (IAM)
- Secure Windows administration
- Cybersecurity and forensic readiness
- ITSM-aligned provisioning and compliance
- Auditability and operational traceability

All tooling is engineered with **runtime safety**, **deterministic logging**, and **PowerShell 5.1 compatibility** as first-class requirements.

---

## 🎯 Scope & Intended Use

This repository targets **real-world Windows environments**, including:

- 🏛️ Public sector and judicial institutions  
- 🏢 Enterprise and hybrid infrastructures  
- 🛡️ Blue Team / DFIR operations  
- 📋 Governance, risk, and compliance workflows  

It is **not** a collection of demos or isolated scripts, but a **cohesive automation suite** designed to operate safely across **large Windows realms**.

---

## 🗂️ Repository Domains & Navigation Guide

| Domain | Primary Purpose | Typical Users | Documentation |
|------|-----------------|---------------|---------------|
| **BlueTeam-Tools** | DFIR, Event Log analysis, incident response, forensic readiness | Blue Team, SOC, DFIR analysts | [View README](BlueTeam-Tools/README.md) |
| **Core-ScriptLibrary** | Shared PowerShell modules, GUI frameworks, helpers, packaging logic | Script authors, maintainers | [View README](Core-ScriptLibrary/README.md) |
| **SysAdmin-Tools** | AD, GPO, WSUS, DNS, DHCP, PKI, infrastructure automation | Windows admins, IAM engineers | [View README](SysAdmin-Tools/README.md) |
| **ITSM-Templates-WKS** | Windows 10/11 baseline, provisioning, lifecycle enforcement | Desktop engineering, ITSM teams | [View README](ITSM-Templates-WKS/README.md) |
| **ITSM-Templates-SVR** | Windows Server hardening, compliance, service baselines | Server admins, compliance teams | [View README](ITSM-Templates-SVR/README.md) |

> 📌 Each top-level directory contains its **own README.md** with domain-specific documentation and usage guidance.

---

## 🛡️ Engineering & Safety Principles

- ✅ **PowerShell 5.1 first**, PowerShell 7.x compatible where applicable  
- ✅ No destructive action without explicit intent (`ShouldProcess` enforced in core logic)  
- ✅ GUI-driven execution for operator safety when appropriate  
- ✅ Structured logging (`.log`) and exportable reports (`.csv`)  
- ✅ No hidden state, no silent failure patterns  

The suite is continuously evaluated using **PSScriptAnalyzer**, **SARIF reporting**, and CI pipelines configured in **report-only mode** to ensure **visibility without delivery interruption**.

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

This project reflects **long-term stewardship**, real operational use, and continuous refinement.

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
