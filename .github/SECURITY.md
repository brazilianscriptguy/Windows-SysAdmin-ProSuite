# Security Policy

This repository contains enterprise automation toolsets for Windows environments, including PowerShell and VBScript assets.  
Security updates, supported versions, and vulnerability reporting procedures are defined below.

---

## Supported Versions

The following components of **Windows-SysAdmin-ProSuite** are actively maintained and receive security updates:

- **BlueTeam-Tools** – Security, monitoring, and incident response scripts
- **Core-ScriptLibrary** – Shared PowerShell foundations and frameworks
- **ITSM-Templates-SVR** – Server automation and ITSM compliance templates
- **ITSM-Templates-WKS** – Windows workstation configuration templates
- **SysAdmin-Tools** – Active Directory, GPO, and infrastructure management tools

---

## Release Support Policy

This repository uses **tag and release versioning**.

Only the **two most recent minor release lines** are supported at any given time.

| Release Line | Status | Notes |
|-------------|--------|-------|
| Latest minor line | ✅ Supported | Receives security fixes, improvements, and CI updates |
| Previous minor line | ✅ Supported | Receives security fixes only (best-effort) |
| Older lines | ❌ Unsupported | No guaranteed fixes; upgrade strongly recommended |

---

## Windows Compatibility

### Windows Workstations

| Version | Status | Notes |
|-------|--------|------|
| Windows 11 | ✅ Supported | Fully supported |
| Windows 10 | ✅ Supported | Fully supported |
| Windows 8.x | ❌ Unsupported | Upgrade required |
| Windows 7 | ❌ Unsupported | Upgrade required |

### Windows Server

| Version | Status | Notes |
|-------|--------|------|
| Windows Server 2022 | ✅ Supported | Full support |
| Windows Server 2019 | ✅ Supported | Full support |
| Windows Server 2016 | ⚠️ Best-effort | Older baseline |
| Windows Server 2012 | ❌ Unsupported | Upgrade required |

---

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly.

1. **Contact:**  
   Send details to **luizhamilton.lhr@gmail.com**

2. **Include:**  
   - Affected module or folder  
   - Reproduction steps (if possible)  
   - Logs, screenshots, or proof-of-concept  
   - Expected impact and severity assessment

3. **Response Time:**  
   You can expect an initial response within **3 business days**.

4. **Fixes:**  
   Confirmed vulnerabilities will be patched and released with appropriate notes and updated artifacts.

> ⚠️ **Please do not disclose vulnerabilities publicly** until a fix or mitigation has been published.

---

## Security Measures

This project applies multiple defense-in-depth measures:

- **Secure CI pipelines**  
  PowerShell SARIF, VBScript SARIF, EditorConfig, and formatting enforcement

- **Code review process**  
  Changes are reviewed when possible; CI gates reduce regressions

- **Least privilege**  
  GitHub Actions permissions are minimized and scoped per job

- **Traceability**  
  Builds generate artifacts, logs, and summaries for auditing and reproducibility

---

## Additional Resources

- **BlueTeam-Tools documentation**  
  https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/BlueTeam-Tools

- **Core-ScriptLibrary documentation**  
  https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/Core-ScriptLibrary

- **ITSM-Templates-SVR documentation**  
  https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-SVR

- **ITSM-Templates-WKS documentation**  
  https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-WKS

- **SysAdmin-Tools documentation**  
  https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools

---

## Policy Version History

| Version | Date | Changes | Author |
|-------|------|--------|--------|
| 3.0 | 2026-02-03 | Policy refresh: tag/release support lines, updated module wording, refined CI/security measures | Luiz Hamilton Silva |
| 2.8 | 2025-07-21 | Added Active Directory integration tools | Luiz Hamilton Silva |
| 1.2 | 2024-04-27 | Updated support tables and links | Luiz Hamilton Silva |
| 1.1 | 2023-06-15 | Added templates and Core library | Luiz Hamilton Silva |
| 1.0 | 2023-01-01 | Initial release | Luiz Hamilton Silva |

---

© 2026 Luiz Hamilton. All rights reserved.
