# 🔵 BlueTeam-Tools - EventLog Monitoring Suite

## 📝 Overview

The **EventLogMonitoring Folder** contains a suite of **PowerShell scripts** designed to process and analyze **Windows Event Log files (.evtx)**. These tools automate event log analysis, generate actionable insights, and produce detailed reports to help administrators maintain security, track system activities, and ensure compliance.

### Key Features:
- **User-Friendly GUI:** Simplifies interaction with intuitive graphical interfaces.  
- **Detailed Logging:** All scripts generate `.log` files for comprehensive tracking and troubleshooting.  
- **Exportable Reports:** Outputs in `.csv` format for streamlined analysis and reporting.  
- **Proactive Event Management:** Automates log monitoring and analysis, enhancing system visibility and security.

---

## 🛠️ Prerequisites

Ensure the following requirements are met before running the scripts:

1. **⚙️ PowerShell**
   - PowerShell must be enabled on your system.
   - The following module may need to be imported where applicable:
     - **Active Directory:** `Import-Module ActiveDirectory`

2. **🔑 Administrator Privileges**
   - Scripts may require elevated permissions to access sensitive configurations, analyze logs, or modify system settings.

3. **🖥️ Remote Server Administration Tools (RSAT)**
   - Install RSAT on your Windows 10/11 workstation to enable remote management of Active Directory and server roles.

4. **⚙️ Microsoft Log Parser Utility**  
   - **Download:** Visit the [Log Parser 2.2 page](https://www.microsoft.com/en-us/download/details.aspx?id=24659) to download LogParser.msi.  
   - **Installation:** Required for advanced querying and analysis of various log formats.

---

## 📄 Script Descriptions (Alphabetical Order)

1. **EventID-Count-AllEvtx-Events.ps1**  
   Counts occurrences of each Event ID in `.evtx` files and exports the results to `.csv`, aiding event log analysis.

2. **EventID307-PrintAudit.ps1**  
   Audits print activities by analyzing Event ID 307 from the `Microsoft-Windows-PrintService/Operational` log. Generates detailed tracking reports, including user actions, printer usage, and job specifics.  

   - **Additional Files:**  
     - **PrintService-Operational-EventLogs.reg**: Configures Windows Print Servers to enable detailed print logging.  
     - **PrintService-Operational-EventLogs.md**: Contains setup instructions and best practices for configuring print service logs.

3. **EventID4624-ADUserLoginViaRDP.ps1**  
   Generates a `.csv` report on RDP logon activities (login at Event ID 4624) for monitoring remote access and identifying potential risks.

4. **EventID4624and4634-ADUserLoginTracking.ps1**  
   Tracks user login activities (logon at Event ID 4624) and (logoff at Event ID 4634)and produces a `.csv` report for auditing and compliance purposes.

5. **EventID4625-ADUserLoginAccountFailed.ps1**  
   Compiles failed logon attempts (Event ID 4625) into a `.csv`, helping identify potential breaches and login patterns.

6. **EventID4648-ExplicitCredentialsLogon.ps1**  
   Logs explicit credential usage (Event ID 4648) and generates a `.csv` report, aiding in detecting unauthorized credential use.

7. **EventID4660and4663-ObjectDeletionTracking.ps1**  
   Tracks object deletion events (Event IDs 4660 and 4663) and organizes data into `.csv` files for auditing security and access changes.

8. **EventID4771-KerberosPreAuthFailed.ps1**  
   Identifies Kerberos pre-authentication failures (Event ID 4771) and outputs findings to `.csv`, helping diagnose authentication issues.

9. **EventID4800and4801-WorkstationLockStatus.ps1**  
   Tracks workstation locking and unlocking events (Event IDs 4800 and 4801) and generates a `.csv` report for monitoring workstation security.

10. **EventID5136-5137-5141-ADObjectChanges.ps1**  
    Analyzes Active Directory object changes and deletions (Event IDs 5136, 5137, and 5141), producing `.csv` reports for auditing AD modifications.

11. **EventID6005-6006-6008-6009-6013-1074-1076-SystemRestarts.ps1**  
    Retrieves details of system restarts and shutdown events from the System log and exports the results to `.csv`.

12. **Migrate-WinEvtStructure-Tool.ps1**  
Migrate-WinEvtStructure-Tool.ps1
Moves Windows Event Log files to a new directory, updates registry paths, and restarts the Event Log service. **It requires administrative privileges.**

> **Note:** Some Windows Server environments that are already joined to a domain require restarting in Safe Mode to allow stopping the Event Log service. To do this, run:

```cmd
bcdedit /set {current} safeboot minimal
shutdown /r /t 0
```

This will reboot the server in Safe Mode (with minimal services). After running **Migrate-WinEvtStructure-Tool.ps1**, return to normal mode with:

```cmd
bcdedit /deletevalue {current} safeboot
shutdown /r /t 0
```

The server will then restart in its standard operating mode with all services enabled.

---

## 🚀 Usage Instructions

### General Steps:
1. **Run the Script:** Launch the desired script using the `Run With PowerShell`option.  
2. **Provide Inputs:** Follow on-screen prompts or select log files as required.  
3. **Review Outputs:** Check generated `.log` files and exported `.csv` reports for results.

### Example Scenarios:

- **EventID-Count-AllEvtx-Events.ps1**  
   - Run the script to count occurrences of Event IDs in `.evtx` files. Export results to `.csv` for analysis.

- **EventID307-PrintAudit.ps1**  
   - Merge the `PrintService-Operational-EventLogs.reg` file into the Windows registry to enable detailed logging.  
   - Run the script to audit print activities, generating a `.csv` report for review.

- **EventID4624-ADUserLoginViaRDP.ps1***  
   - Execute the script with administrative privileges to monitor RDP logon activities and identify potential risks.

- **EventID5136-5137-5141-ADObjectChanges.ps1**  
   - Analyze Active Directory object changes and deletions by running this script. Exported `.csv` reports provide detailed auditing information.

- **Migrate-WinEvtStructure-Tool.ps1**  
   - Move Windows Event Log files to a new directory, update registry paths, and restart the Event Log service. Administrative privileges are required.

---

## 📝 Logging and Output

- **📄 Logs:** Each script generates detailed logs in `.LOG` format, documenting actions performed and errors encountered.  
- **📊 Reports:** Scripts export data in `.CSV` format, providing actionable insights for audits and reporting.

---

## 💡 Tips for Optimization

- **Automate Execution:** Schedule scripts to run periodically for consistent log monitoring and analysis.  
- **Centralize Logs:** Store `.log` and `.csv` files in a shared repository for collaborative analysis and audits.  
- **Customize Analysis:** Adjust script parameters to align with your organization's security policies and monitoring needs.
