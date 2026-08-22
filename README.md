# Windows-SysAdmin-ProSuite — v1.8.8

### DOI: [10.5281/zenodo.18487320](https://doi.org/10.5281/zenodo.18487320)

[![GitHub Repo](https://img.shields.io/badge/GitHub-Windows--SysAdmin--ProSuite-181717?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite) [![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-5391FE?style=for-the-badge&logo=powershell&logoColor=white)](#) [ ![Windows](https://img.shields.io/badge/Windows-Server%20%7C%2010%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)](#) [![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge&logo=open-source-initiative)](LICENSE.txt) [![CI](https://img.shields.io/badge/CI-GitHub%20Actions-2088FF?style=for-the-badge&logo=githubactions)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/actions)
[![SARIF](https://img.shields.io/badge/SARIF-Code%20Scanning-brightgreen?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/security/code-scanning) [![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.18487320-blue?style=for-the-badge&logo=zenodo)](https://doi.org/10.5281/zenodo.18487320)

---

## 🧭 Overview

**Windows-SysAdmin-ProSuite** is an enterprise-grade, research-aligned automation platform for Windows Server and workstation environments — authored by **Luiz Hamilton Silva ([@brazilianscriptguy](https://github.com/brazilianscriptguy))**, Senior IAM Analyst, Windows Server Architect, and published researcher in digital forensics and cybersecurity.

Built around **production-tested PowerShell and VBScript toolchains**, the suite addresses five core operational pillars:

| Pillar | Scope |
|--------|-------|
| 🔐 Identity & Access Management | AD lifecycle, LDAP/SSO, credential hygiene |
| 🖥️ ITSM-Aligned Provisioning | Standardized workstation and server onboarding |
| 🛡️ Cybersecurity & Hardening | GPO enforcement, baseline templates, drift remediation |
| 🔬 Digital Forensics & DFIR | EVTX parsing, event correlation, incident response |
| 📋 Operational Auditability | Structured `.log` outputs, `.csv` exports, traceable execution |

> All tooling enforces **runtime safety**, **deterministic logging**, and **PowerShell 5.1 compatibility** as non-negotiable requirements.

---

## 🎯 Who This Is For

This is **not** a collection of demos or one-off scripts. It is a cohesive automation suite built for production use across:

| Environment | Primary Use Case |
|---|---|
| 🏛️ Public sector & judicial institutions | Compliance-driven provisioning and audit trails |
| 🏢 Enterprise & hybrid infrastructures | AD, WSUS, DNS, DHCP, PKI, RDS at scale |
| 🛡️ Blue Team / DFIR operations | Threat hunting, event log analysis, forensic collection |
| 📋 Governance, risk & compliance teams | GPO enforcement, ITSM-aligned change management |
| 🎓 Academic & research environments | Citeable tooling grounded in peer-reviewed methodology |

---

## 📦 Suite Modules

Ten specialized modules — each independently usable, collectively cohesive.

| Module | Purpose | Key Capabilities |
|--------|---------|------------------|
| [![ADCS-Management-Tools](https://img.shields.io/badge/ADCS--Management--Tools-PKI-005A9C?style=flat-square&logo=letsencrypt&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools/ADCS-Management-Tools) | PowerShell toolset for **AD CS, enterprise PKI & certificate lifecycle** administration. | CA maintenance · Certificate lifecycle · Expired certificate cleanup · Repository organization |
| [![AD-SSO-Integrations](https://img.shields.io/badge/AD--SSO--Integrations-LDAP%2FSSO-8A2BE2?style=flat-square&logo=auth0&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools/ActiveDirectory-SSO-Integrations) | **AD LDAP / SSO integration patterns** for cross-platform apps. | PHP · .NET · Flask · Node.js · Spring Boot · Secure env-var binding |
| [![BlueTeam-Tools](https://img.shields.io/badge/BlueTeam--Tools-DFIR-E05C00?style=flat-square&logo=protonmail&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/BlueTeam-Tools) | Defensive security & **digital forensics** utilities for investigation and IR. | DFIR collection · EVTX parsers · Credential audits · Threat hunting |
| [![Core-ScriptLibrary](https://img.shields.io/badge/Core--ScriptLibrary-Framework-C0392B?style=flat-square&logo=visualstudiocode&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/Core-ScriptLibrary) | **Modular PowerShell framework** shared by all modules. | Reusable helpers · Centralized logging · NuGet & SHA256 automation |
| [![GPO-Templates](https://img.shields.io/badge/GPO--Templates-Policies-F39C12?style=flat-square&logo=matrix&logoColor=black)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools/GroupPolicyObjects-Templates) | Ready-to-import **Group Policy Objects** for domain and forest environments. | Security & UX GPOs · Forest-wide templates · Export/import automation |
| [![ITSM-Templates-SVR](https://img.shields.io/badge/ITSM--Templates-SVR-8E44AD?style=flat-square&logo=windows&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-SVR) | **Windows Server provisioning, hardening & ITSM compliance**. | Server baselines · Role configuration · GPO drift remediation |
| [![ITSM-Templates-WKS](https://img.shields.io/badge/ITSM--Templates-WKS-27AE60?style=flat-square&logo=windows&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-WKS) | **Windows 10/11 workstation lifecycle** automation aligned with ITSM. | Pre/post-join · Profile & printer standardization · Compliance hardening |
| [![ProSuite-Hub](https://img.shields.io/badge/ProSuite--Hub-Launcher-1ABC9C?style=flat-square&logo=powershell&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ProSuite-Hub) | Unified **GUI launcher and module orchestrator** for the entire suite. | Centralized tool discovery · Menu-driven interface · Single entry point |
| [![SysAdmin-Tools](https://img.shields.io/badge/SysAdmin--Tools-Automation-0078D6?style=flat-square&logo=microsoft&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools) | PowerShell toolset for **Windows Server, Active Directory & network infrastructure** administration. | AD & OU lifecycle · GPO enforcement · DNS · DHCP · RDS · System administration |
| [![WSUS-Management-Tools](https://img.shields.io/badge/WSUS--Management--Tools-Updates-0078D4?style=flat-square&logo=microsoft&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools/WSUS-Management-Tools) | PowerShell toolset for **WSUS administration, maintenance & SUSDB optimization**. | WSUS inventory · Configuration auditing · Cleanup operations · WID/SQL maintenance · SUSDB reindexing · API validation |

---

## 🏗️ Engineering Principles

Every script and automation component in this suite is engineered against a consistent enterprise safety and operational contract:

- **PowerShell 5.1 first** — Windows PowerShell 5.1 remains the primary compatibility baseline, with PowerShell 7.x support where applicable
- **Explicit change intent** — potentially destructive or state-changing operations use confirmation controls, dry-run capabilities, `ShouldProcess`, or equivalent safeguards where technically applicable
- **Operator-safe execution** — GUI-driven workflows are provided where interactive administration benefits from controlled selection, validation, and confirmation
- **Preflight validation** — dependencies, privileges, target systems, modules, services, paths, and operational prerequisites are validated before significant changes
- **Structured logging and reporting** — significant operations produce traceable `.log`, `.csv`, SARIF, or other structured evidence where applicable
- **Transparent error handling** — failures are surfaced with actionable context and recorded rather than silently suppressed
- **Credential hygiene by design** — credentials and secrets are externalized or securely supplied at runtime and are never intentionally hardcoded
- **Least-privilege administration** — elevated privileges are required only when demanded by the underlying administrative operation
- **Idempotent and repeatable automation** — workflows are designed to tolerate repeated execution and minimize unintended configuration drift
- **Environment-aware execution** — tooling validates infrastructure context before applying Active Directory, AD CS, GPO, WSUS, SUSDB, Windows Server, or endpoint changes
- **Controlled infrastructure maintenance** — high-impact operations incorporate sequencing, validation, recovery considerations, and post-change verification
- **Auditability and operational traceability** — administrative actions are designed to support troubleshooting, governance, compliance, and change-review requirements
- **Modular architecture** — reusable functions, standardized patterns, and component separation reduce duplication and improve maintainability
- **ITSM-aligned change management** — provisioning, maintenance, remediation, and lifecycle workflows follow controlled and repeatable operational practices
- **Secure DevOps integration** — repository automation incorporates static analysis, secret scanning, formatting validation, SARIF reporting, integrity verification, and controlled release workflows

> Quality and security are continuously evaluated through **PSScriptAnalyzer**, **SARIF**, **CodeQL**, **Gitleaks**, **EditorConfig**, **Prettier**, **SHA256 integrity validation**, and **GitHub Actions CI/CD**, with enforcement or report-only behavior applied according to each workflow's operational purpose.

---

## 🔍 Quality Assurance & Static Analysis

| Tool | Role |
|------|------|
| [![PSScriptAnalyzer](https://img.shields.io/badge/PSScriptAnalyzer-ON-blueviolet?style=flat-square&logo=powershell)](https://github.com/PowerShell/PSScriptAnalyzer) | PowerShell linting — runtime safety and best-practice enforcement |
| [![Gitleaks](https://img.shields.io/badge/Gitleaks-ON-red?style=flat-square&logo=github)](https://github.com/gitleaks/gitleaks) | Secret scanning — prevents credential leaks at commit time |
| [![Prettier](https://img.shields.io/badge/Prettier-ON-ff69b4?style=flat-square&logo=prettier)](https://prettier.io) | Markdown and web-asset formatting consistency |
| [![EditorConfig](https://img.shields.io/badge/EditorConfig-ON-blue?style=flat-square&logo=editorconfig)](https://editorconfig.org) | Cross-editor formatting standardization |
| [![NuGet](https://img.shields.io/badge/NuGet-SHA256-blue?style=flat-square&logo=nuget)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/actions) | Integrity-verified package releases |
| [![CodeQL](https://img.shields.io/badge/CodeQL-Static%20Analysis-purple?style=flat-square&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/security/code-scanning) | Deep static security analysis |

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

[![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.18487320-blue?style=for-the-badge&logo=zenodo)](https://doi.org/10.5281/zenodo.18487320) [![CITATION.cff](https://img.shields.io/badge/CITATION.cff-Available-informational?style=for-the-badge)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/CITATION.cff) [![ORCID](https://img.shields.io/badge/ORCID-0000--0003--3705--7468-A6CE39?style=for-the-badge&logo=orcid)](https://orcid.org/0000-0003-3705-7468)

Suitable for **academic, technical, and policy-oriented citation** across cybersecurity engineering, DFIR, IAM, IT governance, and ITSM-aligned infrastructure management.

**Citation (APA):**
> Roberto da Silva, L. H. (2026). *Windows-SysAdmin-ProSuite* (Version 1.8.8) [Computer software]. Zenodo. https://doi.org/10.5281/zenodo.18487320

**Selected publications:**
- Roberto da Silva, L. H. (2025). *SQL Syntax Models for Building Parsers to Query Event Logs in EVTX Format*. Revista FT — Computer Science, Vol. 29, Issue 142. [DOI: 10.69849/revistaft/th102502121360](https://doi.org/10.69849/revistaft/th102502121360)
- Roberto da Silva, L. H. (2024). *Event Logs: Applying a Log Analysis Model for Auditing Event Record Registration*. Sorian Editora. ISBN: 978-65-5453-366-9
- Roberto da Silva, L. H. (2009). *Computer Networking Technology: Using GPOs to Secure Corporate Domains*. Ciência Moderna.

---

## 👤 Author & Stewardship

**Luiz Hamilton Silva** — `@brazilianscriptguy`

Senior IAM Analyst · Identity & Access Management · AD & Azure AD · Windows Server Architect · PowerShell Automation · Digital Forensics Researcher

[![LinkedIn](https://img.shields.io/badge/LinkedIn-brazilianscriptguy-0077B5?style=for-the-badge&logo=linkedin)](https://www.linkedin.com/in/brazilianscriptguy/) [![YouTube](https://img.shields.io/badge/YouTube-@brazilianscriptguy-FF0000?style=for-the-badge&logo=youtube)](https://www.youtube.com/@brazilianscriptguy) [![X](https://img.shields.io/badge/X-@brazscriptguy-000000?style=for-the-badge&logo=x)](https://x.com/brazscriptguy) [![ORCID](https://img.shields.io/badge/ORCID-0000--0003--3705--7468-A6CE39?style=for-the-badge&logo=orcid)](https://orcid.org/0000-0003-3705-7468)

> This project reflects years of operational use, continuous refinement in production environments, and a commitment to principled, auditable systems engineering.

---

## 🤝 Contributing & Reuse

Contributions are welcome. Please review [`CONTRIBUTING.md`](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/CONTRIBUTING.md) before submitting a pull request.

- **Pull requests** — bug fixes, documentation improvements, and new tools aligned with the suite's principles
- **Attribution** — required under the MIT License for any reuse or derivative work
- **Academic / institutional reuse** — please cite the repository DOI or the `CITATION.cff` file
- **Security disclosures** — follow the [`SECURITY.md`](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/SECURITY.md) responsible disclosure process

---

## 📬 Contact & Support

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr%40gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com) [![Patreon](https://img.shields.io/badge/Patreon-Support-red?style=for-the-badge&logo=patreon)](https://www.patreon.com/brazilianscriptguy) [![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Support-yellow?style=for-the-badge&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy) [![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-29ABE0?style=for-the-badge&logo=kofi)](https://ko-fi.com/brazilianscriptguy) [![GoFundMe](https://img.shields.io/badge/GoFundMe-Support-00B964?style=for-the-badge&logo=gofundme)](https://www.gofundme.com/f/brazilianscriptguy) [![WhatsApp](https://img.shields.io/badge/WhatsApp-PowerShellBR-25D366?style=for-the-badge&logo=whatsapp)](https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c)

---

> *"Engineering secure, auditable, and scalable Windows automation for enterprise and public-sector environments — grounded in operational practice and peer-reviewed research."*

© 2026 Luiz Hamilton Silva · MIT License · [CHANGELOG](CHANGELOG.md) · [CITATION](CITATION.cff)

---

<!-- ATS Keywords -->
PowerShell automation · Windows Server administration · Active Directory · Azure AD · DNS · DHCP · WSUS · Group Policy (GPO) · PKI · certificate management · Identity & Access Management (IAM) · ITSM provisioning · security hardening · credential hygiene · digital forensics · DFIR · EVTX log analysis · event correlation · incident response · CI/CD · GitHub Actions · PSScriptAnalyzer · NuGet · SHA256 · SARIF · CodeQL · secure DevOps · modular architecture · enterprise scripting · Windows infrastructure automation
