<div align="center">

  <h1>🔵 BlueTeam-Tools - EventLog Monitoring Suite</h1>

  <p>
    The <strong>EventLogMonitoring Folder</strong> contains a suite of <strong>PowerShell scripts</strong> designed to process and analyze <strong>Windows Event Log files (.evtx)</strong>. These tools automate event log analysis, generate actionable insights, and produce detailed reports to help administrators maintain security, track system activities, and ensure compliance.
  </p>

  <h3>Key Features:</h3>
  <ul>
    <li><strong>User-Friendly GUI:</strong> Simplifies interaction with intuitive graphical interfaces.</li>
    <li><strong>Detailed Logging:</strong> All scripts generate <code>.log</code> files for comprehensive tracking and troubleshooting.</li>
    <li><strong>Exportable Reports:</strong> Outputs in <code>.csv</code> format for streamlined analysis and reporting.</li>
    <li><strong>Proactive Event Management:</strong> Automates log monitoring and analysis, enhancing system visibility and security.</li>
  </ul>

</div>

<hr />

<h2>🛠️ Prerequisites</h2>
<ul>
  <li>
    <strong>⚙️ PowerShell</strong>
    <ul>
      <li>PowerShell must be enabled on your system.</li>
      <li>The following module may need to be imported where applicable:
        <pre><code>Import-Module ActiveDirectory</code></pre>
      </li>
    </ul>
  </li>
  <li>
    <strong>🔑 Administrator Privileges:</strong> Scripts may require elevated permissions to access sensitive configurations, analyze logs, or modify system settings.
  </li>
  <li>
    <strong>🖥️ Remote Server Administration Tools (RSAT):</strong> Install RSAT on your Windows 10/11 workstation to enable remote management of Active Directory and server roles.
  </li>
  <li>
    <strong>⚙️ Microsoft Log Parser Utility:</strong>
    <ul>
      <li><strong>Download:</strong> Visit the <a href="https://www.microsoft.com/en-us/download/details.aspx?id=24659" target="_blank" rel="noopener noreferrer">Log Parser 2.2 page</a> to download LogParser.msi.</li>
      <li><strong>Installation:</strong> Required for advanced querying and analysis of various log formats.</li>
    </ul>
  </li>
</ul>

<hr />

<h2>📄 Script Descriptions (Alphabetical Order)</h2>
<ul>
  <li><strong>EventID-Count-AllEvtx-Events.ps1:</strong> Counts occurrences of each Event ID in <code>.evtx</code> files and exports the results to <code>.csv</code>, aiding event log analysis.</li>
  <li><strong>EventID307-PrintAudit.ps1:</strong> Audits print activities by analyzing Event ID 307 from the <code>Microsoft-Windows-PrintService/Operational</code> log. Generates detailed tracking reports, including user actions, printer usage, and job specifics.
    <ul>
      <li><strong>Additional Files:</strong>
        <ul>
          <li><code>PrintService-Operational-EventLogs.reg:</code> Configures Windows Print Servers to enable detailed print logging.</li>
          <li><code>PrintService-Operational-EventLogs.md:</code> Contains setup instructions and best practices for configuring print service logs.</li>
        </ul>
      </li>
    </ul>
  </li>
  <li><strong>EventID4624-ADUserLoginViaRDP.ps1:</strong> Generates a <code>.csv</code> report on RDP logon activities (login at Event ID 4624) for monitoring remote access and identifying potential risks.</li>
  <li><strong>EventID4624and4634-ADUserLoginTracking.ps1:</strong> Tracks user login activities (logon at Event ID 4624 and logoff at Event ID 4634) and produces a <code>.csv</code> report for auditing and compliance purposes.</li>
  <li><strong>EventID4625-ADUserLoginAccountFailed.ps1:</strong> Compiles failed logon attempts (Event ID 4625) into a <code>.csv</code>, helping identify potential breaches and login patterns.</li>
  <li><strong>EventID4648-ExplicitCredentialsLogon.ps1:</strong> Logs explicit credential usage (Event ID 4648) and generates a <code>.csv</code> report, aiding in detecting unauthorized credential use.</li>
  <li><strong>EventID4660and4663-ObjectDeletionTracking.ps1:</strong> Tracks object deletion events (Event IDs 4660 and 4663) and organizes data into <code>.csv</code> files for auditing security and access changes.</li>
  <li><strong>EventID4771-KerberosPreAuthFailed.ps1:</strong> Identifies Kerberos pre-authentication failures (Event ID 4771) and outputs findings to <code>.csv</code>, helping diagnose authentication issues.</li>
  <li><strong>EventID4800and4801-WorkstationLockStatus.ps1:</strong> Tracks workstation locking and unlocking events (Event IDs 4800 and 4801) and generates a <code>.csv</code> report for monitoring workstation security.</li>
  <li><strong>EventID5136-5137-5141-ADObjectChanges.ps1:</strong> Analyzes Active Directory object changes and deletions (Event IDs 5136, 5137, and 5141), producing <code>.csv</code> reports for auditing AD modifications.</li>
  <li><strong>EventID6005-6006-6008-6009-6013-1074-1076-SystemRestarts.ps1:</strong> Retrieves details of system restarts and shutdown events from the System log and exports the results to <code>.csv</code>.</li>
  <li><strong>Migrate-WinEvtStructure-Tool.ps1:</strong> Moves Windows Event Log files to a new directory, updates registry paths, preserves ACLs, restarts the Event Log service, and rebuilds the DHCP Server configs. Requires administrative privileges.</li>
