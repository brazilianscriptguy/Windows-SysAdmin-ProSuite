# ⚙️ WSUS Management Tools

![WSUS](https://img.shields.io/badge/WSUS-Management-blue?style=for-the-badge&logo=microsoft) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?style=for-the-badge&logo=powershell&logoColor=white) ![Windows Server](https://img.shields.io/badge/Platform-Windows%20Server-0078D6?style=for-the-badge&logo=windows) ![GUI](https://img.shields.io/badge/Interface-GUI%20%7C%20Automation-4CAF50?style=for-the-badge) ![Database](https://img.shields.io/badge/SUSDB-WID%20%7C%20SQL-9C27B0?style=for-the-badge)

## 📝 Overview

The **WSUS Management Tools** suite provides an enterprise-grade, **auditable PowerShell maintenance tool** for **Windows Server Update Services (WSUS)**, including end-to-end care of **SUSDB** on **Windows Internal Database (WID)** or full SQL Server.

This repository is aligned with the same **GUI, logging, safety, and execution standards** used across **Windows‑SysAdmin‑ProSuite** and is designed for **corporate WSUS operations** (repeatable runs, strong guardrails, predictable outputs, and safe defaults).

✅ **Current flagship (all-in-one):** `Maintenance-WSUS-Admin-Tool.ps1`  
This single script consolidates the legacy helper scripts into one hardened GUI tool.

---

## ✅ Key Features

### 🧰 All‑in‑One WSUS Maintenance GUI
- One tool for **preflight**, **inventory**, **decline**, **cleanup**, and **database maintenance**
- Corporate-friendly behavior (safe-by-default execution + clear logs)

### 🔎 Preflight & WSUS API Validation (Hardened)
- Automatic discovery and loading of:
  - `Microsoft.UpdateServices.Administration.dll`
  - `UpdateServices` PowerShell module (when available)
- WSUS Admin API connectivity test (target server/port/SSL)
- Service validation and recovery helpers:
  - `W3SVC`, `WSUSService`
  - IIS AppPool: `WsusPool` recycle/start

### 🧾 Environment Inventory (Exportable)
- Exports **JSON + CSV summary** for auditability
- Captures key WSUS/WID signals:
  - WSUS endpoint (server/port/SSL)
  - WSUS Admin API readiness
  - `wsusutil.exe` and `sqlcmd.exe` detection
  - WID / SQL connectivity validation
  - IIS/Services status

### 🧹 Decline & Cleanup Workflow
- Decline routines (policy-driven):
  - Unapproved (older-than threshold)
  - Expired
  - Superseded
  - Legacy (optional policy set)
- WSUS cleanup operations:
  - Obsolete updates
  - Unneeded content files
  - Obsolete computers
  - Optional update compression (user-controlled)

> Note: `CleanupObsoleteUpdates` can legitimately hit timeouts on large environments. The tool logs the timeout and continues where safe.

### 🗄️ SUSDB Health & Performance (WID / SQL)
- Generates SQL scripts for repeatable database maintenance:
  - fragmentation verification
  - “smart” reindex strategy (reorganize vs rebuild)
  - classic maintenance script (optional)
- DB integrity check:
  - `DBCC CHECKDB (SUSDB) WITH NO_INFOMSGS`
- Uses `sqlcmd.exe` with robust argument quoting to avoid command parsing failures.

### 📊 Logging, Reports, and Predictable Outputs
- Single-session log file (default):
  - `C:\Logs-TEMP\WSUS-GUI\Logs\NEW-WSUS-TOOL.log`
- Timestamped inventory and reports for audit trails
- Clear step boundaries and failure visibility (INFO/WARN/ERROR)

---

## 🛠️ Prerequisites

### 1) ⚙️ PowerShell
- Windows PowerShell **5.1+** (recommended on WSUS host)

```powershell
$PSVersionTable.PSVersion
```

### 2) 🔑 Administrator Privileges
- Run **elevated** (required for WSUS Admin API operations, IIS actions, and DB tasks).

### 3) 📦 WSUS Administration Components
- WSUS must be installed and the WSUS Admin API available:
  - `Microsoft.UpdateServices.Administration.dll`
- Usually present on the WSUS server at:
  - `C:\Program Files\Update Services\Api\Microsoft.UpdateServices.Administration.dll`

### 4) 🗄️ SQLCMD Utilities (Required for SUSDB Maintenance)
- Required to run queries against WID/SUSDB (or SQL Server).
- WID named pipe (typical WSUS/WID):
```
np:\\.\pipe\MICROSOFT##WID\tsql\query
```

**sqlcmd.exe**
- The tool detects common locations (e.g. ODBC 17/18 Client SDK).
- Best practice: ensure `sqlcmd.exe` is available in `PATH`.

### 5) 🔧 Execution Policy (Session Only)
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
```

---

## 📜 Script Inventory

| Script | Purpose |
|------|--------|
| **Maintenance-WSUS-Admin-Tool.ps1** | **All-in-one** WSUS GUI: preflight, inventory export, decline & cleanup operations, SQL script generation, SUSDB maintenance (WID/SQL) |

> Legacy helper scripts (`Check-WSUS-AdminAssembly.ps1`, `Inventory-WSUSEnvironment.ps1`, `Generate-WSUSReindexScript.ps1`) were **integrated** into the main tool for a single corporate-grade workflow. They may remain in the repository for reference/testing, but the recommended operational path is the unified tool.

---

## 🚀 Usage

### 🖥️ Run the WSUS Maintenance GUI (Recommended)

1. Copy `Maintenance-WSUS-Admin-Tool.ps1` to the WSUS host (or run from a secured share)
2. Right‑click → **Run with PowerShell (Administrator)**
3. Confirm:
   - WSUS Server (default: local FQDN)
   - Port (default: `8530`)
   - SSL (default: `False`, unless your environment uses 8531/SSL)
4. Use **Preflight** first:
   - Admin API load
   - Connection test
   - Export inventory
   - Generate SQL scripts
5. Execute maintenance steps and review logs/reports

---

## 📁 Output Paths & Structure

Default working directory:

```
C:\Logs-TEMP\WSUS-GUI\
├── Logs\
│   ├── NEW-WSUS-TOOL.log
│   └── Inventory\
│       ├── wsus-inventory-YYYYMMDD-HHMMSS.json
│       └── wsus-inventory-summary-YYYYMMDD-HHMMSS.csv
├── CSV\
├── Backups\
└── settings.json
```

Generated SQL scripts (default):

```
C:\Scripts\SUSDB\
├── wsus-verify-fragmentation.sql
├── wsus-reindex-smart.sql
└── wsusdbmaintenance-classic.sql
```

---

## 💡 Operational Best Practices (Corporate WSUS)

- ⏰ Run maintenance in an **overnight window**
- 📌 Prefer: **Reindex/DB maintenance → WSUS cleanup** for very large SUSDBs
- 💾 Keep DB backups and logs on a dedicated volume or secured share
- 🔐 Restrict execution to WSUS admins and audit all runs via exported inventory/logs
- 🧪 After maintenance, validate:
  - WSUS console opens quickly
  - sync health (if upstream)
  - client scan/reporting behavior

---

## 🔒 Security & Scheduling

- ✅ Task Scheduler compatible
- ✅ GPO startup compatible (machine context)
- ✅ “Headless-friendly” execution model (logs + deterministic outputs)
- ✅ No `Get-Credential` dependency

---

## 📄 License / Author

© 2026 **Luiz Hamilton Silva** (@brazilianscriptguy). All rights reserved.
