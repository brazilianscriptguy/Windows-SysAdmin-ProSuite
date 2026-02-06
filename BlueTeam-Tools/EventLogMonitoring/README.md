## 🔵 BlueTeam-Tools: EventLog Monitoring Suite  
### Log Analysis · Threat Detection · Audit Readiness

[![BlueTeam](https://img.shields.io/badge/BlueTeam-Event%20Log%20Analysis-orange?style=for-the-badge&logo=protonmail&logoColor=white)]() [![PowerShell](https://img.shields.io/badge/PowerShell-Primary-5391FE?style=for-the-badge&logo=powershell&logoColor=white)]() [![Windows](https://img.shields.io/badge/Windows-Server%20%7C%2010%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)]() [![Forensics](https://img.shields.io/badge/Domain-Digital%20Forensics-black?style=for-the-badge)]() [![Security](https://img.shields.io/badge/Domain-Cybersecurity-critical?style=for-the-badge)]()

---

## 🧭 Overview

The **EventLogMonitoring** suite provides **PowerShell-based tooling** for processing and correlating **Windows Event Log (`.evtx`)** data to support **security investigations**, **audit trails**, and **forensic analysis**.

The tools are optimized for **clarity**, **repeatability**, and **structured output**, enabling reliable analysis across large log sets.

- 🎛️ **GUI-Based Execution** — Analyst-friendly interfaces  
- 📈 **Structured Reports** — `.csv` exports for dashboards and SIEMs  
- 🧾 **Execution Logging** — Deterministic `.log` files  
- 🔎 **Security Insight** — Authentication, object changes, and system activity  

---

## 📦 Script Inventory (Alphabetical)

| Script | Purpose |
|--------|---------|
| **EventID-Count-AllEvtx-Events.ps1** | Counts all Event IDs in selected `.evtx` files and exports summaries. |
| **EventID307-PrintAudit.ps1** | Audits print activity using Event ID 307. |
| **EventID4624-ADUserLoginViaRDP.ps1** | Tracks RDP logons using Event ID 4624. |
| **EventID4624and4634-ADUserLoginTracking.ps1** | Tracks login/logout sessions via Event IDs 4624 and 4634. |
| **EventID4625-ADUserLoginAccountFailed.ps1** | Captures failed logon attempts (Event ID 4625). |
| **EventID4648-ExplicitCredentialsLogon.ps1** | Detects explicit credential usage (lateral movement indicator). |
| **EventID4663-TrackingObjectDeletions.ps1** | Detects object deletions using Event ID 4663. |
| **EventID4720to4756-PrivilegedAccessTracking.ps1** | Tracks privileged account lifecycle events. |
| **EventID4771-KerberosPreAuthFailed.ps1** | Detects failed Kerberos pre-authentication events. |
| **EventID4800and4801-WorkstationLockStatus.ps1** | Tracks workstation lock/unlock events. |
| **EventID5136-5137-5141-ADObjectChanges.ps1** | Audits AD object create/modify/delete events. |
| **EventID6005-6006-6008-6009-6013-1074-1076-SystemRestarts.ps1** | Audits shutdowns, crashes, and restarts. |
| **Migrate-WinEvtStructure-Tool.ps1** | Migrates Windows Event Log storage while preserving permissions. |

---

## 🚀 How to Use

1. Run the script via GUI or CLI  
2. Select one or more `.evtx` files  
3. Review generated `.csv` and `.log` outputs  

---

## 🛠️ Requirements & Dependencies

- PowerShell **5.1+**  
- **Administrator** privileges  
- **RSAT** for AD-based filtering  
- **Log Parser 2.2** (optional but recommended)

---

## 📊 Logs and Exports

- `.log` — Execution trace and warnings  
- `.csv` — Structured datasets for analysis and dashboards  

---

## 💡 Operational Recommendations

- ⏱️ Schedule periodic execution via **Task Scheduler**  
- 📁 Centralize exports for SOC and audit teams  
- 🔎 Apply filters to reduce noise and increase signal  

---

> 🛡️ _EventLogMonitoring tools are designed to provide **high-fidelity visibility** into Windows security events._

© 2026 Luiz Hamilton Silva. All rights reserved.
