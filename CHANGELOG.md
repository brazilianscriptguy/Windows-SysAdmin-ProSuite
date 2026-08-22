# Changelog

All notable repository changes are documented in this file.

> **Compatibility note:** The `## <Component-Name>` headings are part of the GitHub Actions release contract. The repository currently manages **12 distribution packages**: 10 functional Suite Modules plus `All-Repository-Files` and `READMEs-Files-Package`. Each managed package must preserve exactly the `### Added`, `### Changed`, and `### Security` subsections unless the release workflow parser is updated in the same change.

---

## ADCS-Management-Tools

### Added

- Established **ADCS-Management-Tools** as a first-class repository component for **Active Directory Certificate Services (AD CS), enterprise PKI, certificate lifecycle management, and certificate repository administration**.
- Added `Manage-PKICertificateLifecycle-Tool.ps1` for centralized PKI certificate lifecycle operations.
- Added `Cleanup-CertificateAuthority-Tool.ps1` for Certificate Authority cleanup and maintenance.
- Added `Cleanup-Repository-ExpiredCertificates-Tool.ps1` for controlled cleanup of expired certificates from certificate repositories.
- Added `Purge-ExpiredInstalledCertificates-Tool.ps1` for remediation of expired certificates installed on managed Windows systems.
- Added `Organize-CERTs-Repository.ps1` for certificate repository organization and lifecycle management.
- Added dedicated README documentation for AD CS and enterprise PKI administration.

### Changed

- Consolidated AD CS, PKI, certificate cleanup, repository organization, and certificate lifecycle tooling into the dedicated **ADCS-Management-Tools** component.
- Moved certificate-management functionality previously distributed under other `SysAdmin-Tools` areas into the dedicated AD CS component.
- Standardized the component around certificate discovery, validation, cleanup, lifecycle management, repository maintenance, and operational traceability.
- Aligned the component name with the canonical Suite Modules, CHANGELOG, release-tag, ZIP, SHA256, and GitHub Release taxonomy.

### Security

- Reinforced least-privilege and auditable execution for PKI and Certificate Authority administration.
- Reinforced controlled handling of certificates, certificate stores, private keys, CA configuration, and related PKI artifacts.
- Promoted validation-first execution and explicit safeguards for certificate cleanup, purge, and repository-maintenance operations.

---

## AD-SSO-Integrations

### Added

- Delivered reusable **Active Directory LDAP / SSO integration patterns** for enterprise applications and services.
- Added implementation samples for **PHP, .NET, Python/Flask, Node.js, and Spring Boot**.
- Added per-platform README documentation covering prerequisites, configuration, integration flow, and operational guidance.

### Changed

- Renamed the managed release identity from `AD-SSO-APIs-Integration` to the canonical **AD-SSO-Integrations** name used by the Suite Modules catalog.
- Standardized integration templates for **modularity, portability, maintainability, and cross-platform deployment**.
- Separated authentication logic, environment-specific configuration, and sensitive credential material.
- Aligned CHANGELOG headings, workflow detection, release tags, artifacts, and repository links with the canonical component name.

### Security

- Standardized **secure bind** patterns using environment variables and externalized configuration.
- Removed the need for hardcoded credentials in reference implementations.
- Reinforced encrypted directory communication and least-privilege service access where applicable.

---

## All-Repository-Files

### Added

- Created a consolidated archive containing the repository's principal components and distribution assets.
- Included root-level `README.md`, `LICENSE.txt`, and applicable release metadata.
- Added an offline-ready distribution model for controlled deployment, archival, migration, recovery, and administrative use cases.
- Consolidated the complete functional module set:
  - `ADCS-Management-Tools`
  - `AD-SSO-Integrations`
  - `BlueTeam-Tools`
  - `Core-ScriptLibrary`
  - `GPO-Templates`
  - `ITSM-Templates-SVR`
  - `ITSM-Templates-WKS`
  - `ProSuite-Hub`
  - `SysAdmin-Tools`
  - `WSUS-Management-Tools`

### Changed

- Aligned the packaged directory structure with the canonical **12-package** GitHub Actions release model.
- Preserved logical separation between identity, PKI, security, administration, infrastructure, endpoint/server lifecycle, WSUS, ITSM, and shared framework components.
- Improved repository portability, deterministic packaging, and repeatable distribution.
- Updated consolidated distribution behavior to include `ProSuite-Hub` and the dedicated `WSUS-Management-Tools` component.
- Updated certificate-related distribution content, including `All-Certificates-Install.vbs`, where applicable.

### Security

