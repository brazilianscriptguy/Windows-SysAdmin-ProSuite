# 🔍 EventLogMonitoring  
### Windows Event Logs · Detection · Correlation · Audit Support

[![Parent](https://img.shields.io/badge/Parent-BlueTeam--Tools-181717?style=for-the-badge&logo=github)](../)
[![Domain](https://img.shields.io/badge/Domain-DFIR-black?style=for-the-badge)]()
[![Security](https://img.shields.io/badge/Focus-Security%20Monitoring-critical?style=for-the-badge)]()
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-5391FE?style=for-the-badge&logo=powershell&logoColor=white)]()
[![Windows](https://img.shields.io/badge/Windows-Server%20%7C%2010%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)]()

---

## 🧭 Overview

[![Purpose](https://img.shields.io/badge/Purpose-Event%20Log%20Analysis-blue?style=for-the-badge)]()
[![Output](https://img.shields.io/badge/Output-CSV%20%7C%20LOG-success?style=for-the-badge)]()
[![Design](https://img.shields.io/badge/Design-Auditable-6A5ACD?style=for-the-badge)]()

The **EventLogMonitoring** module provides **security-focused PowerShell scripts** for the analysis and correlation of **Windows Event Logs** in enterprise and public-sector environments.

The tools in this folder are designed to support:

- Detection of suspicious or anomalous activity  
- Authentication and authorization analysis  
- Policy enforcement verification  
- Forensic timelines and audit evidence generation  

All scripts follow the same principles applied across **BlueTeam-Tools**:
**deterministic execution, structured logging, and reproducible outputs**.

---

## 🧪 What These Scripts Do

[![Detect](https://img.shields.io/badge/Capability-Detection-orange?style=for-the-badge)]()
[![Correlate](https://img.shields.io/badge/Capability-Correlation-purple?style=for-the-badge)]()
[![Audit](https://img.shields.io/badge/Capability-Audit%20Support-success?style=for-the-badge)]()

Typical use cases include:

- Analysis of authentication failures and successes  
- Identification of privilege escalation indicators  
- Detection of abnormal logon patterns  
- Review of policy and security-relevant events  
- Generation of evidence-ready reports for investigations  

Scripts **read and analyze logs only** — they do **not modify system state**.

---

## 📂 Inputs & Outputs

[![Input](https://img.shields.io/badge/Input-Windows%20Event%20Logs-blue?style=for-the-badge)]()
[![Output](https://img.shields.io/badge/Output-CSV-informational?style=for-the-badge)]()
[![Output](https://img.shields.io/badge/Output-LOG-success?style=for-the-badge)]()

**Inputs**
- Local or remote Windows Event Logs
- Security, System, and Application channels (as applicable)

**Outputs**
- Structured `.csv` files for correlation and SIEM ingestion
- Deterministic `.log` files for audit and traceability

---

## ⚙️ Requirements

[![PS](https://img.shields.io/badge/PowerShell-Minimum%205.1-5391FE?style=for-the-badge&logo=powershell)]()
[![Privileges](https://img.shields.io/badge/Privileges-Read%20Access-critical?style=for-the-badge)]()

- **PowerShell**: minimum **5.1**
- **Permissions**: sufficient rights to read Event Logs
- **RSAT** (optional, depending on scope)

---

## 🚀 Usage Model

[![Workflow](https://img.shields.io/badge/Workflow-Analyze%20→%20Export-blue?style=for-the-badge)]()

Recommended operational flow:

1. Select the script aligned with the investigation scope  
2. Review the script header and parameters  
3. Execute the script in the appropriate context  
4. Review generated `.csv` and `.log` outputs  

> ⚠️ Always preserve original logs and validate time synchronization before analysis.

---

## 🧭 Position in the Suite

[![Level](https://img.shields.io/badge/Documentation-Level--3-2F4F4F?style=for-the-badge)]()

This folder represents a **Level-3 documentation scope**:
- It documents **what this folder does**
- It does **not replace per-script help**
- Script-specific details are contained within each `.ps1` file

---

> 🔍 _EventLogMonitoring is intended for environments where **visibility, traceability, and forensic soundness** are mandatory._

© 2026 Luiz Hamilton Silva. All rights reserved.
