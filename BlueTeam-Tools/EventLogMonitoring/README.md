## 🔵 BlueTeam-Tools: EventLog Monitoring Suite

### 📌 Overview

The **EventLogMonitoring** folder includes a robust set of **PowerShell scripts** for security analysts and Windows administrators to efficiently process `.evtx` logs. These tools support auditing logons, print jobs, object changes, and system restarts — generating `.log` and `.csv` files for documentation, forensics, and compliance purposes.

- 🎛️ **GUI Interfaces:** Most scripts are GUI-based for ease of use.  
- 📈 **Report Exports:** Structured `.csv` files support log correlation and dashboards.  
- 🧾 **Execution Logs:** Each execution produces a `.log` file.  
- 🔎 **Security Insights:** Detect failed logons, admin group changes, object deletions, and credential misuse.

---

## 📦 Script Inventory (Alphabetical)

| Script | Purpose |
|--------|---------|
| **EventID-Count-AllEvtx-Events.ps1** | Counts all Event IDs in selected `.evtx` files. Outputs summary to `.csv`. |
| **EventID307-PrintAudit.ps1** | Audits print activity via Event ID 307. See `PrintService-Operational-EventLogs.md`. |
| **EventID4624-ADUserLoginViaRDP.ps1** | Tracks Event ID 4624 (logon) filtered by RDP sessions. |
| **EventID4624and4634-ADUserLoginTracking.ps1** | Tracks user login/logout (IDs 4624, 4634). Exports full session info. |
| **EventID4625-ADUserLoginAccountFailed.ps1** | Captures failed login attempts (Event ID 4625). Outputs `.csv`. |
| **EventID4648-ExplicitCredentialsLogon.ps1** | Monitors Event ID 4648 for explicit credential usage. Flags lateral movement. |
| **EventID4663-TrackingObjectDeletions.ps1** | Detects object deletions via Event ID 4663 + AccessMask 0x10000. |
| **EventID4720to4756-PrivilegedAccessTracking.ps1** | Tracks privileged account actions (creation, group changes, etc.). |
| **EventID4771-KerberosPreAuthFailed.ps1** | Tracks failed Kerberos pre-authentication (ID 4771). |
| **EventID4800and4801-WorkstationLockStatus.ps1** | Logs lock/unlock events for user presence analysis. |
| **EventID5136-5137-5141-ADObjectChanges.ps1** | Audits AD object lifecycle events: create/modify/delete with DN and timestamp. |
| **EventID6005-6006-6008-6009-6013-1074-1076-SystemRestarts.ps1** | Logs system restarts, crashes, and shutdowns (user-initiated or failures). |
| **Migrate-WinEvtStructure-Tool.ps1** | Moves `.evtx` log location. Adjusts registry, preserves permissions. |

> 🧠 **Migration Notes for `Migrate-WinEvtStructure-Tool.ps1`:**
>
> - Enter Safe Mode to stop EventLog:
>   ```powershell
>   bcdedit /set {current} safeboot minimal
>   shutdown /r /t 0
>   ```
>   After migration:
>   ```powershell
>   bcdedit /deletevalue {current} safeboot
>   shutdown /r /t 0
>   ```
>
> - Backup/restore DHCP config (optional):
>   ```powershell
>   netsh dhcp server export C:\Backup\dhcpconfig.dat all
>   netsh dhcp server import C:\Backup\dhcpconfig.dat all
>   ```

---

## 🚀 How to Use

1. **Run the Script:**  
   Right-click → `Run with PowerShell` or use terminal execution.

2. **Select Input:**  
   Choose one or more `.evtx` files when prompted or via the GUI.

3. **Analyze Outputs:**  
   - `.csv` for data  
   - `.log` for runtime tracing

---

## 🛠️ Requirements

- ✅ PowerShell 5.1 or later  
- 🔐 Administrator privileges  
- 🖥️ RSAT Tools for AD filtering  
- 🔎 [Log Parser 2.2](https://www.microsoft.com/en-us/download/details.aspx?id=24659)  
  [![Download Log Parser](https://img.shields.io/badge/Download-Log%20Parser-blue?style=flat-square&logo=microsoft)](https://www.microsoft.com/en-us/download/details.aspx?id=24659)

---

## 📊 Logs and Exports

- `.log` files: Record execution steps, warnings, and events.  
- `.csv` files: Output structured data for Excel, SIEMs, or dashboards.

---

## 💡 Optimization Tips

- ⏱️ Use **Task Scheduler** to run scripts daily or weekly.  
- 📁 Redirect logs and reports to `\\logserver\exports` or centralized stores.  
- 🧹 Apply filters and pre-conditions to reduce noise and increase accuracy.

---

© 2025 Luiz Hamilton. All rights reserved.