- Preserved security-oriented component boundaries in consolidated repository distributions.
- Reinforced integrity validation through SHA256 manifests generated by the release workflow.

---

## BlueTeam-Tools

### Added

- Delivered a modular **PowerShell toolkit for Blue Team, defensive security, incident response, and DFIR operations**.
- Added `EventLogMonitoring` components for Windows security visibility, audit analysis, and investigation.
- Added `IncidentResponse` helpers for collection, triage, evidence gathering, and investigation workflows.
- Added structured and CSV-compatible output patterns where applicable.
- Added module-level README documentation describing purpose, prerequisites, execution, and scope.

### Changed

- Standardized logging and reporting patterns across applicable security tooling.
- Improved modular separation between monitoring, triage, collection, and investigation functions.
- Improved repeatability and operational traceability of Windows security-analysis workflows.
- Aligned package naming and release handling with the canonical Suite Modules taxonomy.

### Security

- Expanded defensive automation supporting security-event analysis and incident-response activities.
- Reinforced auditable execution patterns for privileged or investigation-related operations where applicable.

---

## Core-ScriptLibrary

### Added

- Built a reusable **PowerShell foundation** shared across repository toolsets.
- Added common helpers, execution patterns, reusable components, and scaffolding utilities.
- Added **NuGet packaging assets** and package-publication support.
- Added release and staging automation support modules.
- Added dedicated documentation for `Modular-PS1-Scripts` and `Nuget-Package-Publisher`.

### Changed

- Centralized reusable functionality to reduce duplication across tool suites.
- Standardized script structure and common execution behavior.
- Improved maintainability, extensibility, packaging, release readiness, validation, and operational consistency.
- Aligned release packaging with the canonical 12-package distribution architecture.

### Security

- Promoted reusable validation and controlled execution patterns for dependent administrative scripts.
- Reinforced integrity-oriented packaging and release processes.

---

## GPO-Templates

### Added

- Delivered reusable **Group Policy Object templates** for Active Directory domain and forest governance.
- Added policy templates supporting security baselines, compliance enforcement, configuration control, and administrative standardization.
- Added dedicated README documentation covering scope, prerequisites, usage, and operational considerations.

### Changed

- Renamed the managed release identity from `GPOs-Templates` to the canonical **GPO-Templates** name used by the Suite Modules catalog.
- Structured templates for controlled GPO **backup, export, import, migration, and lifecycle management**.
- Improved separation between reusable policy definitions and environment-specific configuration.
- Standardized organization for repeatable use across domains, deployments, and migrations.
- Aligned CHANGELOG headings, workflow detection, release tags, artifacts, and repository links with the canonical component name.

### Security

- Expanded reusable policy patterns supporting Windows security configuration and governance.
- Reinforced controlled policy deployment and administrative traceability.

---

## ITSM-Templates-SVR

### Added

- Delivered **Windows Server standardization and automation templates** aligned with ITSM operational practices.
- Added automation supporting provisioning, configuration, validation, maintenance, and operational readiness.
- Added suite-level documentation covering requirements, execution guidance, and scope boundaries.

### Changed

- Standardized server automation for predictable and repeatable execution.
- Improved baseline enforcement, configuration consistency, operational auditability, prerequisite validation, and post-change verification.
- Aligned release packaging and CHANGELOG handling with the canonical distribution model.

### Security

- Incorporated server hardening and security-oriented configuration controls where applicable.
- Reinforced least-privilege and controlled administrative execution principles.

---

## ITSM-Templates-WKS

### Added

- Delivered **Windows 10/11 workstation standardization templates** aligned with ITSM lifecycle operations.
- Added automation supporting provisioning, configuration, maintenance, baseline enforcement, and compliance.
- Added UX and desktop-layout standardization components where applicable.
- Added suite-level README documentation covering deployment and operational usage.

### Changed

- Standardized recurring workstation administration workflows.
- Improved repeatability, predictability, configuration consistency, validation-first execution, and reporting across managed endpoints.
- Updated applicable workstation automation assets, including `All-Certificates-Install.vbs`.
- Aligned release packaging and CHANGELOG handling with the canonical distribution model.

### Security

- Added configuration controls intended to reduce workstation configuration drift and improve endpoint security posture.
- Reinforced auditable and controlled workstation lifecycle operations.

---

## ProSuite-Hub

### Added

- Established **ProSuite-Hub** as a first-class managed release component and standalone distribution package.
- Added the centralized GUI launcher and module-orchestration role to the canonical Suite Modules taxonomy.
- Added dedicated GitHub Actions release handling for the top-level `ProSuite-Hub` repository directory.

