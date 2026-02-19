# ⚙️ WSUS Management Tools

![WSUS](https://img.shields.io/badge/WSUS-Management-blue?style=for-the-badge&logo=microsoft) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?style=for-the-badge&logo=powershell&logoColor=white) ![Windows Server](https://img.shields.io/badge/Platform-Windows%20Server-0078D6?style=for-the-badge&logo=windows) ![GUI](https://img.shields.io/badge/Interface-GUI%20%7C%20Automation-4CAF50?style=for-the-badge) ![Database](https://img.shields.io/badge/SUSDB-WID%20%7C%20SQL-9C27B0?style=for-the-badge)

## 📝 Overview

The **WSUS Management Tools** suite provides an enterprise-grade, **auditable PowerShell GUI tool** for **Windows Server Update Services (WSUS)**, including end-to-end care of **SUSDB** on **Windows Internal Database (WID)** or full SQL Server.

This repository follows the same **GUI, logging, safety, and execution standards** used across **Windows-SysAdmin-ProSuite** and is built for **corporate WSUS operations**: repeatable runs, strong guardrails, predictable outputs, safe defaults, and clear audit trails.

✅ **Current flagship (all-in-one):** `Maintenance-WSUS-Admin-Tool.ps1`  
A single hardened GUI tool that consolidates preflight, inventory, WSUS cleanup/decline, and SUSDB/WID maintenance in one workflow.

**Hardened branch:** DB-first pipeline + resilient WSUS cleanup (timeouts handled) + StrictMode-safe UI settings.

---

## ✅ Key Features

### 🧰 All-in-One WSUS Maintenance GUI
- One tool for **preflight**, **inventory**, **decline**, **cleanup**, and **database maintenance**
- Corporate-friendly behavior: safe-by-default execution, deterministic sequencing, and explicit logs

### 🔎 Preflight & WSUS API Validation (Hardened)
- Automatic discovery and loading of:
  - `Microsoft.UpdateServices.Administration.dll`
  - `UpdateServices` PowerShell module (when available)
- WSUS Admin API connectivity test (server/port/SSL)
- Service validation helpers:
  - `W3SVC`, `WSUSService`
  - IIS AppPool: `WsusPool` (start-only by default; recycle is opt-in)

### 🧾 Environment Inventory (Exportable)
- Exports **JSON + CSV summary** for auditability
- Captures key WSUS/WID signals:
  - WSUS endpoint (server/port/SSL)
  - WSUS Admin API readiness
  - `wsusutil.exe` and `sqlcmd.exe` detection
  - WID / SQL connectivity validation
  - IIS/Services status and configured paths

### 🧹 Decline & Cleanup Workflow (Wizard-Aligned)
- Decline routines (policy-driven):
  - Unapproved (older-than threshold)
  - Expired
  - Superseded
  - Legacy platforms (**optional allowlist-based policy**, see notes below)
- WSUS cleanup operations (native Cleanup Wizard alignment):
  - Obsolete updates (**timeout-aware**)
  - Unneeded content files
  - Obsolete computers
  - Optional compression (guarded)

> Important: `CleanupObsoleteUpdates` can legitimately time out on large SUSDB/WID environments.  
> The tool logs the timeout and continues to the next selected cleanup action (safe behavior).

### 🗄️ SUSDB Health & Performance (WID / SQL)
- Generates SQL scripts for repeatable database maintenance:
  - `wsus-verify-fragmentation.sql` (fragmentation visibility + recommendations)
  - `wsus-reindex-smart.sql` (smart rebuild vs reorganize)
  - `wsusdbmaintenance-classic.sql` (optional classic maintenance)
- DB integrity check:
  - `DBCC CHECKDB (SUSDB) WITH NO_INFOMSGS`
- Uses `sqlcmd.exe` with robust argument quoting to avoid parsing failures.

### 🧠 Execution Model Improvements (Enterprise)
- **DB-first pipeline** option (recommended on large environments):
  - SUSDB maintenance → WSUS cleanup → decline routines
- **Single WSUS connection per run** (cache reuse across tasks)
- Resilience improvements:
  - Timeout handling per cleanup action (continues safely)
  - Avoids aggressive AppPool recycling during long cleanup phases
  - StrictMode-safe UI settings load/save (no “undefined variable” crashes)

### 📊 Logging, Reports, and Predictable Outputs
- Single-session log file (default):
  - `C:\Logs-TEMP\WSUS-GUI\Logs\Maintenance-WSUS-Admin-Tool.log`
- Timestamped inventory and reports for audit trails
- Clear step boundaries and failure visibility (INFO/WARN/ERROR)

---

## 🛠️ Prerequisites

### 1) ⚙️ PowerShell
- Windows PowerShell **5.1+** (recommended on WSUS host)

```powershell
$PSVersionTable.PSVersion
````

### 2) 🔑 Administrator Privileges

* Run **elevated** (required for WSUS Admin API operations, IIS actions, and DB tasks).

### 3) 📦 WSUS Administration Components

* WSUS must be installed and the WSUS Admin API available:

  * `Microsoft.UpdateServices.Administration.dll`
* Usually present on the WSUS server at:

  * `C:\Program Files\Update Services\Api\Microsoft.UpdateServices.Administration.dll`

### 4) 🗄️ SQLCMD Utilities (Required for SUSDB Maintenance)

* Required to run queries against WID/SUSDB (or SQL Server).
* WID named pipe (typical WSUS/WID):

```
np:\\.\pipe\MICROSOFT##WID\tsql\query
```

**sqlcmd.exe**

* The tool detects common locations (e.g. ODBC 17/18 Client SDK).
* Best practice: ensure `sqlcmd.exe` is available in `PATH`.

### 5) 🔧 Execution Policy (Session Only)

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
```

---

## 📜 Script Inventory

| Script                              | Purpose                                                                                                                                                                    |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Maintenance-WSUS-Admin-Tool.ps1** | **All-in-one** WSUS GUI: preflight, inventory export, decline & cleanup operations, SQL script generation, SUSDB maintenance (WID/SQL), enterprise sequencing + guardrails |

> Legacy helper scripts (assembly checks, inventory-only exporters, standalone SQL generators) were integrated into the main tool for a single corporate-grade workflow. They may remain for reference/testing, but the recommended operational path is the unified GUI tool.

---

## 🚀 Usage

### 🖥️ Run the WSUS Maintenance GUI (Recommended)

1. Copy `Maintenance-WSUS-Admin-Tool.ps1` to the WSUS host (or run from a secured share)
2. Right-click → **Run with PowerShell (Administrator)**
3. Confirm:

   * WSUS Server (default: local FQDN)
   * Port (default: `8530`)
   * SSL (default: `False`, unless your environment uses 8531/SSL)
4. Use **Preflight** first:

   * Admin API load
   * Connection test
   * Export inventory
   * Generate SQL scripts
5. Execute maintenance steps and review logs/reports

---

## 📁 Output Paths & Structure

Default working directory:

```
C:\Logs-TEMP\WSUS-GUI\
├── Logs\
│   ├── Maintenance-WSUS-Admin-Tool.log
│   └── Inventory\
│       ├── wsus-inventory-YYYYMMDD-HHMMSS.json
│       └── wsus-inventory-summary-YYYYMMDD-HHMMSS.csv
├── Scripts\
│   └── SUSDB\
│       ├── wsus-verify-fragmentation.sql
│       ├── wsus-reindex-smart.sql
│       └── wsusdbmaintenance-classic.sql
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

* ⏰ Run maintenance in an **overnight window**
* 📌 Recommended order on large SUSDB/WID:

  * **DB maintenance (Reindex/Stats/CheckDB) → WSUS cleanup wizard → decline routines**
* 💾 Keep backups and logs on a dedicated volume or secured share
* 🔐 Restrict execution to WSUS admins and audit all runs via exported inventory/logs
* 🧪 After maintenance, validate:

  * WSUS console responsiveness
  * sync health (if upstream)
  * client scan/reporting behavior

---

## 🧩 Optional Policy: Decline Legacy Platforms (Allowlist-Based)

Some environments require declining “legacy platform” updates, but classification/product matching is risky without an explicit allowlist.
If enabled, this action must use allowlisted patterns and a maximum decline cap to avoid accidental declines.

---

## 🔒 Security & Scheduling

* ✅ Task Scheduler compatible
* ✅ GPO startup compatible (machine context)
* ✅ Headless-friendly execution model (deterministic outputs + logs)
* ✅ No `Get-Credential` dependency

---

© 2026 **Luiz Hamilton Silva** (@brazilianscriptguy). All rights reserved.
