## 🛠️ ADCS Management Tools

### Certificate Hygiene · Compliance Audits · Privileged Operations

![Suite](https://img.shields.io/badge/Suite-Security%20%26%20Process%20Optimization-0A66C2?style=for-the-badge\&logo=windows\&logoColor=white) ![Scope](https://img.shields.io/badge/Scope-Certificates%20%7C%20Access%20%7C%20Storage-informational?style=for-the-badge) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207.x-5391FE?style=for-the-badge\&logo=powershell\&logoColor=white) ![Focus](https://img.shields.io/badge/Focus-Security%20Posture%20%7C%20Compliance-critical?style=for-the-badge)

---

## 🧭 Overview

The **ADCS Management Tools** suite provides **enterprise-grade PowerShell automation** for managing certificate hygiene, lifecycle governance, repository maintenance, and privileged operations across **Microsoft Active Directory Certificate Services (AD CS)** and Windows certificate environments.

These tools are designed to streamline and standardize operations such as:

* Certificate Authority database cleanup and maintenance
* Expired certificate detection and removal
* Certificate repository organization and lifecycle hygiene
* PKI certificate lifecycle management and automated revocation
* CRL publication and governance reporting
* Installed certificate remediation across Windows systems
* Group Policy-based certificate cleanup and compliance enforcement

All scripts follow the same engineering standards used across **Windows-SysAdmin-ProSuite**, ensuring **deterministic execution, structured logging, and audit-ready outputs**.

---

## 🌟 Key Features

* 🔐 **Certificate Management** — Cleanup of expired certificates and organization of shared repositories
* 📝 **Comprehensive Logging** — Structured `.log` files for traceability and diagnostics
* 📊 **Exportable Reports** — Outputs for documentation, audits, governance, and compliance
* ⚙️ **Efficient PKI Automation** — Eliminates repetitive and error-prone manual certificate-management tasks

---

## 🛠️ Prerequisites

* **⚙️ PowerShell** — Version **5.1 or later** (PowerShell 7.x supported)

  ```powershell
  $PSVersionTable.PSVersion
  ```

* **🔑 Administrative Privileges** — Required for certificate stores, registry, disk, and AD operations

* **🔧 Execution Policy** — Session-scoped execution

  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
  ```

---

## 📄 Script Catalog (Alphabetical)

| Script Name                                         | Description                                                                                                                              |
| --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| **Cleanup-CertificateAuthority-Tool.ps1**           | Removes obsolete certificate records from Microsoft AD CS Certificate Authority databases based on configurable retention policies.      |
| **Cleanup-Repository-ExpiredCertificates-Tool.ps1** | Removes expired certificate files from repository locations according to configurable retention policies.                                |
| **Manage-PKICertificateLifecycle-Tool.ps1**         | Manages Microsoft AD CS certificate lifecycle, automated revocation, CA database maintenance, CRL publication, and governance reporting. |
| **Organize-CERTs-Repository.ps1**                   | Organizes and standardizes certificate repository contents to improve certificate storage hygiene and administration.                    |
| **Purge-ExpiredInstalledCertificates-Tool.ps1**     | Identifies and removes expired certificates installed in Windows certificate stores through controlled administrative remediation.       |
| **Purge-ExpiredInstalledCertificates-viaGPO.ps1**   | Automates expired installed-certificate cleanup across managed Windows systems through Group Policy deployment.                          |

---

## 🚀 Usage Instructions

1. Run scripts using **Run with PowerShell** or from an **elevated PowerShell console**
2. Provide the required parameters or interact via the GUI (script-dependent)
3. Review the generated outputs

### 📂 Logs and Reports Locations

| Path                       | Purpose                                                                    |
| -------------------------- | -------------------------------------------------------------------------- |
| `C:\Scripts-LOGS\`         | Certificate lifecycle, cleanup, GPO remediation, and security tooling logs |
| `C:\Logs-TEMP\`            | General-purpose, transient, and legacy script outputs                      |
| `%USERPROFILE%\Documents\` | CSV and exported reports for compliance, auditing, and PKI workflows       |

---

## 📄 Complementary Files

* Certificate repository content — Source and managed certificate files used by repository maintenance operations
* PKI lifecycle reports — Certificate lifecycle, revocation, CA maintenance, and governance outputs
* Certificate cleanup logs — Operational and audit records generated during remediation workflows

---

## 💡 Optimization Tips

* 🔁 Automate recurring certificate hygiene and lifecycle operations using Task Scheduler or GPOs
* 🗂️ Centralize PKI and certificate-management logs to a network share or SIEM pipeline
* 🧩 Customize retention policies, certificate repositories, and remediation scope to match enterprise PKI design

---

© 2026 Luiz Hamilton Silva. All rights reserved.
