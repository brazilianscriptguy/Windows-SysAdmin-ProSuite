## 🔵 BlueTeam-Tools: EventLog Monitoring Suite  
### Log Analysis · Threat Detection · Audit Readiness

[![BlueTeam](https://img.shields.io/badge/BlueTeam-Event%20Log%20Analysis-orange?style=for-the-badge&logo=protonmail&logoColor=white)]() [![PowerShell](https://img.shields.io/badge/PowerShell-Primary-5391FE?style=for-the-badge&logo=powershell&logoColor=white)]() [![Windows](https://img.shields.io/badge/Windows-Server%20%7C%2010%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)]() [![Forensics](https://img.shields.io/badge/Domain-Digital%20Forensics-black?style=for-the-badge)]() [![Security](https://img.shields.io/badge/Domain-Cybersecurity-critical?style=for-the-badge)]()

---

The **EventLogMonitoring** folder contains a specialized and forensic-oriented collection of **PowerShell scripts** designed to process, correlate, and audit **Windows Event Log (`.evtx`) data**.

These tools are intended for use by **Blue Team operators, DFIR analysts, security engineers, and Windows administrators** in enterprise and public-sector environments where **auditability, repeatability, and evidentiary integrity** are required.

Primary use cases include:

- Authentication and logon analysis  
- Privilege escalation and group membership auditing  
- Object lifecycle tracking in Active Directory  
- Print activity and service usage auditing  
- System restarts, crashes, and shutdown attribution  

All scripts generate **structured `.log` and `.csv` artifacts**, suitable for investigations, compliance reporting, and long-term forensic readiness.

---

## 📦 Script Inventory (Alphabetical)

| Script | Purpose |
|------|---------|
| **EventID-Count-AllEvtx-Events.ps1** | Counts all Event IDs in selected `.evtx` files and exports a frequency summary to `.csv`. |
| **EventID307-PrintAudit.ps1** | Audits print activity using Event ID 307. Complements `PrintService-Operational-EventLogs.md`. |
| **EventID4624-ADUserLoginViaRDP.ps1** | Identifies successful logons (Event ID 4624) filtered specifically for RDP sessions. |
| **EventID4624and4634-ADUserLoginTracking.ps1** | Correlates logon/logoff activity (Event IDs 4624 and 4634) into full user session timelines. |
| **EventID4625-ADUserLoginAccountFailed.ps1** | Captures failed authentication attempts (Event ID 4625) with detailed failure reasons. |
| **EventID4648-ExplicitCredentialsLogon.ps1** | Detects explicit credential usage (Event ID 4648), commonly associated with lateral movement. |
| **EventID4663-TrackingObjectDeletions.ps1** | Tracks object deletions via Event ID 4663 with AccessMask `0x10000`. |
| **EventID4720to4756-PrivilegedAccessTracking.ps1** | Monitors privileged account operations (creation, deletion, group changes, delegation). |
| **EventID4771-KerberosPreAuthFailed.ps1** | Analyzes Kerberos pre-authentication failures (Event ID 4771). |
| **EventID4800and4801-WorkstationLockStatus.ps1** | Records workstation lock and unlock events to infer user presence. |
| **EventID5136-5137-5141-ADObjectChanges.ps1** | Audits Active Directory object creation, modification, and deletion events. |
| **EventID6005-6006-6008-6009-6013-1074-1076-SystemRestarts.ps1** | Attributes system restarts, crashes, and shutdowns to users, services, or failures. |
| **Migrate-WinEvtStructure-Tool.ps1** | Migrates the Windows Event Log storage path, updates registry settings, and preserves permissions. |

---

## 🧠 Migration Notes — `Migrate-WinEvtStructure-Tool.ps1`

> ⚠️ **This script performs low-level changes to the Windows Event Log infrastructure.**  
> It must be executed carefully and only by qualified administrators.

### Safe Mode Requirement

To safely stop the Event Log service and migrate the `.evtx` structure:

```powershell
bcdedit /set {current} safeboot minimal
shutdown /r /t 0
```

After completing the migration:

```powershell
bcdedit /deletevalue {current} safeboot
shutdown /r /t 0
```

### Optional: DHCP Configuration Backup

If executed on systems hosting DHCP services:

```powershell
netsh dhcp server export C:\Backup\dhcpconfig.dat all
netsh dhcp server import C:\Backup\dhcpconfig.dat all
```

> 🔎 Always validate Event Log integrity and permissions after migration.

---

## 🚀 How to Use

1. Execute the desired script:
   - Right-click → **Run with PowerShell**, or
   - Launch from an elevated PowerShell console.

2. Select one or more `.evtx` files when prompted (GUI or file picker).

3. Review generated artifacts:
   - `.csv` — structured analytical output  
   - `.log` — execution trace and warnings  

---

## 🛠️ Requirements

- **PowerShell 5.1 or later**
```powershell
$PSVersionTable.PSVersion
```

- **Administrator privileges** (mandatory)

- **RSAT tools** (for Active Directory correlation)
```powershell
Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online
```

- **Microsoft Log Parser 2.2**
  Required for advanced `.evtx` parsing operations.

---

## 📊 Logs and Exports

- `.log` files  
  Execution trace, warnings, and processing steps.

- `.csv` files  
  Structured output suitable for Excel, SIEM ingestion, or forensic timelines.

---

## 💡 Operational Recommendations

- Schedule recurring analysis via **Task Scheduler**
- Centralize outputs on secured file shares (e.g., `\\logserver\exports`)
- Apply pre-filters to reduce noise and improve signal quality
- Preserve original `.evtx` files for evidentiary integrity

---

© 2026 Luiz Hamilton Silva. All rights reserved.
