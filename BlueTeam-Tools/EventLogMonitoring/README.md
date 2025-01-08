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
        <li>
          The following module may need to be imported where applicable:
          <code>Import-Module ActiveDirectory</code>
        </li>
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
            Log Parser 2.2 page
          </a> to download LogParser.msi.
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
      <!-- Other scripts remain unchanged -->
      <tr>
        <td>Migrate-WinEvtStructure-Tool.ps1</td>
        <td>
          Moves Windows Event Log files to a new directory, updates registry paths, preserves ACLs, restarts the Event Log service, and rebuilds the DHCP Server configurations. <strong>It requires administrative privileges.</strong>
          <p><strong>Note:</strong> Some Windows Server environments that are already joined to a domain require restarting in Safe Mode to allow stopping the Event Log service. To do this, run:</p>
          <pre>
<bcdedit /set {current} safeboot minimal>
<shutdown /r /t 0>
          </pre>
          <p>
            This will reboot the server in Safe Mode (with minimal services). After running <strong>Migrate-WinEvtStructure-Tool.ps1</strong>, return to normal mode with:
          </p>
          <pre>
<bcdedit /deletevalue {current} safeboot>
<shutdown /r /t 0>
          </pre>
          <p>The server will then restart in its standard operating mode with all services enabled.</p>
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
</div>
