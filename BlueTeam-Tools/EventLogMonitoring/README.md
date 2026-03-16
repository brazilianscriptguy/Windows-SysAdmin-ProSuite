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
| **EventID4624-ADUserLoginViaRDP.ps1**                            | Identifies successful logons (Event ID 4624) filtered specifically for RDP sessions.                                   |
| **EventID4624and4634-ADUserLoginTracking.ps1**                   | Correlates logon and logoff activity (Event IDs 4624 and 4634) to reconstruct user session timelines.                  |
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
| **Migrate-WinEvtStructure-Tool.ps1**                             | Migrates Windows Event Log storage structure and updates the associated registry configuration.                        |
| **PrintService-Operational-EventLogs.md**                        | Documentation describing how to enable and configure PrintService Operational logging.                                 |
| **PrintService-Operational-EventLogs.reg**                       | Registry configuration used to enable or configure PrintService Operational logging.                                   |

---

# 🧠 Windows Event IDs Covered by the Toolkit

## Authentication and Logon

```
4624  Successful Logon
4625  Failed Logon
4634  Logoff
4648  Explicit Credentials Logon
4672  Special Privileges Assigned
4768  Kerberos TGT Request
4769  Kerberos Service Ticket Request
4771  Kerberos Pre-Authentication Failure
```

---

## Active Directory Changes and Privileged Operations

```
4720  User Account Created
4724  Password Reset
4728  User Added to Security Group
4732  User Added to Local Group
4735  Security Group Modified
4756  User Added to Universal Security Group
5136  Directory Object Modified
5137  Directory Object Created
5141  Directory Object Deleted
```

---

## Endpoint and User Activity

```
4663  Object Access / Deletion Activity
4698  Scheduled Task Creation
4800  Workstation Locked
4801  Workstation Unlocked
```

---

## Print and Service Monitoring

```
307   Print Job Activity
7045  Service Installation
```

---

## Log Integrity and Restart Attribution

```
1102  Security Log Cleared
6005  Event Log Service Started
6006  Event Log Service Stopped
6008  Unexpected Shutdown
6009  OS Version Logged
6013  System Uptime
1074  Planned Shutdown / Restart
1076  Unexpected Shutdown Reason
```

---

## EVTX Inventory and Bulk Analysis

All event IDs present in archived `.evtx` files can be analyzed using:

```
EventID-Count-AllEvtx-Events.ps1
```

---

# 🚀 How to Use

1️⃣ Execute the desired script:

* Right-click → **Run with PowerShell**
* or launch from an **elevated PowerShell console**

---

2️⃣ Choose the analysis mode supported by the script:

**Live Log Mode**

* reads directly from Windows Event Logs

**Archived EVTX Mode**

* analyzes `.evtx` files selected from a folder

---

3️⃣ Review exported artifacts:

| File Type | Purpose                                    |
| --------- | ------------------------------------------ |
| `.csv`    | Structured analytical output               |
| `.log`    | Execution trace and processing information |

---

# 🛠 Requirements

### PowerShell

PowerShell **5.1 or later**

```powershell
$PSVersionTable.PSVersion
```

---

### Administrative Privileges

Scripts should be executed with **Administrator rights**.

---

### Microsoft Log Parser 2.2

Required only by scripts that perform **SQL-style EVTX parsing**.

---

### Windows Event Logs

Scripts can analyze:

* live Windows Event Logs
* archived `.evtx` files

---

# 📊 Outputs

## Execution Logs

Execution traces are written to:

```
C:\Logs-TEMP
```

---

## CSV Reports

Structured reports are exported by default to:

```
$env:USERPROFILE\Documents
```

These outputs are suitable for:

* Excel analysis
* forensic timeline reconstruction
* SIEM ingestion
* incident documentation
* audit evidence support

---

# 📘 Supporting Material

## Academic Reference

**2017 - Audit of Event Logs - Master's Thesis.pdf**

Provides conceptual background for Windows Event Log auditing.

---

## Print Monitoring Support

Files related to PrintService Operational logging:

* **PrintService-Operational-EventLogs.md**
* **PrintService-Operational-EventLogs.reg**

These support the print monitoring workflow and help configure the necessary logging environment.

---

# 💡 Operational Recommendations

For operational security deployments:

* preserve original `.evtx` files for evidentiary integrity
* centralize `.csv` and `.log` artifacts in secured storage
* use **archived EVTX mode** for retrospective investigations
* use **live log mode** for triage and recurring audits
* validate execution policy and administrative privileges before running scripts

---

© 2026 Luiz Hamilton Silva - All rights reserved.
