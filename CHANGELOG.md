# Changelog

All notable repository changes are documented in this file.

> **Compatibility note:** The `## <Component-Name>` headings are
> intentionally preserved because the GitHub Actions release workflow
> uses these second-level headings to locate component-specific
> changelog content. Do not rename them or demote them to `###` without
> updating the release workflow parser.

------------------------------------------------------------------------

## AD-SSO-APIs-Integration

### Added

-   Delivered reusable **Active Directory LDAP / SSO integration
    patterns** for enterprise applications and services.
-   Added implementation samples for **PHP, .NET, Python/Flask, Node.js,
    and Spring Boot**.
-   Added per-platform README documentation covering prerequisites,
    configuration, integration flow, and operational guidance.

### Changed

-   Standardized integration templates for **modularity, portability,
    maintainability, and cross-platform deployment**.
-   Separated authentication logic, environment-specific configuration,
    and sensitive credential material.

### Security

-   Standardized **secure bind** patterns using environment variables
    and externalized configuration.
-   Removed the need for hardcoded credentials in reference
    implementations.
-   Reinforced encrypted directory communication and least-privilege
    service access where applicable.

------------------------------------------------------------------------

## ADCS-Management-Tools

### Added

-   Established **ADCS-Management-Tools** as a first-class repository
    component for **Active Directory Certificate Services (AD CS),
    enterprise PKI, certificate lifecycle management, and certificate
    repository administration**.
-   Added `Manage-PKICertificateLifecycle-Tool.ps1` for centralized PKI
    certificate lifecycle operations.
-   Added `Cleanup-CertificateAuthority-Tool.ps1` for Certificate
    Authority cleanup and maintenance.
-   Added `Cleanup-Repository-ExpiredCertificates-Tool.ps1` for
    controlled cleanup of expired certificates from certificate
    repositories.
-   Added `Purge-ExpiredInstalledCertificates-Tool.ps1` for remediation
    of expired certificates installed on managed Windows systems.
-   Added `Organize-CERTs-Repository.ps1` for certificate repository
    organization and lifecycle management.
-   Added dedicated README documentation for AD CS and PKI
    administration.

### Changed

-   Consolidated AD CS, PKI, certificate cleanup, repository
    organization, and certificate lifecycle tooling into the dedicated
    **ADCS-Management-Tools** component.
-   Moved certificate-management scripts previously distributed under
    other `SysAdmin-Tools` areas into the dedicated AD CS component.
-   Separated PKI and certificate-services administration from general
    Windows security and optimization tooling.
-   Standardized the component around certificate discovery, validation,
    cleanup, lifecycle management, repository maintenance, and
    operational traceability.

### Security

-   Reinforced least-privilege and auditable execution for PKI and
    Certificate Authority administration.
-   Reinforced controlled handling of certificates, certificate stores,
    private keys, CA configuration, and related PKI artifacts.
-   Promoted validation-first execution and explicit safeguards for
    certificate cleanup, purge, and repository-maintenance operations.

------------------------------------------------------------------------

## All-Repository-Files

### Added

-   Created a consolidated archive containing the repository's principal
    components.
-   Included root-level `README.md` and `LICENSE.txt`.
-   Added an offline-ready distribution model for controlled deployment,
    archival, migration, and recovery use cases.
-   Included `ADCS-Management-Tools`, `BlueTeam-Tools`,
    `Core-ScriptLibrary`, `ITSM-Templates-WKS`, `ITSM-Templates-SVR`,
    and `SysAdmin-Tools`.

### Changed

-   Aligned the packaged directory structure with automated staging and
    release workflows.
-   Preserved logical separation between PKI, security, administration,
    infrastructure, ITSM, and shared framework components.
-   Improved repository portability and repeatable distribution.
- Update All-Certificates-Install.vbs (`4eff651`)

### Security

-   Preserved security-oriented component boundaries in consolidated
    repository distributions.

------------------------------------------------------------------------

## BlueTeam-Tools

### Added

-   Delivered a modular **PowerShell toolkit for Blue Team, defensive
    security, incident response, and DFIR operations**.
-   Added `EventLogMonitoring` components for Windows security
    visibility, audit analysis, and investigation.
