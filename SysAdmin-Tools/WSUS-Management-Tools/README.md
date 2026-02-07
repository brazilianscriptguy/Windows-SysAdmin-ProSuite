# ⚙️ WSUS Management Tools

![WSUS](https://img.shields.io/badge/WSUS-Management-blue?style=for-the-badge&logo=microsoft) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?style=for-the-badge&logo=powershell&logoColor=white) ![Windows Server](https://img.shields.io/badge/Platform-Windows%20Server-0078D6?style=for-the-badge&logo=windows) ![GUI](https://img.shields.io/badge/Interface-GUI%20%7C%20Automation-4CAF50?style=for-the-badge) ![Database](https://img.shields.io/badge/SUSDB-WID%20%7C%20SQL-9C27B0?style=for-the-badge)

## 📝 Overview

The **WSUS Management Tools** suite provides a comprehensive and enterprise-grade set of **PowerShell tools** for maintaining, auditing, and optimizing **Windows Server Update Services (WSUS)** and its **SUSDB (Windows Internal Database)**.

These tools are aligned with the same **design, logging, GUI, and execution standards** used across the *Windows‑SysAdmin‑ProSuite*, supporting both **standalone WSUS servers** and **Active Directory–integrated environments**.

They are built to reduce operational risk, improve database performance, and provide **auditable, repeatable WSUS maintenance workflows**.

---

## ✅ Key Features

- 🖥️ **GUI‑Driven Maintenance**  
  Perform complex WSUS tasks without command-line interaction

- 🗄️ **SUSDB Health & Performance**
  - Fragmentation analysis
  - Smart index reorganization vs rebuild
  - Statistics update and integrity checks

- 🧩 **WSUS Assembly Validation**
  - Automatic detection and loading of `Microsoft.UpdateServices.Administration.dll`
  - Clear guidance when WSUS Admin components are missing

- 📊 **Structured Logging & Reporting**
  - `.log` (execution trace)
  - `.csv` (decline counts, cleanup metrics)
  - Timestamped, session‑scoped outputs

- 📈 **Weighted Progress Tracking**
  - Real progress bar capped at 100%
  - Phased execution (decline → cleanup → database)

- 🧱 **Enterprise‑Ready Design**
  - Modular scripts
  - GUI + non‑interactive execution
  - Safe for Task Scheduler and GPO execution

---

## 🛠️ Prerequisites

### 1. ⚙️ PowerShell
- Windows PowerShell **5.1 or later**
```powershell
$PSVersionTable.PSVersion
```

### 2. 🔑 Administrator Privileges
- Must be executed **elevated**
- Required for WSUS API access and SUSDB maintenance

### 3. 📦 Required Components

- **WSUS Administration Console**
  - Provides `UpdateServices` module
  - Installs WSUS Admin assemblies

- **PowerShell Modules**
  - `UpdateServices`
  - `ActiveDirectory` *(optional, for WSUS discovery)*

### 4. 🗄️ SQLCMD Utilities
- Required to execute maintenance queries on WID / SUSDB
- Named pipe:
```
np:\\.\pipe\MICROSOFT##WID\tsql\query
```
- Ensure `sqlcmd.exe` is installed and available in `PATH`

### 5. 🔧 Execution Policy
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
```

### 6. 📄 Required SQL Scripts
Location:
```
C:\Logs-TEMP\WSUS-GUI\Scripts\
```

- `wsus-verify-fragmentation.sql`
- `wsus-reindex-smart.sql`

### 7. 📦 WSUS Admin Assembly
- `Microsoft.UpdateServices.Administration.dll`
- Automatically validated by:
  - `Check-WSUS-AdminAssembly.ps1`

---

## 📜 Script Descriptions

| Script | Purpose |
|------|--------|
| **Check-WSUS-AdminAssembly.ps1** | Detects and loads WSUS Admin assemblies, validates WSUS tooling |
| **Generate-WSUSReindexScript.ps1** | Generates adaptive reindex T‑SQL based on fragmentation thresholds |
| **Maintenance-WSUS-Admin-Tool.ps1** | Full GUI‑based WSUS maintenance: decline, cleanup, SUSDB optimization |

---

## 🚀 Usage

### 🖥️ WSUS Maintenance GUI

1. Right‑click **Maintenance-WSUS-Admin-Tool.ps1**
2. Select **Run with PowerShell (Administrator)**
3. Confirm WSUS server and port (default: local FQDN / `8530`)
4. Select maintenance tasks
5. Monitor execution via GUI and logs

---

### 🗄️ Generate Smart Reindex Script

```powershell
.\Generate-WSUSReindexScript.ps1
```

---

### 🧩 Validate WSUS Assemblies

```powershell
.\Check-WSUS-AdminAssembly.ps1
```

---

## 📁 Supporting Files & Structure

```
C:\Logs-TEMP\WSUS-GUI\
├── Scripts\
├── Logs\
├── CSV\
├── Backups\
└── settings.json
```

---

## 💡 Operational Best Practices

- ⏰ Schedule maintenance overnight
- 🔐 Use least-privilege WSUS admin accounts
- 📁 Centralize logs to a UNC path
- 🧪 Always verify before rebuild

---

## 🔒 Security & Scheduling

- Task Scheduler compatible
- GPO startup compatible
- Headless execution supported

---

© 2026 Luiz Hamilton Silva. All rights reserved.
