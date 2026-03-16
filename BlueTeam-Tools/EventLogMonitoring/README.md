## 🔵 BlueTeam-Tools: EventLog Monitoring Suite  
### Log Analysis · Threat Detection · Audit Readiness

[![BlueTeam](https://img.shields.io/badge/BlueTeam-Event%20Log%20Analysis-orange?style=for-the-badge&logo=protonmail&logoColor=white)]()
[![PowerShell](https://img.shields.io/badge/PowerShell-Primary-5391FE?style=for-the-badge&logo=powershell&logoColor=white)]()
[![Windows](https://img.shields.io/badge/Windows-Server%202019%20%7C%2010%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)]()
[![Forensics](https://img.shields.io/badge/Domain-Digital%20Forensics-black?style=for-the-badge)]()
[![Security](https://img.shields.io/badge/Domain-Cybersecurity-critical?style=for-the-badge)]()

---

The **EventLogMonitoring** folder contains a forensic-oriented collection of **PowerShell scripts**, reference files, and support material for analyzing **Windows Event Logs (`.evtx`)**.

This toolkit is intended for:

- **Blue Team operators**
- **DFIR analysts**
- **Windows administrators**
- **security engineers**
- **audit and compliance teams**

Primary use cases include:

- authentication and logon analysis
- privileged access auditing
- Active Directory object lifecycle tracking
- print activity auditing
- Kerberos authentication monitoring
- service installation monitoring
- workstation lock/unlock analysis
- event log integrity monitoring
- restart, shutdown, and crash attribution
- bulk EVTX inventory and frequency counting

All scripts are organized for **Windows Server 2019 / PowerShell 5.1** operational use, with CSV export workflows suitable for incident response, compliance review, and forensic preservation.

---

## 📦 Repository File Inventory

| File | Purpose |
|------|---------|
| **2017 - Audit of Event Logs - Master's Thesis.pdf** | Reference thesis related to event log auditing and academic background for the toolkit domain. |
| **EventID-Count-AllEvtx-Events.ps1** | Counts all Event IDs in selected `.evtx` files and exports a frequency summary to `.csv`. |
| **EventID1102-EventLogCleared.ps1** | Detects Security log clearing events (Event ID 1102). |
| **EventID307-PrintingAudit.ps1** | Audits print activity through PrintService Operational logging and Event ID 307 analysis. |
| **EventID4624-ADUserLoginViaRDP.ps1** | Identifies successful logons (Event ID 4624) filtered specifically for RDP sessions. |
| **EventID4624and4634-ADUserLoginTracking.ps1** | Correlates logon and logoff activity (Event IDs 4624 and 4634) into user session timelines. |
| **EventID4625-ADUserLoginAccountFailed.ps1** | Captures failed authentication attempts (Event ID 4625) with failure context. |
| **EventID4648-ExplicitCredentialsLogon.ps1** | Detects explicit credential usage (Event ID 4648), useful for lateral movement analysis. |
| **EventID4663-TrackingObjectDeletions.ps1** | Tracks deletion-related object access activity via Event ID 4663. |
| **EventID4672-AdminPrivilegesAssigned.ps1** | Detects assignment of special administrative privileges at logon (Event ID 4672). |
| **EventID4698-ScheduledTaskCreated.ps1** | Detects scheduled task creation events (Event ID 4698). |
| **EventID4720to4756-PrivilegedAccessTracking.ps1** | Monitors privileged account and group management operations across multiple security Event IDs. |
| **EventID4768-KerberosTGTRequest.ps1** | Analyzes Kerberos TGT request events (Event ID 4768). |
| **EventID4769-KerberosServiceTicket.ps1** | Analyzes Kerberos service ticket request events (Event ID 4769). |
| **EventID4771-KerberosPreAuthFailed.ps1** | Analyzes Kerberos pre-authentication failures (Event ID 4771). |
| **EventID4800and4801-WorkstationLockStatus.ps1** | Records workstation lock and unlock activity to infer user presence. |
| **EventID5136-5137and5141-ADChanges-and-ObjectDeletions.ps1** | Audits Active Directory object modification, creation, and deletion events. |
| **EventID6005-6006-6008-6009-6013-1074-1076-SystemRestarts.ps1** | Attributes startups, shutdowns, crashes, uptime events, and user-initiated restart operations. |
| **EventID7045-ServiceInstalled.ps1** | Detects service installation events (Event ID 7045). |
| **Migrate-WinEvtStructure-Tool.ps1** | Migrates the Windows Event Log storage structure and associated configuration. |
| **PrintService-Operacional-EventLogs.md** | Supporting documentation for PrintService Operational logging. |
| **PrintService-Operacional-EventLogs.reg** | Registry file used to support or enable PrintService Operational logging configuration. |

---

## 🧠 Event Coverage Overview

### Authentication and Logon
- `4624`
- `4625`
- `4634`
- `4648`
- `4672`
- `4768`
- `4769`
- `4771`

### Active Directory Changes and Privileged Operations
- `4720`
- `4724`
- `4728`
- `4732`
- `4735`
- `4756`
- `5136`
- `5137`
- `5141`

### Endpoint and User Activity
- `4663`
- `4698`
- `4800`
- `4801`

### Print and Service Monitoring
- `307`
- `7045`

### Log Integrity and Restart Attribution
- `1102`
- `6005`
- `6006`
- `6008`
- `6009`
- `6013`
- `1074`
- `1076`

### EVTX Inventory and Bulk Analysis
- all Event IDs present in archived `.evtx` files through:
  - `EventID-Count-AllEvtx-Events.ps1`

---

## 🚀 How to Use

1. Run the desired script:
   - right-click → **Run with PowerShell**, or
   - start it from an elevated PowerShell session.

2. Choose one of the available analysis modes:
   - **live log mode**, when supported by the script
   - **archived EVTX mode**, by selecting a folder containing `.evtx` files

3. Review the exported artifacts:
   - `.csv` → structured analytical output
   - `.log` → execution log and operational trace

---

## 🛠️ Requirements

- **PowerShell 5.1 or later**
```powershell
$PSVersionTable.PSVersion
```

- **Administrator privileges**

- **Microsoft Log Parser 2.2**
  Required by the event-oriented parsing tools that use Log Parser COM.

- **Windows Event Logs / archived `.evtx` files**
  Depending on the selected script and analysis mode.

---

## 📊 Outputs

### Log Files
Execution logs are written to:

```text
C:\Logs-TEMP
```

### CSV Reports
Structured reports are exported by default to:

```text
My Documents
```

These outputs are suitable for:

- Excel review
- timeline construction
- SIEM ingestion
- incident documentation
- audit evidence support

---

## 📘 Supporting Material

### Academic Reference
- **2017 - Audit of Event Logs - Master's Thesis.pdf**

### Print Monitoring Support Files
- **PrintService-Operacional-EventLogs.md**
- **PrintService-Operacional-EventLogs.reg**

These files complement the print-audit workflow and help document or enable the required logging path.

---

## 💡 Operational Recommendations

- keep original `.evtx` files preserved for evidentiary integrity
- centralize generated `.csv` and `.log` outputs in secured storage when used operationally
- use archived EVTX mode for retrospective investigation
- use live mode for rapid triage and recurring audit workflows
- validate PowerShell execution policy and administrative context before running the tools

---

© 2026 Luiz Hamilton Silva. All rights reserved.
