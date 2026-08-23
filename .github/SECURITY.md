# Security Policy

Windows-SysAdmin-ProSuite contains enterprise administration and security automation for Windows environments, including PowerShell, VBScript, Active Directory, IAM, AD CS/PKI, Group Policy, WSUS/SUSDB, Windows Server, ITSM, Blue Team, and DFIR components.

This policy defines supported project scope, vulnerability reporting, disclosure expectations, and repository security controls.

---

## Supported Project Scope

Security reports are accepted for the repository's 10 functional Suite Modules:

| Module | Security-Relevant Scope |
|---|---|
| `ADCS-Management-Tools` | AD CS, CA administration, certificates, PKI lifecycle, repository handling |
| `AD-SSO-Integrations` | LDAP/LDAPS, SSO, authentication integration, credential/configuration handling |
| `BlueTeam-Tools` | Monitoring, DFIR, incident response, forensic collection |
| `Core-ScriptLibrary` | Shared PowerShell framework, packaging, reusable execution patterns |
| `GPO-Templates` | Group Policy, security baselines, domain/forest configuration |
| `ITSM-Templates-SVR` | Windows Server provisioning, maintenance, hardening, lifecycle operations |
| `ITSM-Templates-WKS` | Windows workstation provisioning, maintenance, hardening, lifecycle operations |
| `ProSuite-Hub` | Tool discovery, GUI launch/orchestration, execution routing |
| `SysAdmin-Tools` | AD, DNS, DHCP, RDS, infrastructure and system administration |
| `WSUS-Management-Tools` | WSUS, Windows Update infrastructure, SUSDB, WID/SQL maintenance |

The aggregate `All-Repository-Files` and `READMEs-Files-Package` distributions inherit the security status of the components and documentation they contain.

Repository CI/CD, release automation, packaging metadata, GitHub Actions, secret-scanning configuration, and supply-chain controls are also in scope.

---

## Supported Releases

Security fixes are prioritized for the **current `main` branch and the latest published release artifacts**.

Older generated component releases may be replaced or superseded by newer builds. Unless a release is explicitly identified as supported, users should upgrade to the latest available repository state or release package before requesting a backport.

The project does not guarantee long-term security maintenance for historical release artifacts.

---

## Platform Compatibility and Security Support

Compatibility varies by module and underlying Microsoft platform.

The project is **Windows PowerShell 5.1-first** unless a component explicitly documents another runtime requirement.

Security support does not override Microsoft lifecycle status. A platform or dependency that is no longer supported by its vendor may receive only best-effort project assistance.

Users are responsible for validating vendor support, patch level, prerequisites, backup/recovery readiness, and change-control requirements in their own environments.

---

## Reporting a Vulnerability

Do **not** open a public GitHub Issue for a suspected vulnerability.

Report security concerns privately to:

**luizhamilton.lhr@gmail.com**

Include, when applicable:

- Affected module, script, workflow, package, or repository path
- Affected release/tag/commit
- Technical description
- Reproduction steps or proof of concept
- Preconditions and required privileges
- Potential confidentiality, integrity, or availability impact
- Sanitized logs, screenshots, or traces
- Suggested remediation, if known

Do not send live passwords, production tokens, private keys, sensitive personal data, or unnecessary confidential material.

---

## Response and Disclosure

The maintainer will make reasonable efforts to:

1. Acknowledge a credible report within **3 business days**.
2. Validate and assess the issue.
3. Determine affected components and release artifacts.
4. Develop a fix, mitigation, or documented workaround where feasible.
5. Update affected documentation, CHANGELOG entries, workflows, or release artifacts as appropriate.

Complex vulnerabilities, upstream dependency issues, or infrastructure-specific problems may require additional time.

Please avoid public disclosure until a fix, mitigation, or coordinated disclosure plan is available.

---

## Security Engineering Controls

### Static Analysis and Quality Controls

- PSScriptAnalyzer
- SARIF reporting and GitHub code scanning
- CodeQL where applicable
- EditorConfig and Prettier
- VBScript validation where applicable

### Secret and Credential Controls

- Gitleaks scanning
- Narrow allowlists for explicit documentation placeholders
- Policy prohibiting hardcoded production credentials and private key material
- Ignore/package rules for common secret-bearing files

### Release and Supply-Chain Controls

- Canonical 12-package release taxonomy
- Component-specific CHANGELOG extraction
- Scoped GitHub Actions permissions
- ZIP artifact generation
- SHA256 integrity manifests
- MIT license inclusion in distributed software artifacts
- Deterministic package naming and release traceability

### Administrative Safety Controls

- Windows PowerShell 5.1 compatibility baseline
- Explicit change intent for state-changing operations
- Prerequisite/dependency validation
- Least-privilege execution
- Structured logging/reporting
- Post-change verification
- Idempotent or repeatable behavior where practical
- Recovery/rollback consideration for high-impact changes

---

## Security-Sensitive Repository Areas

Additional scrutiny is expected for changes involving Active Directory privileges, AD CS/private keys/certificates, LDAP/SSO, GPO security baselines, WSUS/SUSDB maintenance, remote execution, secrets/tokens, GitHub Actions permissions, package publication, release automation, and DFIR evidence handling.

---

## Security Resources

- [Repository](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite)
- [ADCS-Management-Tools](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools/ADCS-Management-Tools)
- [AD-SSO-Integrations](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools/ActiveDirectory-SSO-Integrations)
- [BlueTeam-Tools](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/BlueTeam-Tools)
- [Core-ScriptLibrary](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/Core-ScriptLibrary)
- [GPO-Templates](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools/GroupPolicyObjects-Templates)
- [ITSM-Templates-SVR](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-SVR)
- [ITSM-Templates-WKS](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-WKS)
- [ProSuite-Hub](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ProSuite-Hub)
- [SysAdmin-Tools](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools)
- [WSUS-Management-Tools](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools/WSUS-Management-Tools)
- [MIT License](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/LICENSE.txt)
- [CHANGELOG](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/CHANGELOG.md)

---

## Policy Version History

| Version | Date | Changes |
|---|---|---|
| 4.0 | 2026-08-23 | Aligned security scope with 10 functional modules, 12-package release governance, AD CS/PKI, WSUS/SUSDB, supply-chain controls, and current repository engineering standards |
| 3.0 | 2026-02-03 | Refreshed tag/release support policy and CI/security measures |
| 2.8 | 2025-07-21 | Added Active Directory integration tooling |
| 1.2 | 2024-04-27 | Updated support tables and repository links |
| 1.1 | 2023-06-15 | Added templates and Core library |
| 1.0 | 2023-01-01 | Initial policy |

---

Copyright (c) 2026 Luiz Hamilton Roberto da Silva.

Windows-SysAdmin-ProSuite is distributed under the repository-wide [MIT License](../LICENSE.txt).
