<div>
  <h1>🔵 BlueTeam-Tools - EventLog Monitoring Suite</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>EventLogMonitoring Folder</strong> contains a suite of 
    <strong>PowerShell scripts</strong> designed to process and analyze 
    <strong>Windows Event Log files (.evtx)</strong>. These tools automate event 
    log analysis, generate actionable insights, and produce detailed reports to 
    help administrators maintain security, track system activities, and ensure 
    compliance.
  </p>

  <h3>Key Features:</h3>
  <ul>
    <li><strong>User-Friendly GUI:</strong> Simplifies interaction with intuitive graphical interfaces.</li>
    <li><strong>Detailed Logging:</strong> All scripts generate <code>.log</code> files for comprehensive tracking and troubleshooting.</li>
    <li><strong>Exportable Reports:</strong> Outputs in <code>.csv</code> format for streamlined analysis and reporting.</li>
    <li><strong>Proactive Event Management:</strong> Automates log monitoring and analysis, enhancing system visibility and security.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell</strong>
      <ul>
        <li>PowerShell must be enabled on your system.</li>
        <li>The following module may need to be imported where applicable:</li>
        <li><code>Import-Module ActiveDirectory</code></li>
      </ul>
    </li>
    <li>
      <strong>🔑 Administrator Privileges</strong>
      <p>Scripts may require elevated permissions to access sensitive configurations, analyze logs, or modify system settings.</p>
    </li>
    <li>
      <strong>🖥️ Remote Server Administration Tools (RSAT)</strong>
      <p>Install RSAT on your Windows 10/11 workstation to enable remote management of Active Directory and server roles.</p>
    </li>
    <li>
      <strong>⚙️ Microsoft Log Parser Utility</strong>
      <ul>
        <li>
          <strong>Download:</strong> Visit the 
          <a href="https://www.microsoft.com/en-us/download/details.aspx?id=24659" target="_blank">
            <img src="https://img.shields.io/badge/Download-Log%20Parser%202.2-blue?style=flat-square&logo=microsoft" alt="Download Log Parser Badge">
          </a>
        </li>
        <li><strong>Installation:</strong> Required for advanced querying and analysis of various log formats.</li>
      </ul>
    </li>
  </ol>

  <hr />

  <h2>📄 Script Descriptions (Alphabetical Order)</h2>
  <table border="1" style="border-collapse: collapse; width: 100%;">
    <thead>
      <tr>
        <th style="padding: 8px;">Script Name</th>
        <th style="padding: 8px;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td>EventID-Count-AllEvtx-Events.ps1</td>
        <td>Counts occurrences of each Event ID in <code>.evtx</code> files and exports the results to <code>.csv</code>, aiding event log analysis.</td>
      </tr>
      <tr>
        <td>EventID307-PrintAudit.ps1</td>
        <td>Audits print activities by analyzing Event ID 307 from the <code>Microsoft-Windows-PrintService/Operational</code> log. Generates detailed tracking reports.</td>
      </tr>
      <tr>
        <td>EventID4624-ADUserLoginViaRDP.ps1</td>
        <td>Generates a <code>.csv</code> report on RDP logon activities (login at Event ID 4624) for monitoring remote access.</td>
      </tr>
      <tr>
        <td>EventID4624and4634-ADUserLoginTracking.ps1</td>
        <td>Tracks user login activities (Event ID 4624 and 4634) and produces a <code>.csv</code> report for auditing purposes.</td>
      </tr>
      <tr>
        <td>EventID4625-ADUserLoginAccountFailed.ps1</td>
        <td>Compiles failed logon attempts (Event ID 4625) into a <code>.csv</code>, helping identify potential breaches.</td>
      </tr>
      <tr>
        <td>EventID4648-ExplicitCredentialsLogon.ps1</td>
        <td>Logs explicit credential usage (Event ID 4648) and generates a <code>.csv</code> report, aiding in detecting unauthorized credential use.</td>
      </tr>
      <tr>
        <td>EventID4660and4663-ObjectDeletionTracking.ps1</td>
        <td>Tracks object deletion events (Event IDs 4660 and 4663) and organizes data into <code>.csv</code> files for auditing.</td>
      </tr>
      <tr>
        <td>EventID4771-KerberosPreAuthFailed.ps1</td>
        <td>Identifies Kerberos pre-authentication failures (Event ID 4771) and outputs findings to <code>.csv</code>.</td>
      </tr>
      <tr>
        <td>EventID4800and4801-WorkstationLockStatus.ps1</td>
        <td>Tracks workstation locking and unlocking events (Event IDs 4800 and 4801) and generates a <code>.csv</code> report.</td>
      </tr>
      <tr>
        <td>EventID5136-5137-5141-ADObjectChanges.ps1</td>
        <td>Analyzes Active Directory object changes and deletions (Event IDs 5136, 5137, 5141).</td>
      </tr>
      <tr>
        <td>EventID6005-6006-6008-6009-6013-1074-1076-SystemRestarts.ps1</td>
        <td>Retrieves details of system restarts and shutdown events from the System log and exports the results to <code>.csv</code>.</td>
      </tr>
      <tr>
        <td>Migrate-WinEvtStructure-Tool.ps1</td>
        <td>
          Moves Windows Event Log files to a new directory, updates registry paths, and preserves ACLs.
          <br><br>
          <strong>Note:</strong> Some Windows Server environments require restarting in Safe Mode to stop the Event Log service. To do this, run:
          <pre><code>
bcdedit /set {current} safeboot minimal
shutdown /r /t 0
          </code></pre>
          After running the script, return to normal mode:
          <pre><code>
bcdedit /deletevalue {current} safeboot
shutdown /r /t 0
          </code></pre>
        </td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Run the Script:</strong> Launch the desired script using the <code>Run With PowerShell</code> option.</li>
    <li><strong>Provide Inputs:</strong> Follow on-screen prompts or select log files as required.</li>
    <li><strong>Review Outputs:</strong> Check generated <code>.log</code> files and exported <code>.csv</code> reports for results.</li>
  </ol>

  <hr />

  <h2>📝 Logging and Output</h2>
  <ul>
    <li><strong>📄 Logs:</strong> Each script generates detailed logs in <code>.LOG</code> format.</li>
    <li><strong>📊 Reports:</strong> Scripts export data in <code>.CSV</code> format for audits and reporting.</li>
  </ul>

  <hr />

  <h2>💡 Tips for Optimization</h2>
  <ul>
    <li><strong>Automate Execution:</strong> Schedule scripts to run periodically.</li>
    <li><strong>Centralize Logs:</strong> Store <code>.log</code> and <code>.csv</code> files in a shared repository.</li>
    <li><strong>Customize Analysis:</strong> Adjust script parameters as needed.</li>
  </ul>
</div>