-   Added `IncidentResponse` helpers for collection, triage, evidence
    gathering, and investigation workflows.
-   Added structured and CSV-compatible output patterns where
    applicable.
-   Added module-level README documentation describing purpose,
    prerequisites, execution, and scope.

### Changed

-   Standardized logging and reporting patterns across applicable
    security tooling.
-   Improved modular separation between monitoring, triage, collection,
    and investigation functions.
-   Improved repeatability and operational traceability of Windows
    security-analysis workflows.

### Security

-   Expanded defensive automation supporting security-event analysis and
    incident-response activities.
-   Reinforced auditable execution patterns for privileged or
    investigation-related operations where applicable.

------------------------------------------------------------------------

## Core-ScriptLibrary

### Added

-   Built a reusable **PowerShell foundation** shared across repository
    toolsets.
-   Added common helpers, execution patterns, reusable components, and
    scaffolding utilities.
-   Added **NuGet packaging assets** and package-publication support.
-   Added release and staging automation support modules.
-   Added dedicated documentation for `Modular-PS1-Scripts` and
    `Nuget-Package-Publisher`.

### Changed

-   Centralized reusable functionality to reduce duplication across tool
    suites.
-   Standardized script structure and common execution behavior.
-   Improved maintainability, extensibility, packaging, release
    readiness, validation, and operational consistency.

### Security

-   Promoted reusable validation and controlled execution patterns for
    dependent administrative scripts.

------------------------------------------------------------------------

## GPOs-Templates

### Added

-   Delivered reusable **Group Policy Object templates** for Active
    Directory domain and forest governance.
-   Added policy templates supporting security baselines, compliance
    enforcement, configuration control, and administrative
    standardization.
-   Added dedicated README documentation covering scope, prerequisites,
    usage, and operational considerations.

### Changed

-   Structured templates for controlled GPO **backup, export, import,
    migration, and lifecycle management**.
-   Improved separation between reusable policy definitions and
    environment-specific configuration.
-   Standardized organization for repeatable use across domains,
    deployments, and migrations.

### Security

-   Expanded reusable policy patterns supporting Windows security
    configuration and governance.

------------------------------------------------------------------------

## ITSM-Templates-SVR

### Added

-   Delivered **Windows Server standardization and automation
    templates** aligned with ITSM operational practices.
-   Added automation supporting provisioning, configuration, validation,
    maintenance, and operational readiness.
-   Added suite-level documentation covering requirements, execution
    guidance, and scope boundaries.

### Changed

-   Standardized server automation for predictable and repeatable
    execution.
-   Improved baseline enforcement, configuration consistency,
    operational auditability, prerequisite validation, and post-change
    verification.

### Security

-   Incorporated server hardening and security-oriented configuration
    controls where applicable.
-   Reinforced least-privilege and controlled administrative execution
    principles.

------------------------------------------------------------------------

## ITSM-Templates-WKS

### Added

-   Delivered **Windows 10/11 workstation standardization templates**
    aligned with ITSM lifecycle operations.
-   Added automation supporting provisioning, configuration,
    maintenance, baseline enforcement, and compliance.
-   Added UX and desktop-layout standardization components where
    applicable.
-   Added suite-level README documentation covering deployment and
    operational usage.

### Changed

-   Standardized recurring workstation administration workflows.
-   Improved repeatability, predictability, configuration consistency,
    validation-first execution, and reporting across managed endpoints.
- Update All-Certificates-Install.vbs (`4eff651`)

### Security

-   Added configuration controls intended to reduce workstation
    configuration drift and improve endpoint security posture.

------------------------------------------------------------------------

## READMEs-Files-Package

### Added

-   Extracted and centralized README documentation across top-level
    suites and submodules.
-   Added `main-README.md` as the centralized documentation entry point.
-   Added a portable documentation archive for offline consultation and
    controlled distribution.
- Revise README for clarity and updated features (`afd5ff8`)

### Changed

-   Standardized README naming for consistent discovery and indexing.
-   Improved documentation navigation, organization, maintainability,
    prerequisites, scope, usage guidance, and operational-boundary
    documentation.
