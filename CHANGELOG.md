# Changelog

All notable repository changes are documented in this file.

> **Compatibility note:** The `## <Component-Name>` headings are intentionally preserved because the GitHub Actions release workflow uses these second-level headings to locate component-specific changelog content. Do not rename them or demote them to `###` without updating the release workflow parser.

---

## AD-SSO-APIs-Integration

### Added
- Delivered reusable **Active Directory LDAP / SSO integration patterns** for enterprise applications and services.
- Added implementation samples for **PHP, .NET, Python/Flask, Node.js, and Spring Boot**.
- Added per-platform README documentation covering prerequisites, configuration, integration flow, and operational guidance.

### Changed
- Standardized integration templates for **modularity, portability, maintainability, and cross-platform deployment**.
- Separated authentication logic, environment-specific configuration, and sensitive credential material.

### Security
- Standardized **secure bind** patterns using environment variables and externalized configuration.
- Removed the need for hardcoded credentials in reference implementations.
- Reinforced encrypted directory communication and least-privilege service access where applicable.

---

## All-Repository-Files
















### 2026-08-19

#### Changed
- Move Purge-ExpiredInstalledCertificates script to ADCS tools (`ced0e50`)

### 2026-08-19

#### Changed
- Move Purge-ExpiredInstalledCertificates-Tool.ps1 to ADCS tools (`869c60b`)

### 2026-08-19

#### Changed
- Move Organize-CERTs-Repository.ps1 to ADCS tools (`722b887`)

### 2026-08-19

#### Changed
- Delete SysAdmin-Tools/ADCS-Management-Tools/Teste.ps1 (`8545774`)

### 2026-08-19

#### Added
- Add Manage-PKICertificateLifecycle-Tool.ps1 (`22724e9`)

### 2026-08-19

#### Added
- Move PKI Certificate Lifecycle Tool to a new directory (`aad475e`)

### 2026-08-19

#### Changed
- Move Cleanup-Repository-ExpiredCertificates-Tool.ps1 (`d2acd7d`)

### 2026-08-19

#### Changed
- Move Inventory-WSUSConfigs-Tool.ps1 to WSUS-Management-Tools (`1611764`)

### 2026-08-19

#### Changed
- Rename Cleanup-CertificateAuthority-Tool.ps1Cleanup-CertificateAuthority-Tool.ps1 to Cleanup-CertificateAuthority-Tool.ps1 (`81b90e6`)

### 2026-08-19

#### Security
- Rename SysAdmin-Tools/Security-and-Process-Optimization/ADCS-Management-Tools/Cleanup-CertificateAuthority-Tool.ps1 to SysAdmin-Tools/ADCS-Management-Tools/Cleanup-CertificateAuthority-Tool.ps1Cleanup-CertificateAuthority-Tool.ps1 (`078b988`)

### 2026-08-19

#### Changed
- Move Cleanup-CertificateAuthority-Tool.ps1 to ADCS-Management-Tools (`bdf8dfb`)

### 2026-08-19

#### Added
- Add Teste.ps1 file with initial content (`3deb4fe`)

### 2026-08-19

#### Changed
- Update fmt.Println message from 'Hello' to 'Goodbye' (`a6998ef`)

### 2026-08-18

#### Fixed
- Fix formatting issue at the end of the script (`28fa6d2`)

### 2026-08-18

#### Added
- Update Add-ADComputers-Pre-Staging.ps1 (`0fe4f96`)

### Added
- Created a consolidated archive containing the repository's principal components.
- Included root-level `README.md` and `LICENSE.txt`.
- Added an offline-ready distribution model for controlled deployment, archival, migration, and recovery use cases.

### Included
- `BlueTeam-Tools`
- `Core-ScriptLibrary`
- `ITSM-Templates-WKS`
- `ITSM-Templates-SVR`
- `SysAdmin-Tools`

### Changed
- Aligned the packaged directory structure with automated staging and release workflows.
- Preserved logical separation between security, administration, infrastructure, ITSM, and shared framework components.
- Improved repository portability and repeatable distribution.

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

### Security
- Expanded defensive automation supporting security-event analysis and incident-response activities.
- Reinforced auditable execution patterns for privileged or investigation-related operations where applicable.

---

## Core-ScriptLibrary


### 2026-08-18

#### Fixed
- Fix formatting issue at the end of the script (`28fa6d2`)

### Added
- Built a reusable **PowerShell foundation** shared across repository toolsets.
- Added common helpers, execution patterns, reusable components, and scaffolding utilities.
- Added **NuGet packaging assets** and package-publication support.
- Added release and staging automation support modules.
- Added dedicated documentation for:
  - `Modular-PS1-Scripts`
  - `Nuget-Package-Publisher`

### Changed
- Centralized reusable functionality to reduce duplication across tool suites.
- Standardized script structure and common execution behavior.
- Improved maintainability, extensibility, packaging, and release readiness.

### Reliability
- Promoted deterministic execution patterns and reusable validation logic where applicable.
- Improved common error-handling and operational consistency across dependent scripts.

---

## GPOs-Templates