### Changed

- Integrated `ProSuite-Hub` into CHANGELOG detection, release matrices, managed tag prefixes, ZIP generation, SHA256 manifests, and repository-link metadata.
- Standardized its package identity across documentation, release automation, and distribution governance.
- Included `ProSuite-Hub` in `All-Repository-Files`.

### Security

- Preserved explicit module boundaries so launcher/orchestration functionality does not implicitly bypass the authorization, confirmation, or safety controls of the underlying administrative tools.
- Reinforced controlled tool discovery and operator-driven execution.

---

## READMEs-Files-Package

### Added

- Extracted and centralized README documentation across top-level suites and submodules.
- Added `main-README.md` as the centralized documentation entry point.
- Added a portable documentation archive for offline consultation and controlled distribution.
- Expanded documentation coverage to include the canonical 10-module Suite Modules architecture.

### Changed

- Standardized README naming for consistent discovery and indexing.
- Improved documentation navigation, organization, maintainability, prerequisites, scope, usage guidance, and operational-boundary documentation.
- Expanded documentation coverage across **AD/SSO integrations, AD CS/PKI, Blue Team/DFIR, GPOs, WSUS/SUSDB, core PowerShell components, ITSM templates, ProSuite-Hub, system administration, packaging, and publishing utilities**.
- Updated module counts, module descriptions, badge-based module links, alphabetical module ordering, and ATS-optimized keyword layers.
- Aligned documentation terminology with the canonical Suite Modules and 12-package release model.
- Update README.md (`32ee955`)

### Security

- Improved documentation of security-sensitive prerequisites and operational boundaries where applicable.
- Reinforced accurate documentation of least privilege, credential hygiene, certificate handling, WSUS/SUSDB maintenance, and secure DevOps controls.

---

## SysAdmin-Tools

### Added

- Delivered a comprehensive **PowerShell automation suite for Windows systems and infrastructure administration**.
- Added `ActiveDirectory-Management` tooling for directory administration and object lifecycle operations.
- Added `Network-and-Infrastructure-Management` tooling for Windows network and infrastructure services.
- Added `SystemConfiguration-and-Deployment` tooling for repeatable Windows configuration and deployment workflows.
- Added `Security-and-Process-Optimization` tooling for security configuration, maintenance, and system optimization.
- Added documentation covering script purpose, prerequisites, execution requirements, and administrative scope.

### Changed

- Improved modular separation between **identity, infrastructure, deployment, security, and maintenance functions**.
- Standardized automation around repeatability, structured logging, operational visibility, prerequisite validation, post-change verification, and predictable execution.
- Improved maintainability through functional separation and reusable administrative patterns.
- Moved AD CS and PKI-specific release responsibilities into the independent `ADCS-Management-Tools` component.
- Moved WSUS-specific release responsibilities into the independent `WSUS-Management-Tools` component while preserving the physical subdirectory under `SysAdmin-Tools`.
- Preserved parent-package propagation so nested ADCS, AD/SSO, GPO, and WSUS changes also update the `SysAdmin-Tools` and `All-Repository-Files` distributions.

### Security

- Expanded Windows administrative security and optimization capabilities.
- Reinforced secure credential handling, least privilege, auditable privileged operations, and safeguards for potentially disruptive operations.
- Reinforced component isolation for specialized PKI, SSO, Group Policy, and WSUS administrative workflows.

---

## WSUS-Management-Tools

### Added

- Established **WSUS-Management-Tools** as a first-class managed release component for **Windows Server Update Services administration, maintenance, auditing, and SUSDB optimization**.
- Added `Check-WSUS-AdminAssembly.ps1` for validation of Microsoft WSUS Administration API availability.
- Added `Generate-WSUS-ReindexScript.ps1` for SUSDB SQL reindexing and database-maintenance generation.
- Added `Inventory-WSUS-Environment.ps1` for WSUS server, service, database, and supporting-component inventory.
- Added `Inventory-WSUSConfigs-Tool.ps1` for WSUS configuration, patch-state, repository, and operational assessment.
- Added `Maintenance-WSUS-Admin-Tool.ps1` for consolidated WSUS maintenance, cleanup, inventory export, SQL generation, and WID/SQL database operations.
- Added dedicated README documentation for WSUS administration and SUSDB maintenance.

### Changed

