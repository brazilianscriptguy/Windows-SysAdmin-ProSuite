# ⚙️ WSUS Management Tools

![WSUS](https://img.shields.io/badge/WSUS-Management-blue?style=for-the-badge&logo=microsoft)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![Windows Server](https://img.shields.io/badge/Platform-Windows%20Server-0078D6?style=for-the-badge&logo=windows)
![GUI](https://img.shields.io/badge/Interface-GUI%20%7C%20Automation-4CAF50?style=for-the-badge)
![Database](https://img.shields.io/badge/SUSDB-WID%20%7C%20SQL-9C27B0?style=for-the-badge)

---

## 📝 Overview

The **WSUS Management Tools** suite delivers an enterprise-grade, fully auditable **PowerShell GUI solution** for managing **Windows Server Update Services (WSUS)**, including structured maintenance of **SUSDB** on both **Windows Internal Database (WID)** and full **SQL Server** deployments.

This repository follows the same **GUI standards, logging model, execution safeguards, and operational patterns** used across **Windows-SysAdmin-ProSuite**. It is designed for corporate environments requiring:

- Repeatable execution
- Deterministic sequencing
- Safe defaults
- Guardrails against destructive actions
- Clear audit trails and structured logs

---

✅ **Current Flagship (All-in-One Tool)**  
`Maintenance-WSUS-Admin-Tool.ps1`

A hardened, consolidated GUI that integrates:

- Preflight validation
- Environment inventory
- Decline routines
- Cleanup execution
- SUSDB/WID SQL maintenance
- Enterprise-grade sequencing controls

**Hardened Branch Includes:**
- Database-first execution pipeline
- Resilient cleanup (timeout-aware continuation)
- StrictMode-compliant UI configuration handling

---

## ✅ Key Capabilities

### 🧰 Unified WSUS Maintenance GUI

- Single consolidated tool for:
  - Preflight validation
  - Inventory export
  - Decline & cleanup operations
  - SQL script generation
  - SUSDB maintenance
- Safe-by-default execution model
- Explicit logging boundaries and deterministic flow

---

### 🔎 Preflight & WSUS API Validation (Hardened)

Automatic validation and discovery of:

- `Microsoft.UpdateServices.Administration.dll`
- `UpdateServices` PowerShell module (when present)

Includes:

- WSUS Admin API connectivity validation (server / port / SSL)
- Service validation:
  - `W3SVC`
  - `WSUSService`
- IIS Application Pool validation:
  - `WsusPool` (start-only by default; recycle is opt-in)

---

### 🧾 Environment Inventory (Exportable & Auditable)

Exports structured **JSON + CSV summaries** capturing:

- WSUS endpoint (server / port / SSL)
- WSUS Admin API readiness
- `wsusutil.exe` detection
- `sqlcmd.exe` detection
- WID / SQL connectivity validation
- IIS and service states
- Configured WSUS paths

Designed for compliance evidence and operational auditing.

---

### 🧹 Decline & Cleanup Workflow (Wizard-Aligned)

Decline routines (policy-driven):

- Unapproved updates (older-than threshold)
- Expired updates
- Superseded updates
- Optional legacy platform declines (allowlist-based policy)

WSUS Cleanup Wizard-aligned operations:

- Obsolete updates (**timeout-aware**)
- Unneeded content files
- Obsolete computers
- Optional compression (guarded execution)

> ⚠️ Note: `CleanupObsoleteUpdates` may legitimately time out on large SUSDB/WID deployments.  
> The tool logs the timeout event and continues safely with remaining selected actions.

---

### 🗄️ SUSDB Health & Performance (WID / SQL Server)

Structured SQL maintenance scripts generated for repeatable database optimization:

- `wsus-verify-fragmentation.sql` — Fragmentation visibility and recommendations
- `wsus-reindex-smart.sql` — Dynamic REORGANIZE (<30%) vs REBUILD (≥30%)
- `SUSDB-WID-IndexMaintenance-Reindex-UpdateStats.sql` — Full enterprise maintenance (Microsoft-recommended indexes + dynamic reindex + statistics update)
- `wsusdbmaintenance-classic.sql` — Optional legacy maintenance routine

Database integrity validation:

- `DBCC CHECKDB (SUSDB) WITH NO_INFOMSGS`

Execution model:

- Uses `sqlcmd.exe` with robust argument quoting
- Prevents command parsing failures in scheduled or automated contexts

---

### 🧠 Enterprise Execution Model Enhancements

**Database-first pipeline (recommended for large environments):**

1. SUSDB index maintenance  
2. WSUS cleanup operations  
3. Decline routines  

Additional architectural improvements:

- Single WSUS server connection per execution cycle (connection reuse)
- Per-action timeout handling
- No aggressive IIS AppPool recycling during long maintenance
- StrictMode-safe UI configuration persistence

---

### 📊 Logging, Reports & Deterministic Outputs

Default session log:

```

C:\Logs-TEMP\WSUS-GUI\Logs\Maintenance-WSUS-Admin-Tool.log

````

Includes:

- Structured INFO / WARN / ERROR boundaries
- Timestamped inventory exports
- Predictable output paths
- Clear failure visibility

---

## 🛠️ Prerequisites

### 1️⃣ PowerShell

- Windows PowerShell **5.1+** (recommended on WSUS host)

```powershell
$PSVersionTable.PSVersion
````

---

### 2️⃣ Administrator Privileges

* Execution must be elevated
* Required for:

  * WSUS Admin API operations
  * IIS interaction
  * Database tasks

---

### 3️⃣ WSUS Administration Components

Required:

* `Microsoft.UpdateServices.Administration.dll`

Default location:

```
C:\Program Files\Update Services\Api\
```

---

### 4️⃣ SQLCMD Utilities (Required for SUSDB Maintenance)

Required to query WID or SQL Server.

Typical WID named pipe:

```
np:\\.\pipe\MICROSOFT##WID\tsql\query
```

`sqlcmd.exe` must be:

* Installed (ODBC 17/18 Client SDK commonly used)
* Available in system `PATH`

---

### 5️⃣ Execution Policy (Session Scope Recommended)

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
```

---

## 📜 Script Inventory

| Script                              | Purpose                                                                                                                                                                                        |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Maintenance-WSUS-Admin-Tool.ps1** | Consolidated enterprise WSUS GUI: preflight validation, inventory export, decline & cleanup operations, SQL generation, SUSDB maintenance (WID/SQL), sequencing controls and safety guardrails |

> Legacy helper scripts were consolidated into the main GUI tool. They may remain for testing/reference, but production usage should rely on the unified tool.

---

## 🚀 Usage (Recommended Workflow)

1. Copy `Maintenance-WSUS-Admin-Tool.ps1` to the WSUS host
2. Run **as Administrator**
3. Confirm:

   * WSUS Server (default: local FQDN)
   * Port (default: 8530)
   * SSL setting (if applicable)
4. Execute **Preflight**
5. Review inventory export
6. Run maintenance steps
7. Review logs and SQL output

---

## 📁 Output Structure

Default base directory:

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
│       ├── SUSDB-WID-IndexMaintenance-Reindex-UpdateStats.sql
│       └── wsusdbmaintenance-classic.sql
└── settings.json
```

Optional SQL generation path:

```
C:\Scripts\SUSDB\
├── wsus-verify-fragmentation.sql
├── wsus-reindex-smart.sql
├── SUSDB-WID-IndexMaintenance-Reindex-UpdateStats.sql
└── wsusdbmaintenance-classic.sql
```

---

## 💡 Corporate Operational Best Practices

* Schedule maintenance during off-peak hours
* Recommended order for large SUSDB/WID environments:

  * Database maintenance → WSUS cleanup → Decline routines
* Maintain backups before database maintenance
* Restrict execution to WSUS administrators
* Post-maintenance validation:

  * WSUS console responsiveness
  * Sync health
  * Client reporting behavior

---

## 🧩 Optional Policy: Legacy Platform Decline (Allowlist-Based)

Declining legacy platform updates requires strict allowlisting.

If enabled:

* Must use approved product/classification patterns
* Must enforce maximum decline cap
* Should always log declined update IDs

---

## 🔒 Security & Scheduling

* Task Scheduler compatible
* GPO startup compatible (machine context)
* Headless-friendly deterministic execution model
* No `Get-Credential` dependency
* Designed for enterprise auditability

---

© 2026 **Luiz Hamilton Silva** (@brazilianscriptguy). All rights reserved.
