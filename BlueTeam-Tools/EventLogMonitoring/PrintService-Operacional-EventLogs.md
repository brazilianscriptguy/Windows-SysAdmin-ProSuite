# Configuring Windows Event Log for PrintService Operational Log

## .SYNOPSIS

Configures Windows Event Log settings for the PrintService Operational log.

## .DESCRIPTION

This registry file automates the configuration of the Windows Event Log for the PrintService Operational channel. It sets parameters such as `AutoBackupLogFiles`, `Flags`, log file location, maximum log size, and retention policy to ensure efficient logging and management of print services.

## .AUTHOR

Luiz Hamilton Silva - @brazilianscriptguy

## .VERSION

Last Updated: November 26, 2024

## .NOTES

- Ensure that the specified log file path (`"File"`) exists and is accessible.
- This configuration is essential for maintaining and managing print service logs efficiently.
- Apply the `PrintService-Operacional-EventLogs.reg` file with administrative privileges to ensure successful registry modifications.

## Deployment Instructions

### 1. Save the `PrintService-Operacional-EventLogs.reg` File

Save the registry configurations provided above into a file named `PrintService-Operacional-EventLogs.reg`.

### 2. Store the `.reg` File Securely

Place the `PrintService-Operacional-EventLogs.reg` file in a **shared network location** accessible by all target machines. Ensure that the share permissions allow **read access** for the **Authenticated Users** group or the specific accounts that will apply the registry settings.

### 3. Deploy via Group Policy Object (GPO)

#### a. Open Group Policy Management Console (GPMC)

- Press `Win + R`, type `gpmc.msc`, and press **Enter**.

#### b. Create or Edit a GPO

- **Right-click** on the desired **Organizational Unit (OU)**.
- Select **"Create a GPO in this domain, and Link it here..."** or **edit** an existing GPO.

#### c. Navigate to Preferences

- Go to `Computer Configuration` → `Preferences` → `Windows Settings` → `Registry`.

#### d. Create New Registry Items

For each registry value defined in the `PrintService-Operacional-EventLogs.reg` file, create a corresponding registry item in the GPO:

1. **Right-click** on **Registry** and select **"New"** → **"Registry Item"**.

2. **Configure the Registry Item**:

   - **Action**: Select **"Update"**.
   - **Hive**: Select **"HKEY_LOCAL_MACHINE"**.
   - **Key Path**: Enter `SYSTEM\ControlSet001\Services\EventLog\Microsoft-Windows-PrintService/Operational`.
   - **Value Name and Type**:
     - **AutoBackupLogFiles**: `DWORD` = `1`
     - **Flags**: `DWORD` = `1`
     - **File**: `REG_SZ` = `L:\Microsoft-Windows-PrintService-Operational\Microsoft-Windows-PrintService-Operational.evtx`
     - **MaxSize**: `DWORD` = `09270000`
     - **MaxSizeUpper**: `DWORD` = `00000000`
     - **Retention**: `DWORD` = `ffffffff`

3. **Repeat** the above steps for each registry value.

#### e. Apply and Close

After configuring all registry values, click **"OK"** to save the settings. Then, click **"Apply"** and **"OK"** to close the GPO editor.

### 4. Force Group Policy Update

On target machines, expedite the policy application by running:

```powershell
gpupdate /force
```

Alternatively, restart the machines to allow GPO to apply the settings during startup.

### 5. Verify Registry Changes

After deployment, on a target machine, open **Registry Editor** (`regedit`) and navigate to:

```
HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\EventLog\Microsoft-Windows-PrintService/Operational
```

Ensure that all the specified values are correctly set.

### 6. Monitor Logs