- Promoted WSUS from a capability documented only beneath `SysAdmin-Tools` to an independent **WSUS-Management-Tools** release identity.
- Integrated `WSUS-Management-Tools` into CHANGELOG detection, managed tag prefixes, release matrices, ZIP generation, SHA256 manifests, GitHub Releases, and repository-link metadata.
- Standardized the module around WSUS inventory, configuration auditing, cleanup, API validation, WID/SQL maintenance, and SUSDB reindexing.
- Preserved parent-package propagation so WSUS changes also update `SysAdmin-Tools` and `All-Repository-Files`.
- Aligned module documentation and ATS terminology with Windows Server Update Services, patch management, SUSDB, WID, SQL Server, and Windows Update infrastructure.

### Security

- Reinforced validation-first execution for WSUS and SUSDB administrative operations.
- Reinforced change-control safeguards around cleanup, database maintenance, and potentially disruptive update-services operations.
- Promoted pre-maintenance inventory, recovery readiness, operational logging, and post-change validation.
- Reinforced auditable administration and least-privilege handling of WSUS infrastructure where applicable.

---

## Enterprise-Engineering-Standards

### Added

- Established repository-wide architecture, security, reliability, compatibility, and documentation principles.
- Established modular, suite-based architecture and reusable PowerShell execution patterns.
- Established a canonical distinction between **10 functional Suite Modules** and **2 aggregate distribution packages**.

### Changed

- Reinforced separation of concerns between identity, **PKI/certificate services**, infrastructure, Group Policy, WSUS/update services, security, deployment, ITSM, documentation, and orchestration.
- Standardized prerequisite validation, deterministic and idempotent behavior where practical, actionable errors, post-change validation, and structured logging.
- Standardized component-specific compatibility and production-impact documentation requirements.
- Aligned repository engineering terminology with the canonical 12-package distribution model.

### Security

- Prohibited hardcoded production credentials and secrets.
- Promoted externalized configuration, encrypted transport, least privilege, auditability, and secure handling of certificates, private keys, CA configuration, PKI artifacts, and administrative credentials.
- Reinforced validation and recovery considerations for potentially disruptive infrastructure operations.

---

## Release-Governance

### Added

- Established repository-wide change classification using the canonical **Added**, **Changed**, and **Security** sections for managed package CHANGELOG entries.
- Established Semantic Versioning guidance using `MAJOR.MINOR.PATCH` where the release model permits it.
- Established breaking-change, migration, and production-release documentation requirements.
- Established **12 managed distribution packages** consisting of 10 functional modules plus 2 aggregate packages.

### Changed

- Standardized release documentation to capture functionality, behavioral changes, security impact, compatibility impact, and migration requirements.
- Preserved `## <Component-Name>` headings as the component contract consumed by GitHub Actions.
- Standardized canonical release identities to:
  - `ADCS-Management-Tools`
  - `AD-SSO-Integrations`
  - `All-Repository-Files`
  - `BlueTeam-Tools`
  - `Core-ScriptLibrary`
  - `GPO-Templates`
  - `ITSM-Templates-SVR`
  - `ITSM-Templates-WKS`
  - `ProSuite-Hub`
  - `READMEs-Files-Package`
  - `SysAdmin-Tools`
  - `WSUS-Management-Tools`
- Aligned managed tag prefixes, matrix entries, CHANGELOG headings, ZIP names, SHA256 manifests, GitHub Release names, and repository links to the same canonical taxonomy.

### Security

- Required security-sensitive and production-impacting changes to be documented explicitly.
- Reinforced controlled release ownership so automated cleanup affects only recognized managed tag prefixes.

---

## Repository-Scope

### Added

- Defined repository coverage for **Active Directory & Identity Management**, **AD CS & Enterprise PKI**, **Certificate Lifecycle & Repository Management**, **LDAP/SSO integration**, **Group Policy**, **WSUS & SUSDB**, Windows PowerShell automation, Windows Server, Windows 10/11, Blue Team/DFIR, incident response, network infrastructure, system configuration, deployment, ITSM, packaging, release automation, documentation, and module orchestration.
- Recognized `ProSuite-Hub` and `WSUS-Management-Tools` as first-class functional modules.

### Changed

- Expanded repository scope to recognize **ADCS-Management-Tools**, **AD-SSO-Integrations**, **GPO-Templates**, **ProSuite-Hub**, and **WSUS-Management-Tools** using the canonical Suite Modules taxonomy.
- Aligned repository documentation and release governance around 10 functional modules and 2 aggregate distribution packages.

### Security

- Recognized PKI, certificate lifecycle management, identity integration, Group Policy, WSUS/update infrastructure, defensive security, and Windows administration as explicit security-relevant repository domains.
- Reinforced secure DevOps, operational auditability, and controlled infrastructure-change principles across the complete repository scope.
