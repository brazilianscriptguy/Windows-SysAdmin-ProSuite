## 🔵 BlueTeam-Tools: EventLog Monitoring Suite

### Log Analysis · Threat Detection · Audit Readiness

[![BlueTeam](https://img.shields.io/badge/BlueTeam-Event%20Log%20Analysis-orange?style=for-the-badge\&logo=protonmail\&logoColor=white)]()
[![PowerShell](https://img.shields.io/badge/PowerShell-Primary-5391FE?style=for-the-badge\&logo=powershell\&logoColor=white)]()
[![Windows](https://img.shields.io/badge/Windows-Server%202019%20%7C%2010%20%7C%2011-0078D6?style=for-the-badge\&logo=windows\&logoColor=white)]()
[![Forensics](https://img.shields.io/badge/Domain-Digital%20Forensics-black?style=for-the-badge)]()
[![Security](https://img.shields.io/badge/Domain-Cybersecurity-critical?style=for-the-badge)]()

---

The **EventLogMonitoring** folder contains a forensic-oriented collection of **PowerShell scripts**, reference documentation, and support files designed to analyze and audit **Windows Event Logs (`.evtx`)**.

This toolkit is designed for operational use by:

* **Blue Team operators**
* **DFIR analysts**
* **Windows administrators**
* **Security engineers**
* **Audit and compliance teams**

The toolkit prioritizes **forensic preservation, deterministic log parsing, and repeatable audit workflows**, enabling both **live log triage** and **retrospective investigation using archived `.evtx` files**.

---

# 🔎 Core Capabilities

The scripts support multiple operational security and forensic workflows:

* authentication and logon analysis
* privileged access monitoring
* Active Directory object lifecycle tracking
* Kerberos authentication analysis
* scheduled task and service installation detection
* workstation lock and unlock tracking
* print activity auditing
* event log integrity monitoring
* restart, shutdown, and crash attribution
* bulk EVTX inventory and event frequency analysis

All scripts are structured for **Windows Server 2019 environments using PowerShell 5.1**, generating structured outputs suitable for:

* incident response investigations
* compliance and audit review
* digital forensic analysis
* long-term evidence preservation

---

# 📦 Repository File Inventory

| File                                                             | Purpose                                                                                                                |
| ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| **2017 - Audit of Event Logs - Master's Thesis.pdf**             | Academic reference related to Windows event log auditing and the conceptual foundation of the toolkit.                 |
| **EventID-Count-AllEvtx-Events.ps1**                             | Counts all Event IDs across selected `.evtx` files and exports a frequency summary to `.csv`.                          |
| **EventID1102-EventLogCleared.ps1**                              | Detects clearing of the Windows Security Event Log (Event ID 1102), often associated with anti-forensic activity.      |
| **EventID307-PrintingAudit.ps1**                                 | Audits print activity using PrintService Operational logging and Event ID 307.                                         |
| **EventID4624-4634-ADUserSessionAudit.ps1**                   | Correlates logon and logoff activity (Event IDs 4624 and 4634) to reconstruct user session timelines.                  |
| **EventID4625-ADUserLoginAccountFailed.ps1**                     | Captures failed authentication attempts (Event ID 4625) with contextual failure information.                           |
| **EventID4648-ExplicitCredentialsLogon.ps1**                     | Detects explicit credential usage (Event ID 4648), commonly linked to lateral movement attempts.                       |
| **EventID4663-TrackingObjectDeletions.ps1**                      | Tracks object deletion activity via Event ID 4663 with deletion access masks.                                          |
| **EventID4672-AdminPrivilegesAssigned.ps1**                      | Detects assignment of special administrative privileges during logon (Event ID 4672).                                  |
| **EventID4698-ScheduledTaskCreated.ps1**                         | Detects scheduled task creation events (Event ID 4698), often associated with persistence techniques.                  |
| **EventID4720to4756-PrivilegedAccessTracking.ps1**               | Monitors privileged account operations including account creation, deletion, group membership, and delegation changes. |
| **EventID4768-KerberosTGTRequest.ps1**                           | Analyzes Kerberos Ticket Granting Ticket (TGT) request events (Event ID 4768).                                         |
| **EventID4769-KerberosServiceTicket.ps1**                        | Analyzes Kerberos service ticket requests (Event ID 4769).                                                             |
| **EventID4771-KerberosPreAuthFailed.ps1**                        | Detects Kerberos pre-authentication failures (Event ID 4771), often linked to password guessing attacks.               |
| **EventID4800and4801-WorkstationLockStatus.ps1**                 | Records workstation lock and unlock activity to infer user presence and workstation usage.                             |
| **EventID5136-5137and5141-ADChanges-and-ObjectDeletions.ps1**    | Audits Active Directory object modification, creation, and deletion events.                                            |
| **EventID6005-6006-6008-6009-6013-1074-1076-SystemRestarts.ps1** | Attributes system startups, shutdowns, crashes, uptime events, and user-initiated restart operations.                  |
| **EventID7045-ServiceInstalled.ps1**                             | Detects installation of new Windows services (Event ID 7045), commonly associated with persistence mechanisms.         |
| **Extract-Evidences-FileServer-Tool.ps1** | Extracts forensic evidence from FileServer shares using NTFS permissions and Event ID 4663 access logs to identify access activity and involved files or folders. |
| **Migrate-WinEvtStructure-Tool.ps1**                             | Migrates Windows Event Log storage structure and updates the associated registry configuration.                        |
| **PrintService-Operational-EventLogs.md**                        | Documentation describing how to enable and configure PrintService Operational logging.                                 |
| **PrintService-Operational-EventLogs.reg**                       | Registry configuration used to enable or configure PrintService Operational logging.                                   |

---

# 🧠 Windows Event IDs Covered by the Toolkit

This toolkit provides forensic-oriented PowerShell utilities for:

* live Windows Event Log acquisition
* archived `.evtx` forensic analysis
* timeline reconstruction
* privileged access auditing
* authentication tracking
* Active Directory object monitoring
* persistence detection
* restart attribution analysis
* file server evidence extraction

All tools support:

* PowerShell 5.1+
* structured CSV exports
* forensic logging
* GUI-based execution
* PATH-AGNOSTIC archived EVTX processing
* recursive EVTX folder analysis
* live log acquisition and offline forensic workflows

---

# 🔐 Authentication and Logon Events

```text
4624  Successful Logon
4625  Failed Logon
4634  Logoff
4648  Explicit Credentials Logon
4672  Special Privileges Assigned
4768  Kerberos TGT Request
4769  Kerberos Service Ticket Request
4771  Kerberos Pre-Authentication Failure
4800  Workstation Locked
4801  Workstation Unlocked
```

---

# 👑 Privileged Access and Persistence Monitoring

```text
4672  Special Privileges Assigned
4698  Scheduled Task Creation
4720  User Account Created
4724  Password Reset
4728  User Added to Security Group
4732  User Added to Local Group
4735  Security Group Modified
4756  User Added to Universal Security Group
7045  Service Installation
```

---

# 🏛 Active Directory Changes and Object Tracking

```text
5136  Directory Object Modified
5137  Directory Object Created
5141  Directory Object Deleted
```

---

# 📂 File Server and Object Access Monitoring

```text
4663  Object Access / Deletion Activity
```

Additional forensic extraction workflows support:

* bulk evidence extraction
* EVTX correlation
* file server investigation workflows
* timeline reconstruction

---

# 🖨 Print Monitoring

```text
307  Print Job Activity
```

---

# 🛡 Log Integrity and Restart Attribution

```text
1102  Security Log Cleared

6005  Event Log Service Started
6006  Event Log Service Stopped
6008  Unexpected Shutdown
6009  Operating System Version Logged
6013  System Uptime

1074  Planned Shutdown / Restart
1076  Unexpected Shutdown Reason
```

---

# 📦 EVTX Inventory and Bulk Analysis

The toolkit also supports:

* full EVTX inventory analysis
* Event ID counting across archived `.evtx` repositories
* recursive evidence scanning
* large-scale forensic event enumeration

---

# 🚀 How to Use

## 1️⃣ Execute the Desired Script

### GUI Execution

* Right-click → **Run with PowerShell**

### Console Execution

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\ScriptName.ps1
```

---

## 2️⃣ Choose the Analysis Mode

### Live Log Mode

* reads directly from Windows Event Logs
* uses live acquisition workflows
* supports Security/System/Operational channels depending on the tool

### Archived EVTX Mode

* analyzes offline `.evtx` files
* supports recursive folder scanning
* supports PATH-AGNOSTIC evidence locations
* accepts `.evtx` files from:
  * local folders
  * mounted forensic images
  * external storage
  * network shares
  * exported evidence repositories

---

## 3️⃣ Review Exported Artifacts

| File Type | Purpose |
|---|---|
| `.csv` | Structured analytical evidence |
| `.log` | Execution trace and forensic processing lifecycle |

---

# 🛠 Technical Requirements

## PowerShell

PowerShell **5.1 or later**

```powershell
$PSVersionTable.PSVersion
```

---

## Administrative Privileges

Scripts should be executed with:

* local Administrator privileges
* or equivalent forensic analyst privileges

---

## Microsoft Log Parser 2.2

Required by scripts using:

* Log Parser COM
* SQL-style EVTX parsing
* forensic correlation workflows

---

## Windows Event Logs

Supported evidence sources:

* live Windows Event Logs
* archived `.evtx` files
* exported forensic snapshots

---

# 📊 Outputs

## Execution Logs

Execution traces are written to:

```text
C:\Logs-TEMP
```

---

## CSV Reports

Structured reports are exported by default to:

```powershell
$env:USERPROFILE\Documents
```

Generated artifacts are suitable for:

* Excel analysis
* forensic timeline reconstruction
* SIEM ingestion
* DFIR workflows
* incident response
* audit evidence support
* administrative investigations

---

# 🧬 Forensic Processing Architecture

The toolkit implements:

* PATH-AGNOSTIC archived EVTX processing
* string-only EVTX path pipelines
* live acquisition separation
* offline evidence isolation
* recursive EVTX enumeration
* Log Parser COM + Get-WinEvent fallback workflows
* structured forensic normalization
* ordered evidence export schemas

---

# 📘 Supporting Material

## Academic Reference

### `2017 - Audit of Event Logs - Master's Thesis.pdf`

Provides conceptual background for:

* Windows Event Log auditing
* forensic event reconstruction
* evidence correlation
* security auditing methodologies

---

## Print Monitoring Support

### Supporting Files

* `PrintService-Operational-EventLogs.md`
* `PrintService-Operational-EventLogs.reg`

These files assist with:

* enabling PrintService Operational logging
* configuring print auditing
* validating print forensic workflows

---

# 💡 Operational Recommendations

For enterprise and forensic deployments:

* preserve original `.evtx` files
* maintain evidence chain-of-custody
* centralize `.csv` and `.log` artifacts
* use archived EVTX mode for retrospective investigations
* use live mode for triage and recurring audits
* validate execution policy before running scripts
* preserve original timestamps and metadata
* avoid modifying source evidence repositories

---

# ⚖️ Intended Usage

This toolkit is intended for:

* DFIR
* Windows security auditing
* Active Directory investigations
* privileged access monitoring
* insider threat investigations
* administrative auditing
* incident response
* forensic evidence reconstruction

---

© 2026 Luiz Hamilton Roberto da Silva — All rights reserved.
