<div>
  <h1>🧰 WSUS Management Tools</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>WSUS Management Tools</strong> suite provides a modernized set of 
    <strong>PowerShell-based GUI scripts</strong> designed to automate, clean, and maintain Windows Server Update Services (WSUS) environments.
    These scripts target both <strong>content-level cleanup</strong> and <strong>SUSDB (WID)</strong> maintenance, while offering 
    <strong>enterprise-grade compatibility</strong> and <strong>Active Directory forest awareness</strong>.
  </p>

  <h3>Key Features:</h3>
  <ul>
    <li><strong>Graphical Interfaces:</strong> All scripts provide a user-friendly GUI for intuitive interaction and safe operations.</li>
    <li><strong>Update Decline Automation:</strong> Selectively declines expired, unapproved, and superseded updates.</li>
    <li><strong>WSUS Cleanup API:</strong> Executes native WSUS cleanup operations using the official .NET API.</li>
    <li><strong>SUSDB (WID) SQL Tasks:</strong> Enables DBCC CHECKDB, Reindexing, and Shrink operations on WID-hosted SUSDB.</li>
    <li><strong>Backup Integration:</strong> Optional database backup support before critical maintenance actions.</li>
    <li><strong>Remote Server Targeting:</strong> Dynamically detects WSUS servers across the AD forest (no hardcoded names).</li>
    <li><strong>Progress Feedback:</strong> Visual execution tracking via real-time progress bar and status updates.</li>
    <li><strong>Logging and Reports:</strong> Generates log files and structured CSV exports into <code>C:\Logs-TEMP</code>.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell</strong>
      <ul>
        <li>Requires PowerShell version 5.1 or later.</li>
        <li>Check version using:
          <pre><code>$PSVersionTable.PSVersion</code></pre>
        </li>
      </ul>
    </li>
    <li>
      <strong>🔑 Administrator Privileges</strong>
      <p>All scripts must be executed with elevated permissions to interact with WSUS, WID, and Active Directory.</p>
    </li>
    <li>
      <strong>📦 Required Modules</strong>
      <ul>
        <li><code>UpdateServices</code></li>
        <li><code>ActiveDirectory</code></li>
      </ul>
    </li>
    <li>
      <strong>🗃 SQL Command-Line Tools</strong>
      <p>For WID operations, ensure <code>sqlcmd.exe</code> is installed and available in system <code>PATH</code>.</p>
    </li>
    <li>
      <strong>🔧 Execution Policy</strong>
      <p>Temporarily enable script execution with:</p>
      <pre><code>Set-ExecutionPolicy RemoteSigned -Scope Process</code></pre>
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
        <td><strong>Download-WSUSUpdates-WithGUI.ps1</strong></td>
        <td>Searches all pending WSUS updates and allows GUI-based downloading for selected or all updates.</td>
      </tr>
      <tr>
        <td><strong>Force-WSUSFullSync-WithGUI.ps1</strong></td>
        <td>Forces a full synchronization with Microsoft Update, showing live sync status via GUI.</td>
      </tr>
      <tr>
        <td><strong>Purge-WSUS-ContentFolders-WithGUI.ps1</strong></td>
        <td>Scans and purges stale/unused update binaries from the WSUS content folder using GUI options.</td>
      </tr>
      <tr>
        <td><strong>Scan-WSUS-MissingContent-WithGUI.ps1</strong></td>
        <td>Compares WSUS metadata with actual content binaries to identify missing or orphaned packages.</td>
      </tr>
      <tr>
        <td><strong>Analyze-ClientStatusReports.ps1</strong></td>
        <td>Parses WSUS client reporting data to generate compliance reports for connected endpoints.</td>
      </tr>
      <tr>
        <td><strong>Configure-WSUS-AutoApproval-WithGUI.ps1</strong></td>
        <td>Enables and configures automatic approval rules for WSUS update categories and classifications.</td>
      </tr>
      <tr>
        <td><strong>Maintenance-WSUS-Admin-Tool.ps1</strong></td>
        <td>Central GUI tool for performing full WSUS cleanup and WID SQL tasks (Decline, Cleanup, DBCC, Backup, Compress).</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Run with Admin Rights:</strong> Right-click a script and select <em>Run with PowerShell</em>.</li>
    <li><strong>Pick Maintenance Options:</strong> Use GUI checkboxes to select WSUS or SQL operations.</li>
    <li><strong>Review Output:</strong> Logs will be written to <code>C:\Logs-TEMP\</code> with CSV reports where applicable.</li>
    <li><strong>Repeat Periodically:</strong> Recommended to run monthly or as part of patch management cycle.</li>
  </ol>

  <hr />

  <h2>📁 Output Artifacts</h2>
  <ul>
    <li><strong>.log files:</strong> Execution logs with timestamps</li>
    <li><strong>.csv files:</strong> Declined update listings or missing content reports</li>
    <li><strong>.bak files:</strong> Optional SUSDB backup files</li>
  </ul>

  <hr />

  <h2>💡 Optimization Tips</h2>
  <ul>
    <li><strong>Use in GPO or Task Scheduler:</strong> Automate cleanup on schedule.</li>
    <li><strong>Redirect Logs:</strong> Point log folder to a shared UNC path for centralized auditing.</li>
    <li><strong>Exclude CompressUpdates for speed:</strong> Skip compression for faster results on large DBs.</li>
    <li><strong>Use in Pre-Patching Routine:</strong> Clean up before monthly patch syncs.</li>
  </ul>
</div>
