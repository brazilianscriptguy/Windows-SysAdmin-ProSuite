# Windows-SysAdmin-ProSuite — v1.8.8

### DOI: [10.5281/zenodo.18487320](https://doi.org/10.5281/zenodo.18487320)

[![GitHub Repo](https://img.shields.io/badge/GitHub-Windows--SysAdmin--ProSuite-181717?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite) [![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-5391FE?style=for-the-badge&logo=powershell&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite) [![Windows](https://img.shields.io/badge/Windows-Server%20%7C%2010%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite) [![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge&logo=open-source-initiative)](LICENSE.txt) [![CI](https://img.shields.io/badge/CI-GitHub%20Actions-2088FF?style=for-the-badge&logo=githubactions)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/actions) [![SARIF](https://img.shields.io/badge/SARIF-Code%20Scanning-brightgreen?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/security/code-scanning) [![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.18487320-blue?style=for-the-badge&logo=zenodo)](https://doi.org/10.5281/zenodo.18487320)

---

## 🧭 Overview

**Windows-SysAdmin-ProSuite** is an enterprise-grade, research-aligned automation platform for **Windows Server, Windows 10/11, Active Directory, Identity and Access Management, enterprise PKI, WSUS, Group Policy, ITSM, Blue Team, and DFIR operations** — authored and maintained by **Luiz Hamilton Silva ([@brazilianscriptguy](https://github.com/brazilianscriptguy))**.

Built around production-oriented **PowerShell and VBScript automation**, reusable administrative frameworks, structured logging, deterministic packaging, and GitHub Actions-based release engineering, the suite addresses seven core operational pillars:

| Pillar | Scope |
|--------|-------|
| 🔐 Identity & Access Management | Active Directory lifecycle · LDAP/SSO · IAM · credential hygiene |
| 🔏 Enterprise PKI & Certificate Services | AD CS · CA administration · certificate lifecycle · repository management |
| 🖥️ ITSM-Aligned Provisioning | Standardized Windows workstation and server lifecycle automation |
| 🛡️ Cybersecurity & Hardening | Group Policy · security baselines · configuration control · drift remediation |
| 🔬 Digital Forensics & DFIR | EVTX analysis · event correlation · evidence collection · incident response |
| 🔄 Update & Infrastructure Management | WSUS · SUSDB · DNS · DHCP · network services · infrastructure administration |
| 📋 Operational Auditability | Structured `.log` output · `.csv` reporting · validation · traceable execution |

> Tooling is engineered around **runtime safety, explicit administrative intent, deterministic logging, operational traceability, PowerShell 5.1 compatibility, and controlled change management**.

---

## 🎯 Who This Is For

This repository is not intended as a collection of isolated demonstrations or disposable scripts. It is a cohesive automation and administration suite designed for production-oriented use across:

| Environment | Primary Use Case |
|---|---|
| 🏛️ Public sector & judicial institutions | Compliance-driven administration · standardized provisioning · operational audit trails |
| 🏢 Enterprise & hybrid infrastructures | Active Directory · PKI · WSUS · DNS · DHCP · GPO · Windows Server administration |
| 🔐 IAM & identity engineering | AD lifecycle · LDAP/SSO integration · access governance · credential hygiene |
| 🔏 PKI & certificate services | AD CS · Certificate Authority administration · certificate lifecycle and repository management |
| 🛡️ Blue Team / DFIR operations | Threat hunting · EVTX analysis · incident response · forensic collection |
| 📋 Governance, risk & compliance teams | GPO enforcement · configuration control · ITSM-aligned change management |
| 🎓 Academic & research environments | Citeable automation and security tooling supported by documented research |

---

## 📦 Suite Modules

Ten specialized functional modules — independently usable and collectively integrated through a common engineering, documentation, and release model.

> The repository release architecture manages **12 distribution packages**: the 10 functional modules below plus the aggregate `All-Repository-Files` and `READMEs-Files-Package` distributions.

| Module | Purpose | Key Capabilities |
|--------|---------|------------------|
| [![ADCS-Management-Tools](https://img.shields.io/badge/ADCS--Management--Tools-PKI-005A9C?style=flat-square&logo=letsencrypt&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools/ADCS-Management-Tools) | Enterprise **Active Directory Certificate Services and PKI administration**. | AD CS · CA maintenance · certificate lifecycle · repository management · certificate hygiene |
| [![AD-SSO-Integrations](https://img.shields.io/badge/AD--SSO--Integrations-LDAP%2FSSO-8A2BE2?style=flat-square&logo=auth0&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools/ActiveDirectory-SSO-Integrations) | Cross-platform **Active Directory LDAP / SSO integration patterns** for applications and services. | PHP · .NET · Flask · Node.js · Spring Boot · secure bind · environment-based configuration |
| [![BlueTeam-Tools](https://img.shields.io/badge/BlueTeam--Tools-DFIR-E05C00?style=flat-square&logo=protonmail&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/BlueTeam-Tools) | Defensive security and **digital forensics / incident response** tooling. | DFIR collection · EVTX analysis · event correlation · credential auditing · threat hunting |
| [![Core-ScriptLibrary](https://img.shields.io/badge/Core--ScriptLibrary-Framework-C0392B?style=flat-square&logo=visualstudiocode&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/Core-ScriptLibrary) | Shared **modular PowerShell framework and release foundation**. | Reusable helpers · structured logging · common execution patterns · NuGet · SHA256 automation |
| [![GPO-Templates](https://img.shields.io/badge/GPO--Templates-Policies-F39C12?style=flat-square&logo=matrix&logoColor=black)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools/GroupPolicyObjects-Templates) | Reusable **Group Policy Object templates** for Active Directory governance. | Security baselines · configuration policies · forest/domain templates · GPO export/import · lifecycle management |
| [![ITSM-Templates-SVR](https://img.shields.io/badge/ITSM--Templates--SVR-Server-8E44AD?style=flat-square&logo=windows&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-SVR) | **Windows Server provisioning, standardization, hardening, and ITSM lifecycle automation**. | Server baselines · provisioning · role configuration · validation · maintenance · compliance |
| [![ITSM-Templates-WKS](https://img.shields.io/badge/ITSM--Templates--WKS-Workstations-27AE60?style=flat-square&logo=windows&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-WKS) | **Windows 10/11 workstation lifecycle automation** aligned with ITSM practices. | Pre/post-join automation · workstation baselines · profile and printer standardization · compliance hardening |
| [![ProSuite-Hub](https://img.shields.io/badge/ProSuite--Hub-Launcher-1ABC9C?style=flat-square&logo=powershell&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ProSuite-Hub) | Unified **GUI launcher and module orchestration layer** for the suite. | Centralized tool discovery · menu-driven operation · module orchestration · single administrative entry point |
| [![SysAdmin-Tools](https://img.shields.io/badge/SysAdmin--Tools-Automation-0078D6?style=flat-square&logo=microsoft&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools) | Comprehensive PowerShell toolset for **Windows systems and infrastructure administration**. | AD & OU lifecycle · DNS · DHCP · network services · system configuration · deployment · administrative automation |
| [![WSUS-Management-Tools](https://img.shields.io/badge/WSUS--Management--Tools-Update%20Services-0078D4?style=flat-square&logo=windows&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools/WSUS-Management-Tools) | Dedicated **Windows Server Update Services and SUSDB administration** toolkit. | WSUS inventory · configuration auditing · cleanup · Admin API validation · WID/SQL · SUSDB reindexing |

---

## 📦 Distribution Architecture

The GitHub Actions release pipeline manages **12 canonical distribution packages** using synchronized CHANGELOG headings, managed tag prefixes, release matrices, ZIP archives, SHA256 manifests, and GitHub Releases.

| Distribution Package | Classification |
|----------------------|----------------|
| `ADCS-Management-Tools` | Functional module |
| `AD-SSO-Integrations` | Functional module |
| `All-Repository-Files` | Aggregate repository distribution |
| `BlueTeam-Tools` | Functional module |
| `Core-ScriptLibrary` | Functional module |
| `GPO-Templates` | Functional module |
| `ITSM-Templates-SVR` | Functional module |
| `ITSM-Templates-WKS` | Functional module |
| `ProSuite-Hub` | Functional module |
| `READMEs-Files-Package` | Aggregate documentation distribution |
| `SysAdmin-Tools` | Functional module |
| `WSUS-Management-Tools` | Functional module |

Nested components under `SysAdmin-Tools` retain dedicated release identities while participating in parent and repository-wide distributions. Changes to applicable nested components therefore propagate to their standalone package, `SysAdmin-Tools`, and `All-Repository-Files`.

---

## 🏗️ Engineering Principles

The suite follows a common engineering and operational-safety contract:

- ✅ **PowerShell 5.1 first** — PowerShell 7.x compatibility maintained where applicable
- ✅ **Explicit administrative intent** — potentially disruptive operations require controlled execution and appropriate confirmation semantics
- ✅ **Validation-first execution** — prerequisites, dependencies, targets, and operational state are validated before applicable changes
- ✅ **Idempotent behavior where practical** — repeated execution should converge toward the intended state without unnecessary changes
- ✅ **Structured logging and reporting** — significant operations produce traceable `.log`, `.csv`, or equivalent structured output where applicable
- ✅ **No silent failures** — actionable errors, warnings, and validation results are surfaced to the operator
- ✅ **Credential hygiene by design** — production secrets and credentials are externalized rather than embedded in source code
- ✅ **Least-privilege administration** — privileged operations are constrained to the access required for the requested task
- ✅ **Post-change verification** — applicable administrative operations validate resulting state after execution
- ✅ **ITSM-aligned change management** — provisioning, maintenance, remediation, and lifecycle workflows emphasize repeatability and auditability
- ✅ **Deterministic release engineering** — managed packages use canonical names, automated ZIP creation, SHA256 integrity manifests, and component-specific release metadata

> Repository quality and security controls are continuously evaluated through **PSScriptAnalyzer, SARIF reporting, CodeQL, Gitleaks, formatting controls, and GitHub Actions CI**, with findings feeding controlled remediation and engineering cycles.

---

## 🔍 Quality Assurance & Static Analysis

| Tool | Role |
|------|------|
| [![PSScriptAnalyzer](https://img.shields.io/badge/PSScriptAnalyzer-ON-blueviolet?style=flat-square&logo=powershell)](https://github.com/PowerShell/PSScriptAnalyzer) | PowerShell static analysis, compatibility checks, and engineering-quality validation |
| [![Gitleaks](https://img.shields.io/badge/Gitleaks-ON-red?style=flat-square&logo=github)](https://github.com/gitleaks/gitleaks) | Secret scanning and credential-exposure detection |
| [![Prettier](https://img.shields.io/badge/Prettier-ON-ff69b4?style=flat-square&logo=prettier)](https://prettier.io) | Markdown and supported web-asset formatting consistency |
| [![EditorConfig](https://img.shields.io/badge/EditorConfig-ON-blue?style=flat-square&logo=editorconfig)](https://editorconfig.org) | Cross-editor formatting and whitespace standardization |
| [![NuGet](https://img.shields.io/badge/NuGet-Packaging-blue?style=flat-square&logo=nuget)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/actions) | Package creation and publication support |
| [![SHA256](https://img.shields.io/badge/SHA256-Integrity-2E8B57?style=flat-square&logo=securityscorecard&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/releases) | Release artifact integrity verification |
| [![CodeQL](https://img.shields.io/badge/CodeQL-Static%20Analysis-purple?style=flat-square&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/security/code-scanning) | Static security analysis and code-scanning integration |
| [![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-CI%2FCD-2088FF?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/actions) | Automated validation, CHANGELOG maintenance, packaging, and release orchestration |

> CI findings provide operational visibility and support controlled remediation while release automation maintains deterministic package naming, integrity validation, and traceability.

---

## 🌐 Language Composition

The repository is predominantly PowerShell, with supporting technologies used where required by integration, legacy administration, reporting, and database-maintenance scenarios.

| Language / Technology | Primary Use |
|-----------------------|-------------|
| PowerShell | Windows administration · IAM · AD CS · WSUS · DFIR · ITSM · automation |
| VBScript | Legacy Windows and workstation automation |
| T-SQL / SQL | WSUS SUSDB maintenance and database operations |
| HTML / Web assets | GUI components, documentation, and report presentation |
| PHP | LDAP / SSO integration examples |
| .NET | Active Directory and SSO integration examples |
| Python / Flask | Cross-platform LDAP / SSO integration examples |
| Node.js | Cross-platform LDAP / SSO integration examples |
| Java / Spring Boot | Enterprise LDAP / SSO integration examples |

> Exact language percentages may change as the repository evolves; GitHub's repository language statistics remain the authoritative current measurement.

---

## 📚 Research Foundation & Citation

[![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.18487320-blue?style=for-the-badge&logo=zenodo)](https://doi.org/10.5281/zenodo.18487320) [![CITATION.cff](https://img.shields.io/badge/CITATION.cff-Available-informational?style=for-the-badge)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/CITATION.cff) [![ORCID](https://img.shields.io/badge/ORCID-0000--0003--3705--7468-A6CE39?style=for-the-badge&logo=orcid)](https://orcid.org/0000-0003-3705-7468)

**Windows-SysAdmin-ProSuite** combines production-oriented Windows systems engineering with research-informed practices in **cybersecurity, Identity and Access Management (IAM), Active Directory, enterprise PKI, Group Policy, WSUS, Digital Forensics & Incident Response (DFIR), and IT governance**.

The project is structured to support **academic, technical, institutional, professional, and policy-oriented citation**, providing persistent research identifiers through **Zenodo DOI**, structured citation metadata through **`CITATION.cff`**, and author attribution through **ORCID**.

### Software Citation

**APA:**

> Roberto da Silva, L. H. (2026). *Windows-SysAdmin-ProSuite* (Version 1.8.8) [Computer software]. Zenodo. https://doi.org/10.5281/zenodo.18487320

**Repository DOI:** `10.5281/zenodo.18487320`  
**Version:** `1.8.8`  
**License:** MIT  
**Citation metadata:** [`CITATION.cff`](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/CITATION.cff)

### 🔬 Peer-Reviewed Research

**2025**

[![DOI](https://img.shields.io/badge/DOI-10.69849%2Frevistaft%2Fth102502121360-blue?style=for-the-badge&logo=crossref)](https://doi.org/10.69849/revistaft/th102502121360) [![ISSN](https://img.shields.io/badge/ISSN-1678--0817-555555?style=for-the-badge&logo=readthedocs)](https://doi.org/10.69849/revistaft/th102502121360) [![Qualis](https://img.shields.io/badge/Qualis-B2-4CAF50?style=for-the-badge&logo=academia&logoColor=white)](https://doi.org/10.69849/revistaft/th102502121360)

**Roberto da Silva, Luiz Hamilton**  
**_"SQL Syntax Models for Building Parsers to Query Event Logs in EVTX Format"_**  
*Revista FT — Computer Science*, Vol. 29, Issue 142, January 2025  
ISSN: **1678-0817** · Qualis: **B2**  
DOI: **10.69849/revistaft/th102502121360**

> Presents a structured SQL-oriented methodology for querying and parsing **Windows Event Log (EVTX)** data, supporting security auditing, incident investigation, event correlation, authentication analysis, and Active Directory traceability.

### 🎓 Master's Research

**2017 — Federal University of Pernambuco (UFPE)**

[![UFPE Repository](https://img.shields.io/badge/UFPE-Academic%20Repository-003366?style=for-the-badge&logo=academia)](https://repositorio.ufpe.br/handle/123456789/27515) [![Institution](https://img.shields.io/badge/Institution-UFPE-555555?style=for-the-badge&logo=academia)](https://repositorio.ufpe.br/handle/123456789/27515) [![Field](https://img.shields.io/badge/Field-Computer%20Science-4CAF50?style=for-the-badge&logo=academia&logoColor=white)](https://repositorio.ufpe.br/handle/123456789/27515)

**Roberto da Silva, Luiz Hamilton**  
**_"Event Logs: Applying a Log Analysis Model for Auditing Event Record Registration"_**  
Federal University of Pernambuco (UFPE), 2017  
Master's Thesis · **Computer Science**  
Keywords: **Log Auditing · Digital Forensics · Event Logs · Security Monitoring**

> Defines a structured methodology for event-log auditing and digital forensic analysis, applying Syslog principles and PowerShell-driven workflows to security-event examination, forensic readiness, operational monitoring, and governance.

### 📘 Selected Books

**2024**

[![DOI](https://img.shields.io/badge/DOI-10.54466%2Fsorianed.978--65--5453--366--9-blue?style=for-the-badge&logo=crossref)](https://doi.org/10.54466/sorianed.978-65-5453-366-9) [![Print ISBN](https://img.shields.io/badge/Print%20ISBN-978--65--5453--346--1-555555?style=for-the-badge&logo=bookstack)](https://www.magazineluiza.com.br/log-de-eventos-aplicacao-de-um-modelo-de-analise-de-logs-para-auditoria-de-registro-de-eventos-editora-sorian/p/ek6e33k93h/li/adml/?seller_id=sorianeditorial) [![eBook ISBN](https://img.shields.io/badge/eBook%20ISBN-978--65--5453--366--9-555555?style=for-the-badge&logo=bookstack)](https://www.magazineluiza.com.br/log-de-eventos-aplicacao-de-um-modelo-de-analise-de-logs-para-auditoria-de-registro-de-eventos-editora-sorian/p/ek6e33k93h/li/adml/?seller_id=sorianeditorial)

**Roberto da Silva, Luiz Hamilton**  
**_Event Logs: Applying a Log Analysis Model for Auditing Event Record Registration_**  
Sorian, 1st ed., 2024  
Print ISBN: **978-65-5453-346-1** · eBook ISBN: **978-65-5453-366-9**  
DOI: **10.54466/sorianed.978-65-5453-366-9**

> A practitioner-focused scholarly work on **Windows Event Log auditing, forensic readiness, security-event analysis, and vulnerability identification**, connecting research methodology with PowerShell-enabled operational workflows.

**2009**

[![DOI](https://img.shields.io/badge/DOI-10.54236%2Fedcimo.001-blue?style=for-the-badge&logo=crossref)](https://doi.org/10.54236/edcimo.001) [![ISBN](https://img.shields.io/badge/ISBN-978--85--7393--835--7-555555?style=for-the-badge&logo=bookstack)](https://www.worldcat.org/isbn/9788573938357)

**Roberto da Silva, Luiz Hamilton**  
**_Computer Networking Technology: Using GPOs to Secure Corporate Domains_**  
Ciência Moderna, 1st ed., 2009  
ISBN: **978-85-7393-835-7**  
DOI: **10.54236/edcimo.001**

> Focused on the application of **Group Policy Objects (GPOs)** to secure and standardize Windows domain environments through centralized policy enforcement, Active Directory administration, security baselines, configuration governance, and domain-level hardening.

---

## 👤 Author & Stewardship

**Luiz Hamilton Silva** — `@brazilianscriptguy`

**Identity & Access Management · Active Directory · Windows Server Architecture · Enterprise PKI · PowerShell Automation · Windows Security · Digital Forensics & Incident Response**

[![GitHub](https://img.shields.io/badge/GitHub-brazilianscriptguy-181717?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy) [![LinkedIn](https://img.shields.io/badge/LinkedIn-brazilianscriptguy-0077B5?style=for-the-badge&logo=linkedin)](https://www.linkedin.com/in/brazilianscriptguy/) [![ORCID](https://img.shields.io/badge/ORCID-0000--0003--3705--7468-A6CE39?style=for-the-badge&logo=orcid)](https://orcid.org/0000-0003-3705-7468) [![YouTube](https://img.shields.io/badge/YouTube-@brazilianscriptguy-FF0000?style=for-the-badge&logo=youtube)](https://www.youtube.com/@brazilianscriptguy) [![X](https://img.shields.io/badge/X-@brazscriptguy-000000?style=for-the-badge&logo=x)](https://x.com/brazscriptguy)

The project is maintained at the intersection of **enterprise Windows engineering, identity architecture, cybersecurity, infrastructure automation, PKI, DFIR, and applied research**.

Its engineering model emphasizes:

- **Production-oriented automation** for Windows Server and Windows 10/11 environments
- **Identity engineering** across Active Directory, LDAP, SSO, and IAM workflows
- **Enterprise PKI administration** through Active Directory Certificate Services and certificate lifecycle management
- **Infrastructure management** spanning Group Policy, DNS, DHCP, WSUS, SUSDB, and Windows services
- **Security engineering and DFIR** through event-log analysis, forensic readiness, security auditing, and incident-response tooling
- **Reproducibility and auditability** through structured logging, deterministic packaging, SHA256 integrity validation, and controlled release automation
- **Research-informed engineering** connecting academic methodology with operational systems administration and cybersecurity practice

> **Windows-SysAdmin-ProSuite** represents the convergence of operational Windows engineering, identity and security architecture, automation, and research — developed as a maintainable, auditable, reproducible, and citeable open-source platform.

---

## 🤝 Contributing & Reuse

Contributions are welcome. Review [`CONTRIBUTING.md`](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/CONTRIBUTING.md) before submitting a pull request.

- **Pull requests** — bug fixes, documentation improvements, security improvements, automation enhancements, and new tools aligned with repository engineering principles
- **Attribution** — reuse and derivative works must comply with the repository's MIT License terms
- **Academic / institutional reuse** — cite the repository DOI or use the metadata provided in `CITATION.cff`
- **Security disclosures** — follow the [`SECURITY.md`](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/SECURITY.md) responsible-disclosure process
- **Release governance** — component naming and CHANGELOG structures should remain compatible with the automated 12-package release architecture

---

## 📬 Contact & Support

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr%40gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com) [![Patreon](https://img.shields.io/badge/Patreon-Support-red?style=for-the-badge&logo=patreon)](https://www.patreon.com/brazilianscriptguy) [![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Support-yellow?style=for-the-badge&logo=buymeacoffee)](https://buymeacoffee.com/brazilianscriptguy) [![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-29ABE0?style=for-the-badge&logo=kofi)](https://ko-fi.com/brazilianscriptguy) [![GoFundMe](https://img.shields.io/badge/GoFundMe-Support-00B964?style=for-the-badge&logo=gofundme)](https://www.gofundme.com/f/brazilianscriptguy) [![WhatsApp](https://img.shields.io/badge/WhatsApp-PowerShellBR-25D366?style=for-the-badge&logo=whatsapp)](https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c)

---

> *"Engineering secure, auditable, and scalable Windows automation for enterprise and public-sector environments — grounded in operational practice and research."*

© 2026 Luiz Hamilton Silva · MIT License · [CHANGELOG](CHANGELOG.md) · [CITATION](CITATION.cff)

---

<!-- ATS-optimized keyword layer -->

**Core Expertise:** PowerShell automation · Windows PowerShell 5.1 · PowerShell 7 · Windows systems administration · Windows Server · Windows 10 · Windows 11 · Active Directory · Active Directory Domain Services · AD DS · Active Directory Certificate Services · AD CS · enterprise PKI · Public Key Infrastructure · Certificate Authority administration · CA maintenance · certificate lifecycle management · certificate repository management · certificate hygiene · Identity and Access Management · IAM · LDAP · LDAPS · Single Sign-On · SSO · authentication integration · Group Policy · Group Policy Objects · GPO · GPO lifecycle management · DNS · DHCP · Windows Server Update Services · WSUS · SUSDB · Windows Internal Database · WID · SQL Server · patch management · update infrastructure · WSUS maintenance · WSUS cleanup · SUSDB reindexing · network infrastructure administration · system configuration · software deployment · ITSM · workstation lifecycle management · server lifecycle management · security hardening · configuration baselines · configuration drift remediation · least privilege · credential hygiene · Blue Team · Digital Forensics and Incident Response · DFIR · incident response · Windows Event Log monitoring · EVTX analysis · event correlation · threat hunting · security auditing · compliance · governance · structured logging · operational traceability · validation-first automation · idempotent automation · PowerShell modular architecture · GUI administration · GitHub Actions · CI/CD · release automation · automated CHANGELOG management · Semantic Versioning · deterministic packaging · NuGet packaging · ZIP distribution · SHA256 integrity validation · PSScriptAnalyzer · SARIF · CodeQL · EditorConfig · Prettier · Gitleaks · secure DevOps · enterprise automation · Windows infrastructure automation · public-sector IT
