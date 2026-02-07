## 🔵 BlueTeam-Tools: EventLog Monitoring Suite  
### Log Analysis · Threat Detection · Audit Readiness

[![BlueTeam](https://img.shields.io/badge/BlueTeam-Event%20Log%20Analysis-orange?style=for-the-badge&logo=protonmail&logoColor=white)]()  
[![PowerShell](https://img.shields.io/badge/PowerShell-Primary-5391FE?style=for-the-badge&logo=powershell&logoColor=white)]()  
[![Windows](https://img.shields.io/badge/Windows-Server%20%7C%2010%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)]()  
[![Forensics](https://img.shields.io/badge/Domain-Digital%20Forensics-black?style=for-the-badge)]()  
[![Security](https://img.shields.io/badge/Domain-Cybersecurity-critical?style=for-the-badge)]()

---

The **EventLogMonitoring** directory contains **forensic‑grade PowerShell tooling** focused exclusively on **Windows Event Log (.evtx) analysis** for **Blue Team, DFIR, SOC, and audit workflows**.

This layer is **capability‑scoped**: it does **not** describe the full BlueTeam suite nor individual script internals, but defines *what this folder delivers operationally*.

Core characteristics:

- 🎛️ **GUI‑driven execution** for analyst usability  
- 📈 **Structured CSV outputs** for correlation, dashboards, and SIEM ingestion  
- 🧾 **Deterministic execution logs** for audit trails  
- 🔎 **Security‑relevant detections** aligned with Windows native Event IDs  

All scripts are **read‑only by design** (no state changes) and compatible with **PowerShell 5.1 corporate environments**.

---

## 🧪 Capability Scope

[![Scope](https://img.shields.io/badge/Scope-Event%20Logs-blue?style=for-the-badge)]()  
[![ReadOnly](https://img.shields.io/badge/Mode-Read--Only-success?style=for-the-badge)]()  
[![Audit](https://img.shields.io/badge/Use-Audit%20%26%20DFIR-informational?style=for-the-badge)]()

This folder supports:

- Authentication & logon auditing  
- Failed logon and credential misuse detection  
- Privileged group and object change tracking  
- Kerberos authentication anomaly analysis  
- System restart, shutdown, and crash auditing  
- Print activity and operational event monitoring  

---

## 📦 Script Inventory (Alphabetical)

| Script | Purpose |
|------|---------|
| **EventID-Count-AllEvtx-Events.ps1** | Counts Event IDs across `.evtx` files and exports summary statistics. |
| **EventID307-PrintAudit.ps1** | Audits print activity (Event ID 307). |
| **EventID4624-ADUserLoginViaRDP.ps1** | Tracks interactive logons via RDP (ID 4624). |
| **EventID4624and4634-ADUserLoginTracking.ps1** | Correlates logon / logoff sessions. |
| **EventID4625-ADUserLoginAccountFailed.ps1** | Reports failed authentication attempts. |
| **EventID4648-ExplicitCredentialsLogon.ps1** | Detects explicit credential usage (lateral movement indicator). |
| **EventID4663-TrackingObjectDeletions.ps1** | Identifies object deletions using AccessMask correlation. |
| **EventID4720to4756-PrivilegedAccessTracking.ps1** | Monitors privileged account lifecycle and group changes. |
| **EventID4771-KerberosPreAuthFailed.ps1** | Detects Kerberos pre‑authentication failures. |
| **EventID4800and4801-WorkstationLockStatus.ps1** | Tracks workstation lock / unlock events. |
| **EventID5136-5137-5141-ADObjectChanges.ps1** | Audits AD object create/modify/delete operations. |
| **EventID6005-6006-6008-6009-6013-1074-1076-SystemRestarts.ps1** | Audits system restarts, crashes, and shutdown causes. |
| **Migrate-WinEvtStructure-Tool.ps1** | Migrates Event Log storage location while preserving permissions. |

---

## 🚀 Usage Model

1. Execute via GUI or console  
2. Select `.evtx` source files  
3. Review generated artifacts:
   - `.csv` → analytical data  
   - `.log` → execution trace  

> ⚠️ Always preserve original evidence. Work on copies of `.evtx` files during investigations.

---

## 🛠️ Requirements

[![PS](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=for-the-badge&logo=powershell)]()  
[![Admin](https://img.shields.io/badge/Privileges-Administrator-critical?style=for-the-badge)]()

- PowerShell **5.1 minimum**  
- Administrative privileges  
- RSAT (when querying AD‑backed events)  
- Optional: **Log Parser 2.2** (Microsoft)

---

## 📊 Outputs

- **`.log`** — execution trace & warnings  
- **`.csv`** — structured analytical output  
- Ready for Excel, SIEMs, dashboards, and reports

---

## 💡 Operational Guidance

- Schedule periodic runs via **Task Scheduler**  
- Centralize outputs to secured log repositories  
- Combine with IncidentResponse tools for full timelines  

---

© 2026 Luiz Hamilton Silva. All rights reserved.
