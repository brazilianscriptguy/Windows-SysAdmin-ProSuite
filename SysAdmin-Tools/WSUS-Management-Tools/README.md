# Maintenance-WSUS-Admin-Tool.ps1

### Purpose:
A professional PowerShell GUI tool for **automated WSUS cleanup** and **Windows Internal Database (WID)** maintenance — including update declines, WSUS API cleanups, and optional DBCC tasks on SUSDB.

---

## Features

- ✔️ Declines unapproved, superseded, and expired updates
- ✔️ Executes WSUS cleanup operations through official WSUS API
- ✔️ Optional `CompressUpdates` toggle (via GUI checkbox)
- ✔️ Full support for `WID` (Windows Internal Database)
- ✔️ GUI-driven execution — no console interaction required
- ✔️ Executes:
  - `DBCC CHECKDB`
  - Reindex (with `sp_MSforeachtable`)
  - Shrink SUSDB
- ✔️ Real-time progress bar with status feedback
- ✔️ Persistent log and CSV report to `C:\Logs-TEMP`

---

## Usage

1. **Run with Administrator privileges**
2. Double-click the script or run:
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\Maintenance-WSUS-Admin-Tool.ps1