</ul>

<hr />

<h2>🚀 Usage Instructions</h2>
<p><strong>General Steps:</strong></p>
<ol>
  <li>Run the Script: Launch the desired script using the <code>Run With PowerShell</code> option.</li>
  <li>Provide Inputs: Follow on-screen prompts or select log files as required.</li>
  <li>Review Outputs: Check generated <code>.log</code> files and exported <code>.csv</code> reports for results.</li>
</ol>

<p><strong>Example Scenarios:</strong></p>
<ul>
  <li><strong>EventID-Count-AllEvtx-Events.ps1:</strong> Run the script to count occurrences of Event IDs in <code>.evtx</code> files. Export results to <code>.csv</code> for analysis.</li>
  <li><strong>EventID307-PrintAudit.ps1:</strong> Merge the <code>PrintService-Operational-EventLogs.reg</code> file into the Windows registry to enable detailed logging. Run the script to audit print activities, generating a <code>.csv</code> report for review.</li>
  <li><strong>EventID4624-ADUserLoginViaRDP.ps1:</strong> Execute the script with administrative privileges to monitor RDP logon activities and identify potential risks.</li>
  <li><strong>Migrate-WinEvtStructure-Tool.ps1:</strong> Moves Windows Event Log files to a new directory, updates registry paths, preserves ACLs, restarts the Event Log service, and rebuilds the DHCP Server configs.</li>
</ul>

<hr />

<h2>📝 Logging and Output</h2>
<ul>
  <li><strong>📄 Logs:</strong> Each script generates detailed logs in <code>.LOG</code> format, documenting actions performed and errors encountered.</li>
  <li><strong>📊 Reports:</strong> Scripts export data in <code>.CSV</code> format, providing actionable insights for audits and reporting.</li>
</ul>

<hr />

<h2>💡 Tips for Optimization</h2>
<ul>
  <li><strong>Automate Execution:</strong> Schedule scripts to run periodically for consistent log monitoring and analysis.</li>
  <li><strong>Centralize Logs:</strong> Store <code>.log</code> and <code>.csv</code> files in a shared repository for collaborative analysis and audits.</li>
  <li><strong>Customize Analysis:</strong> Adjust script parameters to align with your organization's security policies and monitoring needs.</li>
</ul>
