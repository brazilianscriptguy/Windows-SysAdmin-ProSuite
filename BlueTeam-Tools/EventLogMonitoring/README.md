<div align="center">

  <h1>🔵 BlueTeam-Tools - EventLog Monitoring Suite</h1>

  <p>
    The <strong>EventLogMonitoring Folder</strong> contains a suite of <strong>PowerShell scripts</strong> designed to process and analyze <strong>Windows Event Log files (.evtx)</strong>. These tools automate event log analysis, generate actionable insights, and produce detailed reports to help administrators maintain security, track system activities, and ensure compliance.
  </p>

</div>

<hr />

<h2>✨ Key Features</h2>
<ul>
  <li><strong>User-Friendly GUI:</strong> Simplifies interaction with intuitive graphical interfaces.</li>
  <li><strong>Detailed Logging:</strong> All scripts generate <code>.log</code> files for comprehensive tracking and troubleshooting.</li>
  <li><strong>Exportable Reports:</strong> Outputs in <code>.csv</code> format for streamlined analysis and reporting.</li>
  <li><strong>Proactive Event Management:</strong> Automates log monitoring and analysis, enhancing system visibility and security.</li>
</ul>

<hr />

<h2>🛠️ Prerequisites</h2>
<ul>
  <li>
    <strong>⚙️ PowerShell</strong><br>
    PowerShell must be enabled on your system. Import the following module where applicable:
    <pre><code>Import-Module ActiveDirectory</code></pre>
  </li>
  <li>
    <strong>🔑 Administrator Privileges</strong><br>
    Some scripts require elevated permissions to access sensitive configurations, analyze logs, or modify system settings.
  </li>
  <li>
    <strong>🖥️ Remote Server Administration Tools (RSAT)</strong><br>
    Install RSAT on Windows 10/11 to enable remote management of Active Directory and server roles.
  </li>
  <li>
    <strong>⚙️ Microsoft Log Parser Utility</strong><br>
    Download and install <a href="https://www.microsoft.com/en-us/download/details.aspx?id=24659" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/LogParser-Download%20Here-blue?style=for-the-badge&logo=microsoft" alt="Log Parser Badge">
    </a> for advanced querying and analysis of log formats.
  </li>
</ul>

<hr />

<h2>📄 Script Descriptions</h2>
<ul>
  <li>
    <strong>EventID-Count-AllEvtx-Events.ps1</strong><br>
    Counts occurrences of each Event ID in <code>.evtx</code> files and exports the results to <code>.csv</code>, aiding event log analysis.
  </li>
  <li>
    <strong>EventID307-PrintAudit.ps1</strong><br>
    Audits print activities by analyzing Event ID 307 from the <code>Microsoft-Windows-PrintService/Operational</code> log. Generates detailed tracking reports, including user actions, printer usage, and job specifics.<br>
    <ul>
      <li>
        <a href="#" target="_blank" rel="noopener noreferrer">
          <img src="https://img.shields.io/badge/Registry%20File-PrintService%20Config-orange?style=for-the-badge&logo=windows" alt="Registry File Badge">
        </a>
      </li>
    </ul>
  </li>
  <li>
    <strong>EventID4624-ADUserLoginViaRDP.ps1</strong><br>
    Generates a <code>.csv</code> report on RDP logon activities (Event ID 4624) for monitoring remote access and identifying potential risks.
  </li>
  <li>
    <strong>EventID5136-5137-5141-ADObjectChanges.ps1</strong><br>
    Analyzes Active Directory object changes and deletions (Event IDs 5136, 5137, and 5141), producing <code>.csv</code> reports for auditing AD modifications.
  </li>
</ul>

<hr />

<h2>🚀 Usage Instructions</h2>
<ul>
  <li><strong>Run the Script:</strong> Launch the desired script using the <code>Run With PowerShell</code> option.</li>
  <li><strong>Provide Inputs:</strong> Follow on-screen prompts or select log files as required.</li>
  <li><strong>Review Outputs:</strong> Check generated <code>.log</code> files and exported <code>.csv</code> reports for results.</li>
</ul>

<h3>Example Scenarios:</h3>
<ul>
  <li>
    <strong>EventID-Count-AllEvtx-Events.ps1</strong><br>
    Run the script to count occurrences of Event IDs in <code>.evtx</code> files. Export results to <code>.csv</code> for analysis.
  </li>
  <li>
    <strong>EventID307-PrintAudit.ps1</strong><br>
    Merge the <code>PrintService-Operational-EventLogs.reg</code> file into the Windows registry to enable detailed logging. Run the script to audit print activities, generating a <code>.csv</code> report for review.
  </li>
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

<hr />

<h2>🎯 Contributions and Feedback</h2>
<p>
  For improvements, suggestions, or bug reports, feel free to contact:
</p>
<div align="center">
  <a href="mailto:luizhamilton.lhr@gmail.com" target="_blank" rel="noopener noreferrer">
    <img src="https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail" alt="Email Badge">
  </a>
  <a href="https://github.com/brazilianscriptguy/BlueTeam-Tools/issues" target="_blank" rel="noopener noreferrer">
    <img src="https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github" alt="GitHub Issues Badge">
  </a>
  <a href="https://patreon.com/brazilianscriptguy" target="_blank" rel="noopener noreferrer">
    <img src="https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge&logo=patreon" alt="Support on Patreon Badge">
  </a>
  <a href="https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c" target="_blank" rel="noopener noreferrer">
    <img src="https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp" alt="WhatsApp Badge">
  </a>
</div>
