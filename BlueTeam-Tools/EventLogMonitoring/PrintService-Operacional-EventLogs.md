## What’s repeated (and why)

Yes — you have **the same content twice**, just in two formats:

- **Markdown section** (starts with `# Configuring Windows Event Log...`)
- **HTML section** (starts with `<div><h1>🖨️ Configuring Windows Event Log...`)

They repeat the same fields:

- Title / Synopsis / Description / Author / Version / Notes  
- Deployment instructions (steps 1–6)
- Best practices and final notes
- Closing paragraph

So the “repeatable information” is not small redundancy inside the Markdown; it’s a **full duplication** because both Markdown and HTML versions were included.

---

## Recommended revision: keep ONE format (Markdown) and remove the HTML block

Below is a cleaned, non-duplicated Markdown-only version (same meaning, tighter wording, and no repeated blocks):

```markdown
# Configuring Windows Event Log for PrintService Operational Log

## Synopsis
Configures Windows Event Log settings for the **Microsoft-Windows-PrintService/Operational** channel.

## Description
This `.reg` configuration automates key Event Log parameters such as `AutoBackupLogFiles`, `Flags`, log file path (`File`), maximum size (`MaxSize` / `MaxSizeUpper`), and retention (`Retention`) to support reliable PrintService logging.

## Author
Luiz Hamilton Silva — @brazilianscriptguy

## Version
Last Updated: November 26, 2024

## Notes
- Ensure the target log path (value `File`) exists and is reachable by the system.
- Apply the `.reg` with administrative privileges (or deploy via GPO) to ensure registry changes succeed.

## Deployment Instructions

### 1) Save the `.reg` file
Save the provided registry content as:
`PrintService-Operacional-EventLogs.reg`

### 2) Store it in a shared location
Place the file on a shared path accessible to target machines (read access for the accounts applying the change).

### 3) Deploy via Group Policy Object (GPO)
1. Open **GPMC** (`gpmc.msc`)
2. Create/edit a GPO linked to the target OU
3. Go to: `Computer Configuration` → `Preferences` → `Windows Settings` → `Registry`
4. Create Registry Items with:
   - **Action:** Update  
   - **Hive:** `HKEY_LOCAL_MACHINE`  
   - **Key Path:** `SYSTEM\ControlSet001\Services\EventLog\Microsoft-Windows-PrintService/Operational`  
   - **Values:**
     - `AutoBackupLogFiles` (DWORD) = `1`
     - `Flags` (DWORD) = `1`
     - `File` (REG_SZ) = `L:\Microsoft-Windows-PrintService-Operational\Microsoft-Windows-PrintService-Operational.evtx`
     - `MaxSize` (DWORD) = `09270000`
     - `MaxSizeUpper` (DWORD) = `00000000`
     - `Retention` (DWORD) = `ffffffff`

### 4) Force policy update
```powershell
gpupdate /force
```
(or reboot)

### 5) Verify registry
Check:
`HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\EventLog\Microsoft-Windows-PrintService/Operational`

### 6) Monitor logs
Confirm the `.evtx` is being created/updated at:
`L:\Microsoft-Windows-PrintService-Operational\`

## Best Practices
- Backup registry / test on a single machine first.
- Validate that `L:` is consistently available on all endpoints (mapping/permissions).
- Secure the log storage location against tampering.
```

---

## One important consistency note (optional but recommended)
Your key path alternates between:

- `Microsoft-Windows-PrintService/Operational` (with `/`)
- `Microsoft-Windows-PrintService\Operational` (with `\`)

In Windows Registry paths, it’s typically shown with backslashes. If you want maximum clarity, standardize the documentation to **one** form (I’d use `Microsoft-Windows-PrintService/Operational` only when referring to the *Event Log channel name*, and `...\Microsoft-Windows-PrintService\Operational` when referring to the *registry key path*).

If you tell me which one your `.reg` actually uses, I’ll align the text precisely to match it.