### Added
- Delivered reusable **Group Policy Object templates** for Active Directory domain and forest governance.
- Added policy templates supporting security baselines, compliance enforcement, configuration control, and administrative standardization.
- Added dedicated README documentation covering scope, prerequisites, usage, and operational considerations.

### Changed
- Structured templates for controlled GPO **backup, export, import, migration, and lifecycle management**.
- Improved separation between reusable policy definitions and environment-specific configuration.
- Standardized organization for repeatable use across domains, deployments, and migrations.

### Security
- Expanded reusable policy patterns supporting Windows security configuration and governance.

---

## ITSM-Templates-SVR

### Added
- Delivered **Windows Server standardization and automation templates** aligned with ITSM operational practices.
- Added automation supporting provisioning, configuration, validation, maintenance, and operational readiness.
- Added suite-level documentation covering requirements, execution guidance, and scope boundaries.

### Changed
- Standardized server automation for predictable and repeatable execution.
- Improved baseline enforcement, configuration consistency, and operational auditability.
- Improved structured logging and reporting patterns where applicable.

### Security
- Incorporated server hardening and security-oriented configuration controls where applicable.
- Reinforced least-privilege and controlled administrative execution principles.

### Reliability
- Promoted prerequisite validation, post-change verification, and idempotent behavior where practical.

---

## ITSM-Templates-WKS

### Added
- Delivered **Windows 10/11 workstation standardization templates** aligned with ITSM lifecycle operations.
- Added automation supporting provisioning, configuration, maintenance, baseline enforcement, and compliance.
- Added UX and desktop-layout standardization components where applicable.
- Added suite-level README documentation covering deployment and operational usage.

### Changed
- Standardized recurring workstation administration workflows.
- Improved repeatability, predictability, and configuration consistency across managed endpoints.
- Improved structured execution and reporting patterns where supported.

### Security
- Added configuration controls intended to reduce workstation configuration drift and improve endpoint security posture.

### Reliability
- Promoted validation-first execution and predictable administrative outcomes where applicable.

---

## READMEs-Files-Package

### Added
- Extracted and centralized README documentation across top-level suites and submodules.
- Added `main-README.md` as the centralized documentation entry point.
- Added a portable documentation archive for offline consultation and controlled distribution.

### Changed
- Standardized README naming for consistent discovery and indexing.
- Improved documentation navigation, organization, and maintainability.
- Expanded documentation coverage across:
  - API and SSO integrations
  - Blue Team and DFIR tooling
  - Core PowerShell components
  - ITSM templates
  - System administration tooling
  - Packaging and publishing utilities

### Documentation
- Improved prerequisite, scope, usage, and operational-boundary documentation across supported components.

---

## SysAdmin-Tools















### 2026-08-19

#### Changed
- Move Purge-ExpiredInstalledCertificates script to ADCS tools (`ced0e50`)

### 2026-08-19

#### Changed
- Move Purge-ExpiredInstalledCertificates-Tool.ps1 to ADCS tools (`869c60b`)

### 2026-08-19

#### Changed
- Move Organize-CERTs-Repository.ps1 to ADCS tools (`722b887`)

### 2026-08-19

#### Changed
- Delete SysAdmin-Tools/ADCS-Management-Tools/Teste.ps1 (`8545774`)

### 2026-08-19

#### Added
- Add Manage-PKICertificateLifecycle-Tool.ps1 (`22724e9`)

### 2026-08-19

#### Added
- Move PKI Certificate Lifecycle Tool to a new directory (`aad475e`)

### 2026-08-19

#### Changed
- Move Cleanup-Repository-ExpiredCertificates-Tool.ps1 (`d2acd7d`)

### 2026-08-19

#### Changed
- Move Inventory-WSUSConfigs-Tool.ps1 to WSUS-Management-Tools (`1611764`)

### 2026-08-19

#### Changed
- Rename Cleanup-CertificateAuthority-Tool.ps1Cleanup-CertificateAuthority-Tool.ps1 to Cleanup-CertificateAuthority-Tool.ps1 (`81b90e6`)

### 2026-08-19

#### Security
- Rename SysAdmin-Tools/Security-and-Process-Optimization/ADCS-Management-Tools/Cleanup-CertificateAuthority-Tool.ps1 to SysAdmin-Tools/ADCS-Management-Tools/Cleanup-CertificateAuthority-Tool.ps1Cleanup-CertificateAuthority-Tool.ps1 (`078b988`)

### 2026-08-19

#### Changed
- Move Cleanup-CertificateAuthority-Tool.ps1 to ADCS-Management-Tools (`bdf8dfb`)

### 2026-08-19

#### Added
- Add Teste.ps1 file with initial content (`3deb4fe`)

### 2026-08-19

#### Changed
- Update fmt.Println message from 'Hello' to 'Goodbye' (`a6998ef`)

### 2026-08-18

#### Added
- Update Add-ADComputers-Pre-Staging.ps1 (`0fe4f96`)

