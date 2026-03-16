# Configuring Windows Event Log for PrintService Operational Log

## Synopsis
Configures Windows Event Log settings for the **Microsoft-Windows-PrintService/Operational** channel.

## Description
This `.reg` configuration automates key Event Log parameters to support reliable PrintService logging, including:

- `AutoBackupLogFiles`
- `Flags`
- Log file path (`File`)
- Maximum size (`MaxSize` / `MaxSizeUpper`)
- Retention policy (`Retention`)

## Author
Luiz Hamilton Silva — `@brazilianscriptguy`

## Version
**Last Updated:** 2024-11-26

## Notes
- Ensure the target log path (registry value `File`) exists and is reachable by the **Local System** context.
- Apply the `.reg` file with **administrative privileges** (or deploy via **GPO**) to ensure registry changes succeed.

---

## Deployment Instructions

### 1) Save the `.reg` file
Save the provided registry content as:

- **Filename:** `PrintService-Operacional-EventLogs.reg`

### 2) Store it in a shared location
Place the file on a shared path accessible to target machines (ensure **read access** for the accounts/computers applying the change).

### 3) Deploy via Group Policy Object (GPO)
1. Open **Group Policy Management Console (GPMC)**:
   - Press `Win + R`, type `gpmc.msc`, press `Enter`.
2. Create or edit a GPO linked to the target OU.
3. Navigate to:
   - `Computer Configuration` → `Preferences` → `Windows Settings` → `Registry`
4. Create Registry Items with the following settings:
   - **Action:** `Update`
   - **Hive:** `HKEY_LOCAL_MACHINE`
   - **Key Path:** `SYSTEM\ControlSet001\Services\EventLog\Microsoft-Windows-PrintService/Operational`
   - **Values:**
     - `AutoBackupLogFiles` (`DWORD`) = `1`
     - `Flags` (`DWORD`) = `1`
     - `File` (`REG_SZ`) = `L:\Microsoft-Windows-PrintService-Operational\Microsoft-Windows-PrintService-Operational.evtx`
     - `MaxSize` (`DWORD`) = `09270000`
     - `MaxSizeUpper` (`DWORD`) = `00000000`
     - `Retention` (`DWORD`) = `ffffffff`

### 4) Force policy update
Run:

```powershell
gpupdate /force
```

Or reboot the machine to apply the GPO at startup.

### 5) Verify registry changes
Confirm the values exist at:

`HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\EventLog\Microsoft-Windows-PrintService/Operational`

### 6) Monitor logs
Confirm the `.evtx` log file is being created/updated at:

`L:\Microsoft-Windows-PrintService-Operational\`

---

## Best Practices
- Backup the registry and test on a single machine before wide deployment.
- Validate that `L:` is consistently available on all endpoints (mapping, permissions, connectivity).
- Secure the log storage location to prevent tampering (ACLs, monitoring, write restrictions).