-   Expanded documentation coverage across API/SSO integrations, AD
    CS/PKI, Blue Team/DFIR, core PowerShell components, ITSM templates,
    system administration, packaging, and publishing utilities.
- Update module count and descriptions in README (`72e3b01`)

### Security

-   Improved documentation of security-sensitive prerequisites and
    operational boundaries where applicable.

------------------------------------------------------------------------

## SysAdmin-Tools

### Added

-   Delivered a comprehensive **PowerShell automation suite for Windows
    systems and infrastructure administration**.
-   Added `ActiveDirectory-Management` tooling for directory
    administration and object lifecycle operations.
-   Added `Network-and-Infrastructure-Management` tooling for Windows
    network and infrastructure services.
-   Added `WSUS-Management-Tools` for WSUS cleanup, maintenance, and
    operational administration.
-   Added `SystemConfiguration-and-Deployment` tooling for repeatable
    Windows configuration and deployment workflows.
-   Added `Security-and-Process-Optimization` tooling for security
    configuration, maintenance, and system optimization.
-   Added documentation covering script purpose, prerequisites,
    execution requirements, and administrative scope.

### Changed

-   Improved modular separation between **identity, infrastructure,
    deployment, security, and maintenance functions**.
-   Standardized automation around repeatability, structured logging,
    operational visibility, prerequisite validation, post-change
    verification, and predictable execution.
-   Improved maintainability through functional separation and reusable
    administrative patterns.
-   Moved AD CS and PKI-specific functionality into the independent
    `ADCS-Management-Tools` component.

### Security

-   Expanded Windows administrative security and optimization
    capabilities.
-   Reinforced secure credential handling, least privilege, auditable
    privileged operations, and safeguards for potentially disruptive
    operations.

------------------------------------------------------------------------

## Enterprise-Engineering-Standards

### Added

-   Established repository-wide architecture, security, reliability,
    compatibility, and documentation principles.
-   Established modular, suite-based architecture and reusable
    PowerShell execution patterns.

### Changed

-   Reinforced separation of concerns between identity,
    **PKI/certificate services**, infrastructure, security, deployment,
    ITSM, and documentation.
-   Standardized prerequisite validation, deterministic and idempotent
    behavior where practical, actionable errors, post-change validation,
    and structured logging.
-   Standardized component-specific compatibility and production-impact
    documentation requirements.

### Security

-   Prohibited hardcoded production credentials and secrets.
-   Promoted externalized configuration, encrypted transport, least
    privilege, auditability, and secure handling of certificates,
    private keys, CA configuration, and PKI artifacts.

------------------------------------------------------------------------

## Release-Governance

### Added

-   Established repository-wide change classification covering **Added,
    Changed, Deprecated, Removed, Fixed, Security, Reliability, and
    Documentation**.
-   Established Semantic Versioning guidance using `MAJOR.MINOR.PATCH`
    where the release model permits it.
-   Established breaking-change, deprecation, migration, and
    production-release documentation requirements.

### Changed

-   Standardized release documentation to capture release identifiers,
    dates, functionality, behavioral changes, fixes, compatibility
    impact, migration requirements, and documentation changes.
-   Preserved `## <Component-Name>` headings as the component contract
    consumed by the GitHub Actions release workflow.

### Security

-   Required security-sensitive and production-impacting changes to be
    documented explicitly in applicable release information.

------------------------------------------------------------------------

## Repository-Scope

### Added

-   Defined repository coverage for **Active Directory & Identity
    Management**, **AD CS & Enterprise PKI**, **Certificate Lifecycle &
    Repository Management**, LDAP/SSO integration, IAM, Windows
    PowerShell automation, Windows Server, Windows 10/11, Group Policy,
    Blue Team/DFIR, incident response, infrastructure, WSUS, deployment,
    ITSM, packaging, release automation, and technical documentation.

### Changed

-   Expanded repository scope to recognize **ADCS-Management-Tools** and
    enterprise PKI as independent first-class capabilities.

### Security

-   Recognized PKI, certificate lifecycle management, defensive
    security, Group Policy, and Windows administration as explicit
    security-relevant repository domains.