### Added
- Delivered a comprehensive **PowerShell automation suite for Windows systems and infrastructure administration**.
- Added `ActiveDirectory-Management` tooling for directory administration and object lifecycle operations.
- Added `Network-and-Infrastructure-Management` tooling for Windows network and infrastructure services.
- Added `WSUS-Management-Tools` for WSUS cleanup, maintenance, and operational administration.
- Added `SystemConfiguration-and-Deployment` tooling for repeatable Windows configuration and deployment workflows.
- Added `Security-and-Process-Optimization` tooling for security configuration, maintenance, and system optimization.
- Added documentation covering script purpose, prerequisites, execution requirements, and administrative scope.

### Changed
- Improved modular separation between **identity, infrastructure, deployment, security, and maintenance functions**.
- Standardized automation around repeatability, structured logging, operational visibility, and predictable execution where applicable.
- Improved maintainability through functional separation and reusable administrative patterns.

### Security
- Expanded Windows administrative security and optimization capabilities.
- Reinforced secure credential handling, least privilege, and auditable privileged operations where applicable.

### Reliability
- Promoted prerequisite validation, clear success/warning/error states, and post-change verification.
- Promoted idempotent behavior and dry-run/validation modes for potentially disruptive operations where appropriate.

---

## Enterprise-Engineering-Standards

### Architecture
- Standardized the repository around a **modular, suite-based architecture**.
- Increased reuse of common PowerShell helpers and execution patterns.
- Reinforced separation of concerns between identity, infrastructure, security, deployment, ITSM, and documentation.

### Security
- Prohibited hardcoded production credentials and secrets.
- Promoted externalized configuration and secure credential handling.
- Reinforced encrypted transport, least privilege, and auditability for privileged workflows.
- Required security-sensitive assumptions and prerequisites to be documented.

### Reliability
- Promoted prerequisite validation before changes are applied.
- Promoted deterministic and idempotent behavior for configuration-management operations where practical.
- Required actionable errors rather than silent failure.
- Promoted post-change state validation and structured operational logging.
- Encouraged distinct discovery, validation, dry-run, remediation, and reporting execution paths where appropriate.

### Compatibility
- Required component-specific platform and dependency requirements to remain explicitly documented.
- Discouraged undocumented platform-specific dependencies.
- Required compatibility-impacting changes to be identified in release documentation.

### Documentation
- Expanded repository-wide README coverage.
- Improved documentation naming, discovery, navigation, and offline availability.
- Required production-impacting, security-sensitive, and breaking changes to be documented explicitly.

---

## Release-Governance

### Change Classification
Future release entries should use the following categories where applicable:

- **Added** — new scripts, modules, templates, integrations, or capabilities.
- **Changed** — changes to existing behavior, architecture, interfaces, defaults, or workflows.
- **Deprecated** — functionality retained temporarily but scheduled for removal or replacement.
- **Removed** — deleted features, scripts, parameters, dependencies, or behaviors.
- **Fixed** — defect, reliability, compatibility, or correctness corrections.
- **Security** — hardening, access-control, credential-handling, auditing, or vulnerability-related changes.
- **Reliability** — resiliency, validation, idempotency, error-handling, and operational-safety improvements.
- **Documentation** — material documentation additions or corrections.

### Versioning
- Use **Semantic Versioning** (`MAJOR.MINOR.PATCH`) where the release model permits it.
- Increment **MAJOR** for incompatible architectural, interface, or operational changes.
- Increment **MINOR** for backward-compatible functionality and significant enhancements.
- Increment **PATCH** for backward-compatible fixes, hardening, and minor improvements.

### Breaking Changes
Breaking changes must be explicitly identified and should include migration guidance where practical.

Examples include:
- Removal or renaming of public parameters.
- Changes to input or output formats.
- Changes to directory or configuration structures consumed by automation.
- Removal of backward compatibility.
- Authentication or authorization changes requiring administrator intervention.

### Deprecation
Deprecated functionality should:
1. Be identified explicitly.
2. Name the recommended replacement where available.
3. Remain documented during the transition period.
4. Be listed as removed when deletion occurs.
5. Include migration guidance when existing deployments are affected.

### Release Documentation
Each production release should document, where applicable:
- Release identifier or version.
- Release date.
- Added functionality.
- Behavioral changes.
- Fixes.
- Security changes.
- Reliability changes.
- Deprecated or removed functionality.
- Breaking changes.
- Compatibility impact.
- Migration requirements.
- Documentation changes.

---

## Repository-Scope

The repository currently covers:

- **Active Directory & Identity Management**
- **LDAP / SSO Application Integration**
- **Identity & Access Management (IAM)**
- **Windows PowerShell Automation**
- **Windows Server Administration**
- **Windows 10/11 Endpoint Management**
- **Group Policy Management**
- **Blue Team & DFIR Operations**
- **Windows Event Log Monitoring**
- **Incident Response**
- **Network & Infrastructure Administration**
- **WSUS Administration**
- **System Configuration & Deployment**
- **Security & Process Optimization**
- **ITSM-Oriented Standardization**
- **PowerShell Packaging & Release Automation**
- **Technical Documentation & Offline Distribution**

---

> **Maintenance note:** Component names used as `##` headings are part of the release-workflow contract. If a component is renamed, the corresponding GitHub Actions parsing logic must be updated in the same change.
