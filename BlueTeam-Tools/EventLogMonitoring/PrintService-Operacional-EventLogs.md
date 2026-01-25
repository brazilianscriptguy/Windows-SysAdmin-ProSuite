# 🖨️ Configuring Windows Event Log for PrintService Operational Log

## 📝 Synopsis

Configures Windows Event Log settings for the **PrintService Operational** log.

## 📖 Description

This registry file automates the configuration of the Windows Event Log for the **PrintService Operational** channel. It sets parameters such as `AutoBackupLogFiles`, `Flags`, log file location, maximum log size, and retention policy to ensure efficient logging and management of print services.

## 👤 Author

**Luiz Hamilton Silva** - [@brazilianscriptguy](https://github.com/brazilianscriptguy)

## 📌 Version

**Last Updated:** November 26, 2024

## 📝 Notes

- Ensure that the specified log file path (`File`) exists and is accessible
- This configuration is essential for maintaining and managing print service logs efficiently
- Apply the `PrintService-Operacional-EventLogs.reg` file with administrative privileges to ensure successful registry modifications

---

## 🚀 Deployment Instructions

### 1️⃣ Save the Registry File

Save the registry configurations into a file named `PrintService-Operacional-EventLogs.reg`.

### 2️⃣ Store Securely

Place the `PrintService-Operacional-EventLogs.reg` file in a **shared network location** accessible by all target machines. Ensure that the share permissions allow **read access** for the `Authenticated Users` group or specific accounts that will apply the registry settings.

### 3️⃣ Deploy via Group Policy Object (GPO)

#### Open Group Policy Management Console (GPMC)
- Press `Win + R`, type `gpmc.msc`, and press `Enter`

#### Create or Edit a GPO
- **Right-click** on the desired **Organizational Unit (OU)**
- Select **"Create a GPO in this domain, and Link it here..."** or edit an existing GPO

#### Navigate to Preferences
- Go to `Computer Configuration` → `Preferences` → `Windows Settings` → `Registry`

#### Create New Registry Items
For each registry value defined in the `PrintService-Operacional-EventLogs.reg` file, create a corresponding registry item in the GPO:

1. **Right-click** on **Registry** and select **"New" → "Registry Item"**
2. **Configure the Registry Item:**
   - **Action:** Select **"Update"**
   - **Hive:** Select `HKEY_LOCAL_MACHINE`
   - **Key Path:** Enter `SYSTEM\ControlSet001\Services\EventLog\Microsoft-Windows-PrintService/Operational`
   - **Value Name and Type:**
     - `AutoBackupLogFiles`: `DWORD` = `1`
     - `Flags`: `DWORD` = `1`
     - `File`: `REG_SZ` = `L:\Microsoft-Windows-PrintService-Operational\Microsoft-Windows-PrintService-Operational.evtx`
     - `MaxSize`: `DWORD` = `09270000`
     - `MaxSizeUpper`: `DWORD` = `00000000`
     - `Retention`: `DWORD` = `ffffffff`
3. **Repeat** the above steps for each registry value

#### Apply and Close
- After configuring all registry values, click **"OK"** to save the settings
- Click **"Apply"** and **"OK"** to close the GPO editor

### 4️⃣ Force Group Policy Update

On target machines, expedite the policy application by running:

```cmd
gpupdate /force
