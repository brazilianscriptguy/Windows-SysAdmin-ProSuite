# ⚙️ WSUS Management Tools

## 📝 Overview
The **WSUS Management Tools** repository provides a curated set of **PowerShell scripts** to automate, maintain, and optimize **Windows Server Update Services (WSUS)** and its **SUSDB (Windows Internal Database)**.  
These tools are designed for **Active Directory** and **standalone** environments, with a lightweight **GUI** for administrators.

---

## ✅ Key Features
- **Graphical Interface**: Run maintenance tasks via GUI (no command line required)  
- **Index Optimization**: Reports fragmentation and generates **smart reindex scripts** for SUSDB  
- **Assembly Detection**: Validates and loads WSUS Admin assemblies from the GAC or known paths  
- **Centralized Logging**: `.log` and `.csv` outputs with structured, timestamped entries  
- **Modular Design**: Scripts can run standalone or be scheduled with Task Scheduler/GPO  

---

## 🛠️ Prerequisites

1. **PowerShell**  
   - Requires **Windows PowerShell 5.1+**  
   ```powershell
   $PSVersionTable.PSVersion
   ```

2. **Administrator Privileges**  
   - Must be run **elevated** to access WSUS APIs and SUSDB

3. **Required Modules**  
   - `UpdateServices` (included with the WSUS Administration Console / Tools)  
   - `ActiveDirectory` *(optional, for WSUS server discovery)*

4. **SQLCMD Tools**  
   - Required to execute SQL scripts on SUSDB (via named pipe: `np:\\.\pipe\MICROSOFT##WID\tsql\query`)  
   - Ensure **`sqlcmd.exe`** is installed and on your `PATH`

5. **Execution Policy**  
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
   ```

6. **SQL Script Files** (copy into `C:\Logs-TEMP\WSUS-GUI\Scripts`)  
   - `wsus-verify-fragmentation.sql`  
   - `wsus-reindex-smart.sql`

7. **WSUS Admin Assembly**  
   - Ensure `Microsoft.UpdateServices.Administration.dll` is available in the **GAC**  
   - Validate with **Check-WSUS-AdminAssembly.ps1**

---

## 📜 Script Descriptions

| Script | Function |
|--------|----------|
| **Check-WSUS-AdminAssembly.ps1** | Detects/loads `Microsoft.UpdateServices.Administration.dll`; guides installation if missing |
| **Generate-WSUSReindexScript.ps1** | Prompts thresholds and generates `wsus-reindex-smart.sql` for SUSDB index maintenance |
| **Maintenance-WSUS-Admin-Tool.ps1** | GUI: decline updates (expired, superseded, unapproved), cleanup obsolete files/computers, SUSDB tasks (CHECKDB, shrink, reindex, backup) |

---

## 🚀 Usage

### GUI Tool
1. Right-click **Maintenance-WSUS-Admin-Tool.ps1** → **Run with PowerShell (Admin)**  
2. Configure WSUS server (defaults to **local FQDN** and port `8530` if missing)  
3. Select maintenance tasks (check boxes)  
4. Run and monitor execution in the status window and log  

### Index Reindex Script
Generate a smart T-SQL script:
```powershell
.\Generate-WSUSReindexScript.ps1
```
The script creates `wsus-reindex-smart.sql` with logic to reorganize or rebuild indexes based on thresholds.

### Assembly Validation
Check if the WSUS Administration assembly is installed and loadable:
```powershell
.\Check-WSUS-AdminAssembly.ps1
```

---

## 📁 Complementary Files
- `wsus-verify-fragmentation.sql` → SUSDB fragmentation report  
- `wsus-reindex-smart.sql` → Smart reindex logic (skip low pages, reorganize vs rebuild)  
- `settings.json` → GUI persistence file  
- `Logs\` → Example: `Maintenance-WSUS-Admin-Tool-20250915-095431.log`

---

## 💡 Tips
- **Logs & Configs**  
  - Logs: `C:\Logs-TEMP\WSUS-GUI\Logs\`  
  - CSV: `C:\Logs-TEMP\WSUS-GUI\CSV\`  
  - Backups: `C:\Logs-TEMP\WSUS-GUI\Backups\`  
  - Settings: `C:\Logs-TEMP\WSUS-GUI\settings.json`

- **Console Visibility**  
  - GUI hides the console window by default  
  - Comment out the *Hide Console* block in scripts while debugging

- **Timeout Handling**  
  - Some WSUS builds lack `DatabaseCommandTimeout`; this is logged as `[DEBUG]`  
  - **CompressUpdates** may time out — run standalone during off-hours if needed

---

## 🧰 Troubleshooting

- **`sqlcmd.exe` not found** → Install SQL Server Command Line Utilities and add to PATH  
- **`Get-WsusServer failed`** → Ensure WSUS Admin Console is installed and run PowerShell as Admin  
- **WinRM errors in remote mode** → Enable remoting with:  
  ```powershell
  Enable-PSRemoting -Force
  ```

---

## 🔒 Scheduling & Security
- Use **Task Scheduler** or **GPO** for recurring maintenance (overnight)  
- Centralize logs by redirecting `$LogDir` to a UNC path  
- Always run as a **WSUS Administrator** account (least privilege recommended)
  