Check the log file location (`L:\Microsoft-Windows-PrintService-Operational\`) to verify that the `Microsoft-Windows-PrintService-Operational.evtx` log file is being created and updated as per the configurations.

## Best Practices and Final Notes

- **Backup Registry Before Changes**:
  - Always create a backup of the registry before applying changes, especially in a production environment.
  
- **Test on a Single Machine**:
  - Before wide-scale deployment, apply the `.reg` file to a single test machine to ensure it behaves as expected.

- **Ensure Network Share Accessibility**:
  - Verify that the drive letter `L:` is correctly mapped on all target machines and that the specified path exists.
  
- **Monitor Event Logs**:
  - Regularly monitor the Application Event Logs for any errors related to the registry changes or the PrintService Operational logs.
  
- **Documentation**:
  - Maintain documentation of all registry changes for future reference and troubleshooting.
  
- **Security Considerations**:
  - Ensure that the network share containing the log files is secured and accessible only by authorized users to prevent unauthorized access or tampering.

---

*By incorporating this well-documented `PrintService-Operacional-EventLogs.reg` file into your deployment strategy, you ensure consistent and efficient configuration of the PrintService Operational event logs across all target machines in your network.* 
<div>
  <h1>🖨️ Configuring Windows Event Log for PrintService Operational Log</h1>

  <h2>📝 SYNOPSIS</h2>
  <p>Configures Windows Event Log settings for the <strong>PrintService Operational</strong> log.</p>

  <h2>📖 DESCRIPTION</h2>
  <p>
    This registry file automates the configuration of the Windows Event Log for the 
    <strong>PrintService Operational</strong> channel. It sets parameters such as 
    <code>AutoBackupLogFiles</code>, <code>Flags</code>, log file location, maximum log size, 
    and retention policy to ensure efficient logging and management of print services.
  </p>

  <h2>👤 AUTHOR</h2>
  <p><strong>Luiz Hamilton Silva</strong> - @brazilianscriptguy</p>

  <h2>📌 VERSION</h2>
  <p><strong>Last Updated:</strong> November 26, 2024</p>

  <h2>📝 NOTES</h2>
  <ul>
    <li>Ensure that the specified log file path (<code>"File"</code>) exists and is accessible.</li>
    <li>This configuration is essential for maintaining and managing print service logs efficiently.</li>
    <li>Apply the <code>PrintService-Operacional-EventLogs.reg</code> file with administrative privileges 
        to ensure successful registry modifications.</li>
  </ul>

  <hr />

  <h2>🚀 Deployment Instructions</h2>

  <h3>1️⃣ Save the <code>PrintService-Operacional-EventLogs.reg</code> File</h3>
  <p>Save the registry configurations provided above into a file named 
    <code>PrintService-Operacional-EventLogs.reg</code>.
  </p>

  <h3>2️⃣ Store the <code>.reg</code> File Securely</h3>
  <p>
    Place the <code>PrintService-Operacional-EventLogs.reg</code> file in a 
    <strong>shared network location</strong> accessible by all target machines. 
    Ensure that the share permissions allow <strong>read access</strong> for the 
    <code>Authenticated Users</code> group or specific accounts that will apply the registry settings.
  </p>

  <h3>3️⃣ Deploy via Group Policy Object (GPO)</h3>

  <h4>➡️ Open Group Policy Management Console (GPMC)</h4>
  <ul>
    <li>Press <kbd>Win + R</kbd>, type <code>gpmc.msc</code>, and press <kbd>Enter</kbd>.</li>
  </ul>

  <h4>➡️ Create or Edit a GPO</h4>
  <ul>
    <li><strong>Right-click</strong> on the desired <strong>Organizational Unit (OU)</strong>.</li>
    <li>Select <strong>"Create a GPO in this domain, and Link it here..."</strong> or edit an existing GPO.</li>
  </ul>

  <h4>➡️ Navigate to Preferences</h4>
  <ul>
    <li>Go to <code>Computer Configuration</code> → <code>Preferences</code> → <code>Windows Settings</code> → <code>Registry</code>.</li>
  </ul>

  <h4>➡️ Create New Registry Items</h4>
  <p>For each registry value defined in the <code>PrintService-Operacional-EventLogs.reg</code> file, 
     create a corresponding registry item in the GPO:
  </p>
  <ol>
    <li><strong>Right-click</strong> on <strong>Registry</strong> and select <strong>"New" → "Registry Item"</strong>.</li>
    <li><strong>Configure the Registry Item:</strong></li>
    <ul>
      <li><strong>Action:</strong> Select <strong>"Update"</strong>.</li>
      <li><strong>Hive:</strong> Select <code>"HKEY_LOCAL_MACHINE"</code>.</li>
      <li><strong>Key Path:</strong> Enter <code>SYSTEM\ControlSet001\Services\EventLog\Microsoft-Windows-PrintService/Operational</code>.</li>
      <li><strong>Value Name and Type:</strong></li>
      <ul>
        <li><code>AutoBackupLogFiles</code>: <code>DWORD</code> = <code>1</code></li>
        <li><code>Flags</code>: <code>DWORD</code> = <code>1</code></li>
        <li><code>File</code>: <code>REG_SZ</code> = <code>L:\Microsoft-Windows-PrintService-Operational\Microsoft-Windows-PrintService-Operational.evtx</code></li>
        <li><code>MaxSize</code>: <code>DWORD</code> = <code>09270000</code></li>
        <li><code>MaxSizeUpper</code>: <code>DWORD</code> = <code>00000000</code></li>
        <li><code>Retention</code>: <code>DWORD</code> = <code>ffffffff</code></li>
      </ul>
    </ul>
    <li><strong>Repeat</strong> the above steps for each registry value.</li>
  </ol>

  <h4>➡️ Apply and Close</h4>
  <ul>
    <li>After configuring all registry values, click <strong>"OK"</strong> to save the settings.</li>
    <li>Click <strong>"Apply"</strong> and <strong>"OK"</strong> to close the GPO editor.</li>
  </ul>

  <h3>4️⃣ Force Group Policy Update</h3>
  <p>On target machines, expedite the policy application by running:</p>
  <pre><code>gpupdate /force</code></pre>
  <p>Alternatively, restart the machines to allow GPO to apply the settings during startup.</p>

  <h3>5️⃣ Verify Registry Changes</h3>
  <p>After deployment, on a target machine, open <strong>Registry Editor</strong> (<code>regedit</code>) and navigate to:</p>
  <pre><code>HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\EventLog\Microsoft-Windows-PrintService/Operational</code></pre>
  <p>Ensure that all the specified values are correctly set.</p>

  <h3>6️⃣ Monitor Logs</h3>
  <p>Check the log file location (<code>L:\Microsoft-Windows-PrintService-Operational\</code>) 
     to verify that the <code>Microsoft-Windows-PrintService-Operational.evtx</code> log file is 
     being created and updated as per the configurations.
  </p>

  <hr />

  <h2>✅ Best Practices and Final Notes</h2>
  <ul>
    <li><strong>Backup Registry Before Changes:</strong> Always create a backup before applying changes, especially in production environments.</li>
    <li><strong>Test on a Single Machine:</strong> Before wide-scale deployment, apply the <code>.reg</code> file to a single test machine.</li>
    <li><strong>Ensure Network Share Accessibility:</strong> Verify that the drive letter <code>L:</code> is correctly mapped and that the specified path exists.</li>
    <li><strong>Monitor Event Logs:</strong> Regularly check the Application Event Logs for any errors related to the registry changes.</li>
    <li><strong>Documentation:</strong> Maintain a record of all registry changes for future reference and troubleshooting.</li>
    <li><strong>Security Considerations:</strong> Ensure that the network share containing log files is secured and accessible only by authorized users.</li>
  </ul>

  <p><em>By incorporating this well-documented <code>PrintService-Operacional-EventLogs.reg</code> file into your deployment strategy, 
     you ensure consistent and efficient configuration of the PrintService Operational event logs across all target machines 
     in your network.</em></p>
</div>
