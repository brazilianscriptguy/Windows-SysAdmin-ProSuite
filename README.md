Windows-SysAdmin-ProSuite — v1.8.8
DOI: 10.5281/zenodo.18487320
![GitHub Repo](https://img.shields.io/badge/GitHub-Windows--SysAdmin--ProSuite-181717?style=for-the-badge&logo=github)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-Server%20%7C%2010%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge&logo=open-source-initiative)
![CI](https://img.shields.io/badge/CI-GitHub%20Actions-2088FF?style=for-the-badge&logo=githubactions)
![SARIF](https://img.shields.io/badge/SARIF-Code%20Scanning-brightgreen?style=for-the-badge&logo=github)
![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.18487320-blue?style=for-the-badge&logo=zenodo)
---
🧭 Overview
Windows-SysAdmin-ProSuite is an enterprise-grade, research-aligned automation platform for Windows Server and workstation environments — authored by Luiz Hamilton Silva (@brazilianscriptguy), Senior IAM Analyst, Windows Server Architect, and published researcher in digital forensics and cybersecurity.
Built around production-tested PowerShell and VBScript toolchains, the suite addresses five core operational pillars:
Pillar	Scope
🔐 Identity & Access Management	AD lifecycle, LDAP/SSO, credential hygiene
🖥️ ITSM-Aligned Provisioning	Standardized workstation and server onboarding
🛡️ Cybersecurity & Hardening	GPO enforcement, baseline templates, drift remediation
🔬 Digital Forensics & DFIR	EVTX parsing, event correlation, incident response
📋 Operational Auditability	Structured `.log` outputs, `.csv` exports, traceable execution
> All tooling enforces **runtime safety**, **deterministic logging**, and **PowerShell 5.1 compatibility** as non-negotiable requirements.
---
🎯 Who This Is For
This is not a collection of demos or one-off scripts. It is a cohesive automation suite built for production use across:
Environment	Primary Use Case
🏛️ Public sector & judicial institutions	Compliance-driven provisioning and audit trails
🏢 Enterprise & hybrid infrastructures	AD, WSUS, DNS, DHCP, PKI, RDS at scale
🛡️ Blue Team / DFIR operations	Threat hunting, event log analysis, forensic collection
📋 Governance, risk & compliance teams	GPO enforcement, ITSM-aligned change management
🎓 Academic & research environments	Citeable tooling grounded in peer-reviewed methodology
---
📦 Suite Modules
Eight specialized modules — each independently usable, collectively cohesive.
Module	Purpose	Key Capabilities
![SysAdmin-Tools](https://img.shields.io/badge/SysAdmin--Tools-Automation-0078D6?style=flat-square&logo=microsoft&logoColor=white)	PowerShell toolset for Windows Server, AD, network services & WSUS.	AD & OU lifecycle · GPO enforcement · WSUS & SUSDB · DNS, DHCP, CA, RDS
![BlueTeam-Tools](https://img.shields.io/badge/BlueTeam--Tools-DFIR-E05C00?style=flat-square&logo=protonmail&logoColor=white)	Defensive security & digital forensics utilities for investigation and IR.	DFIR collection · EVTX parsers · Credential audits · Threat hunting
![Core-ScriptLibrary](https://img.shields.io/badge/Core--ScriptLibrary-Framework-C0392B?style=flat-square&logo=visualstudiocode&logoColor=white)	Modular PowerShell framework shared by all modules.	Reusable helpers · Centralized logging · NuGet & SHA256 automation
![ITSM-Templates-WKS](https://img.shields.io/badge/ITSM--Templates-WKS-27AE60?style=flat-square&logo=windows&logoColor=white)	Windows 10/11 workstation lifecycle automation aligned with ITSM.	Pre/post-join · Profile & printer standardization · Compliance hardening
![ITSM-Templates-SVR](https://img.shields.io/badge/ITSM--Templates-SVR-8E44AD?style=flat-square&logo=windows&logoColor=white)	Windows Server provisioning, hardening & ITSM compliance.	Server baselines · Role configuration · GPO drift remediation
![GPO-Templates](https://img.shields.io/badge/GPO--Templates-Policies-F39C12?style=flat-square&logo=matrix&logoColor=black)	Ready-to-import Group Policy Objects for domain and forest environments.	Security & UX GPOs · Forest-wide templates · Export/import automation
![AD-SSO-Integrations](https://img.shields.io/badge/AD--SSO--Integrations-LDAP%2FSSO-8A2BE2?style=flat-square&logo=auth0&logoColor=white)	AD LDAP / SSO integration patterns for cross-platform apps.	PHP · .NET · Flask · Node.js · Spring Boot · Secure env-var binding
![ProSuite-Hub](https://img.shields.io/badge/ProSuite--Hub-Launcher-1ABC9C?style=flat-square&logo=powershell&logoColor=white)	Unified GUI launcher and module orchestrator for the entire suite.	Centralized tool discovery · Menu-driven interface · Single entry point
---
🏗️ Engineering Principles
Every script in this suite is built against the same safety contract:
✅ PowerShell 5.1 first — PowerShell 7.x compatible where applicable
✅ No destructive action without explicit intent — `ShouldProcess` enforced in all core logic
✅ GUI-driven execution for operator safety in interactive scenarios
✅ Structured logging (`.log`) and exportable audit reports (`.csv`) on every significant operation
✅ No hidden state, no silent failures — every error path is surfaced and logged
✅ Credential hygiene by design — secrets bound via environment variables, never hardcoded
✅ ITSM-aligned change management — provisioning workflows follow standardized lifecycle patterns
> Continuously evaluated via **PSScriptAnalyzer**, **SARIF reporting**, and **GitHub Actions CI** in report-only mode — visibility without blocking delivery.
---
🔍 Quality Assurance & Static Analysis
Tool	Role
![PSScriptAnalyzer](https://img.shields.io/badge/PSScriptAnalyzer-ON-blueviolet?style=flat-square&logo=powershell)	PowerShell linting — runtime safety and best-practice enforcement
![Gitleaks](https://img.shields.io/badge/Gitleaks-ON-red?style=flat-square&logo=github)	Secret scanning — prevents credential leaks at commit time
![Prettier](https://img.shields.io/badge/Prettier-ON-ff69b4?style=flat-square&logo=prettier)	Markdown and web-asset formatting consistency
![EditorConfig](https://img.shields.io/badge/EditorConfig-ON-blue?style=flat-square&logo=editorconfig)	Cross-editor formatting standardization
![NuGet](https://img.shields.io/badge/NuGet-SHA256-blue?style=flat-square&logo=nuget)	Integrity-verified package releases
![CodeQL](https://img.shields.io/badge/CodeQL-Static%20Analysis-purple?style=flat-square&logo=github)	Deep static security analysis
> CI findings inform controlled remediation cycles — **non-blocking by design, signal-rich by intent**.
---
🌐 Language Composition
Language	Share	Primary Use
PowerShell	96.7%	Automation, IAM, DFIR, ITSM provisioning
VBScript	1.3%	Legacy workstation automation
HTML	0.6%	GUI components and report templates
T-SQL	0.4%	WSUS SUSDB maintenance queries
Java / PHP / Other	0.6%	AD LDAP / SSO integration examples
---
📚 Research Foundation & Citation
![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.18487320-blue?style=for-the-badge&logo=zenodo)
![CITATION.cff](https://img.shields.io/badge/CITATION.cff-Available-informational?style=for-the-badge)
![ORCID](https://img.shields.io/badge/ORCID-0000--0003--3705--7468-A6CE39?style=for-the-badge&logo=orcid)
Suitable for academic, technical, and policy-oriented citation across cybersecurity engineering, DFIR, IAM, IT governance, and ITSM-aligned infrastructure management.
Citation (APA):
> Roberto da Silva, L. H. (2026). *Windows-SysAdmin-ProSuite* (Version 1.8.8) [Computer software]. Zenodo. https://doi.org/10.5281/zenodo.18487320
Selected publications:
Roberto da Silva, L. H. (2025). SQL Syntax Models for Building Parsers to Query Event Logs in EVTX Format. Revista FT — Computer Science, Vol. 29, Issue 142. DOI: 10.69849/revistaft/th102502121360
Roberto da Silva, L. H. (2024). Event Logs: Applying a Log Analysis Model for Auditing Event Record Registration. Sorian Editora. ISBN: 978-65-5453-366-9
Roberto da Silva, L. H. (2009). Computer Networking Technology: Using GPOs to Secure Corporate Domains. Ciência Moderna.
---
👤 Author & Stewardship
Luiz Hamilton Silva — `@brazilianscriptguy`
Senior IAM Analyst · Identity & Access Management · AD & Azure AD · Windows Server Architect · PowerShell Automation · Digital Forensics Researcher
![LinkedIn](https://img.shields.io/badge/LinkedIn-brazilianscriptguy-0077B5?style=for-the-badge&logo=linkedin)
![YouTube](https://img.shields.io/badge/YouTube-@brazilianscriptguy-FF0000?style=for-the-badge&logo=youtube)
![X](https://img.shields.io/badge/X-@brazscriptguy-000000?style=for-the-badge&logo=x)
![ORCID](https://img.shields.io/badge/ORCID-0000--0003--3705--7468-A6CE39?style=for-the-badge&logo=orcid)
> This project reflects years of operational use, continuous refinement in production environments, and a commitment to principled, auditable systems engineering.
---
🤝 Contributing & Reuse
Contributions are welcome. Please review `CONTRIBUTING.md` before submitting a pull request.
Pull requests — bug fixes, documentation improvements, and new tools aligned with the suite's principles
Attribution — required under the MIT License for any reuse or derivative work
Academic / institutional reuse — please cite the repository DOI or the `CITATION.cff` file
Security disclosures — follow the `SECURITY.md` responsible disclosure process
---
📬 Contact & Support
![Email](https://img.shields.io/badge/Email-luizhamilton.lhr%40gmail.com-D14836?style=for-the-badge&logo=gmail)
![Patreon](https://img.shields.io/badge/Patreon-Support-red?style=for-the-badge&logo=patreon)
![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Support-yellow?style=for-the-badge&logo=buymeacoffee)
![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-29ABE0?style=for-the-badge&logo=kofi)
![GoFundMe](https://img.shields.io/badge/GoFundMe-Support-00B964?style=for-the-badge&logo=gofundme)
![WhatsApp](https://img.shields.io/badge/WhatsApp-PowerShellBR-25D366?style=for-the-badge&logo=whatsapp)
---
> *"Engineering secure, auditable, and scalable Windows automation for enterprise and public-sector environments — grounded in operational practice and peer-reviewed research."*
© 2026 Luiz Hamilton Silva · MIT License · CHANGELOG · CITATION
---
<!-- ATS Keywords -->
PowerShell automation · Windows Server administration · Active Directory · Azure AD · DNS · DHCP · WSUS · Group Policy (GPO) · PKI · certificate management · Identity & Access Management (IAM) · ITSM provisioning · security hardening · credential hygiene · digital forensics · DFIR · EVTX log analysis · event correlation · incident response · CI/CD · GitHub Actions · PSScriptAnalyzer · NuGet · SHA256 · SARIF · CodeQL · secure DevOps · modular architecture · enterprise scripting · Windows infrastructure automation
