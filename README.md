# Windows-SysAdmin-ProSuite — v1.8.8

### DOI: [10.5281/zenodo.18487320](https://doi.org/10.5281/zenodo.18487320)

## 🚀 Enterprise Windows Automation · IAM · Cybersecurity · ITSM · Forensic Readiness

[![GitHub Repo](https://img.shields.io/badge/GitHub-Windows--SysAdmin--ProSuite-181717?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-5391FE?style=for-the-badge&logo=powershell&logoColor=white)](#)
[![VBScript](https://img.shields.io/badge/VBScript-1.7%25-0078D6?style=for-the-badge&logo=windows&logoColor=white)](#)
[![Windows](https://img.shields.io/badge/Windows-Server%20%7C%2010%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)](#)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge&logo=open-source-initiative)](LICENSE.txt)
[![CI — PowerShell Linting](https://img.shields.io/badge/CI-PowerShell%20Linting-2088FF?style=for-the-badge&logo=githubactions)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/actions)
[![Code Scanning SARIF](https://img.shields.io/badge/SARIF-Code%20Scanning-brightgreen?style=for-the-badge)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/security/code-scanning)
[![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.18487320-blue?style=for-the-badge&logo=zenodo)](https://doi.org/10.5281/zenodo.18487320)

---

## 🧭 Executive Overview

**Windows-SysAdmin-ProSuite** is an **enterprise-grade, research-aligned automation platform** for **Windows Server and workstation infrastructures**, authored and maintained by **Luiz Hamilton Silva ([@brazilianscriptguy](https://github.com/brazilianscriptguy))** — Senior IAM Analyst, Windows Server Architect, and published researcher in digital forensics and cybersecurity.

The suite consolidates **production-tested PowerShell and VBScript toolchains** across seven specialized modules, purpose-built for:

- **Identity & Access Management (IAM)** — AD lifecycle, LDAP/SSO, credential hygiene
- **ITSM-aligned provisioning** — standardized workstation and server onboarding workflows
- **Cybersecurity & security hardening** — GPO enforcement, baseline templates, drift remediation
- **Digital forensics & DFIR readiness** — EVTX parsing, event correlation, incident response
- **Operational auditability** — structured `.log` outputs, `.csv` exports, traceable execution

> All tooling is engineered with **runtime safety**, **deterministic logging**, and **PowerShell 5.1 compatibility** as non-negotiable first-class requirements.

---

## 🎯 Scope & Intended Use

This repository targets **real-world Windows environments**, not sandboxes or toy scripts. It is designed for:

| Environment | Use Case |
|---|---|
| 🏛️ Public sector & judicial institutions | Compliance-driven provisioning and audit trails |
| 🏢 Enterprise & hybrid infrastructures | AD management, WSUS, DNS, DHCP, PKI, RDS |
| 🛡️ Blue Team / DFIR operations | Threat hunting, event log analysis, forensic collection |
| 📋 Governance, risk & compliance teams | GPO enforcement, ITSM-aligned change management |
| 🎓 Academic & research environments | Citeable tooling grounded in peer-reviewed methodology |

> This is **not** a collection of demos or isolated utilities — it is a **cohesive automation suite** engineered to operate safely and repeatably across **large Windows domain realms**.

---

## 📦 Suite Modules

**Seven specialized packages — each independently usable, collectively cohesive.**

| Module | Purpose | Key Capabilities |
|--------|---------|-----------------|
| [![SysAdmin-Tools](https://img.shields.io/badge/SysAdmin--Tools-Automation-0078D6?style=flat-square&logo=microsoft&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools) | Comprehensive PowerShell toolset for **Windows Server, Active Directory, network services, and WSUS** administration. | AD & OU lifecycle management · GPO export/import & baseline enforcement · WSUS maintenance & SUSDB optimization · DNS, DHCP, CA, RDS & infrastructure automation |
| [![BlueTeam-Tools](https://img.shields.io/badge/BlueTeam--Tools-DFIR-E05C00?style=flat-square&logo=protonmail&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/BlueTeam-Tools) | Defensive security and **digital forensics** PowerShell utilities for investigation and incident response. | DFIR data collection modules · EVTX / Event Log parsers · Credential audit analysis · Threat hunting & IR helpers |
| [![Core-ScriptLibrary](https://img.shields.io/badge/Core--ScriptLibrary-Framework-C0392B?style=flat-square&logo=visualstudiocode&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/Core-ScriptLibrary) | Foundational **modular PowerShell framework** and packaging engine shared by all modules. | Reusable helpers & GUI components · Centralized logging & execution patterns · NuGet packaging & SHA256 release automation |
| [![ITSM-Templates-WKS](https://img.shields.io/badge/ITSM--Templates-WKS-27AE60?style=flat-square&logo=windows&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-WKS) | Standardized **Windows 10/11 workstation lifecycle** automation aligned with ITSM best practices. | Pre-join & post-join domain automation · User profile, printer & layout standardization · Compliance hardening, structured logging & CSV reporting |
| [![ITSM-Templates-SVR](https://img.shields.io/badge/ITSM--Templates-SVR-8E44AD?style=flat-square&logo=windows&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-SVR) | Server-side counterpart for **Windows Server provisioning, hardening, and ITSM compliance**. | Server baseline & hardening templates · DNS, DHCP, time sync & role configuration · GPO reset, configuration drift remediation & audit logs |
| [![GPO-Templates](https://img.shields.io/badge/GPO--Templates-Policies-F39C12?style=flat-square&logo=matrix&logoColor=black)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools/GroupPolicyObjects-Templates) | Ready-to-import **Group Policy Objects** for domain and forest environments. | Security, UX & infrastructure GPOs · Domain-level and forest-wide templates · Export/import automation & versioning |
| [![AD-SSO-Integrations](https://img.shields.io/badge/AD--SSO--Integrations-LDAP%20%2F%20SSO-8A2BE2?style=flat-square&logo=auth0&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools/ActiveDirectory-SSO-Integrations) | Cross-platform **Active Directory LDAP / SSO integration patterns** for applications and services. | PHP, .NET, Flask, Node.js & Spring Boot examples · Secure bind via environment variables · Modular, documented, enterprise-ready architecture |
| [![ProSuite-Hub](https://img.shields.io/badge/ProSuite--Hub-Launcher-1ABC9C?style=flat-square&logo=powershell&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ProSuite-Hub) | Unified **GUI launcher and module orchestrator** for the entire suite. | Centralized tool discovery & execution · Operator-friendly menu-driven interface · Single entry point for all ProSuite modules |

---

## 🏗️ Engineering & Safety Principles

Every script in this suite is built against the same safety contract:

- ✅ **PowerShell 5.1 first** — PowerShell 7.x compatible where applicable
- ✅ **No destructive action without explicit intent** — `ShouldProcess` enforced in all core logic
- ✅ **GUI-driven execution** for operator safety in interactive scenarios
- ✅ **Structured logging** (`.log`) and exportable audit reports (`.csv`) on every significant operation
- ✅ **No hidden state, no silent failures** — every error path is surfaced and logged
- ✅ **Credential hygiene by design** — secrets bound via environment variables, never hardcoded
- ✅ **ITSM-aligned change management** — provisioning workflows follow standardized lifecycle patterns

> The suite is continuously evaluated using **PSScriptAnalyzer**, **SARIF reporting**, and **GitHub Actions CI pipelines** in report-only mode — ensuring **visibility without blocking delivery**.

---

## 🔍 Quality Assurance & Static Analysis

| Tool | Role |
|------|------|
| **PSScriptAnalyzer** | PowerShell linting — runtime safety, best-practice enforcement |
| **GitHub Code Scanning (SARIF)** | Static analysis findings surfaced as dashboards and artifacts |
| **Gitleaks** | Secret scanning — prevents credential leaks at commit time |
| **Prettier + EditorConfig** | Markdown and web-asset formatting consistency |
| **NuGet + SHA256** | Integrity-verified package releases |
| **CodeQL** | Deep static security analysis |

> CI findings inform controlled remediation cycles — **non-blocking by design, signal-rich by intent**.

---

## 🌐 Language Composition

| Language | Share | Primary Use |
|----------|-------|-------------|
| PowerShell | 96.7% | Automation, IAM, DFIR, ITSM provisioning |
| VBScript | 1.3% | Legacy workstation automation |
| HTML | 0.6% | GUI components and report templates |
| T-SQL | 0.4% | WSUS SUSDB maintenance queries |
| Java / PHP / Other | 0.6% | AD LDAP / SSO integration examples |

---

## 📚 Research Foundation & Citation

[![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.18487320-blue?style=for-the-badge&logo=zenodo)](https://doi.org/10.5281/zenodo.18487320)
[![CITATION.cff](https://img.shields.io/badge/CITATION.cff-Available-informational?style=for-the-badge)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/CITATION.cff)
[![ORCID](https://img.shields.io/badge/ORCID-0000--0003--3705--7468-A6CE39?style=for-the-badge&logo=orcid)](https://orcid.org/0000-0003-3705-7468)

This repository is backed by peer-reviewed publications and is suitable for **academic, technical, and policy-oriented citation** in the following domains:

- Cybersecurity engineering and security automation
- Digital forensics and incident response (DFIR)
- Identity governance and access management (IAM)
- IT governance, risk, and compliance (GRC)
- ITSM-aligned Windows infrastructure management

**Citation (APA):**

> Roberto da Silva, L. H. (2026). *Windows-SysAdmin-ProSuite* (Version 1.8.8) [Computer software]. Zenodo. https://doi.org/10.5281/zenodo.18487320

**Selected publications grounding this work:**

- Roberto da Silva, L. H. (2025). *SQL Syntax Models for Building Parsers to Query Event Logs in EVTX Format*. Revista FT — Computer Science, Vol. 29, Issue 142. [DOI: 10.69849/revistaft/th102502121360](https://doi.org/10.69849/revistaft/th102502121360)
- Roberto da Silva, L. H. (2024). *Event Logs: Applying a Log Analysis Model for Auditing Event Record Registration*. Sorian Editora. ISBN: 978-65-5453-366-9
- Roberto da Silva, L. H. (2009). *Computer Networking Technology: Using GPOs to Secure Corporate Domains*. Ciência Moderna.

---

## 👤 Author & Stewardship

**Luiz Hamilton Silva** — `@brazilianscriptguy`
Senior IAM Analyst · Identity & Access Management · AD & Azure AD · Windows Server Architect · PowerShell Automation · Digital Forensics Researcher

[![LinkedIn](https://img.shields.io/badge/LinkedIn-brazilianscriptguy-0077B5?style=for-the-badge&logo=linkedin)](https://www.linkedin.com/in/brazilianscriptguy/)
[![YouTube](https://img.shields.io/badge/YouTube-@brazilianscriptguy-FF0000?style=for-the-badge&logo=youtube)](https://www.youtube.com/@brazilianscriptguy)
[![X](https://img.shields.io/badge/X-@brazscriptguy-000000?style=for-the-badge&logo=x)](https://x.com/brazscriptguy)
[![ORCID](https://img.shields.io/badge/ORCID-0000--0003--3705--7468-A6CE39?style=for-the-badge&logo=orcid)](https://orcid.org/0000-0003-3705-7468)

> This project reflects **years of operational use**, continuous refinement in production environments, and a commitment to principled, auditable systems engineering.

---

## 🤝 Contributing & Reuse

Contributions are welcome. Please review [`CONTRIBUTING.md`](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/CONTRIBUTING.md) before submitting a pull request.

- **Pull requests** — bug fixes, documentation improvements, and new tools aligned with the suite's principles
- **Attribution** — required under the MIT License for any reuse or derivative work
- **Academic / institutional reuse** — please cite the repository DOI or the `CITATION.cff` file
- **Security disclosures** — follow the [`SECURITY.md`](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/SECURITY.md) responsible disclosure process

---

## 📬 Contact & Support

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr%40gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com)
[![Patreon](https://img.shields.io/badge/Patreon-Support-red?style=for-the-badge&logo=patreon)](https://www.patreon.com/brazilianscriptguy)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Support-yellow?style=for-the-badge&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-29ABE0?style=for-the-badge&logo=kofi)](https://ko-fi.com/brazilianscriptguy)
[![GoFundMe](https://img.shields.io/badge/GoFundMe-Support-00B964?style=for-the-badge&logo=gofundme)](https://www.gofundme.com/f/brazilianscriptguy)
[![WhatsApp](https://img.shields.io/badge/WhatsApp-PowerShellBR-25D366?style=for-the-badge&logo=whatsapp)](https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c)

---

> *"Engineering secure, auditable, and scalable Windows automation for enterprise and public-sector environments — grounded in operational practice and peer-reviewed research."*

© 2026 Luiz Hamilton Silva · MIT License · [CHANGELOG](CHANGELOG.md) · [CITATION](CITATION.cff)
