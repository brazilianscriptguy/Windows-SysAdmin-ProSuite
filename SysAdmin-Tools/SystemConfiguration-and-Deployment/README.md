<div>
  <h1>🧰 Maintenance-WSUS-Admin-Tool.ps1</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>Maintenance-WSUS-Admin-Tool.ps1</strong> script provides a complete PowerShell GUI-based solution for maintaining a WSUS environment 
    and performing SQL maintenance tasks on <strong>SUSDB (Windows Internal Database)</strong>.
  </p>
  <p>
    It supports unapproved update decline, WSUS cleanup tasks (including optional <code>CompressUpdates</code>), and built-in SQL operations like 
    <code>DBCC CHECKDB</code>, <code>Reindex</code>, and <code>Shrink</code>. Logging and CSV output are automatically saved.
  </p>

  <h3>✅ Key Features</h3>
  <ul>
    <li><strong>Graphical Interface:</strong> Easy-to-use Windows Forms GUI — no PowerShell console required.</li>
    <li><strong>Automated Decline Actions:</strong> Unapproved, expired, and superseded updates declined automatically.</li>
    <li><strong>WSUS API Cleanup:</strong> Performs official WSUS cleanup routines through the <code>Microsoft.UpdateServices.Administration</code> API.</li>
    <li><strong>SQL Maintenance:</strong>
      <ul>
        <li><code>DBCC CHECKDB</code></li>
        <li><code>Reindex</code> using <code>sp_MSforeachtable</code></li>
        <li><code>Shrink SUSDB</code> to reclaim space</li>
      </ul>
    </li>
    <li><strong>Compress Updates:</strong> Optional toggle to include the WSUS <code>CompressUpdates</code> operation.</li>
    <li><strong>Remote WSUS Server Support:</strong> Dropdown selector for registered WSUS servers in the Active Directory forest.</li>
    <li><strong>Progress Bar + Status:</strong> Real-time feedback via progress bar and status label.</li>
    <li><strong>Persistent Logging:</strong> Logs actions to <code>C:\Logs-TEMP\</code> with timestamped filenames.</li>
    <li><strong>CSV Output:</strong> Declined update details exported to structured CSV format.</li>
    <li><strong>SUSDB Backup (WID):</strong> Optional toggle to generate database backup with disk space warning for large DBs.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell Version:</strong>
      <ul>
        <li>Requires PowerShell 5.1 or later</li>
        <li>Run this command to verify:
          <pre><code>$PSVersionTable.PSVersion</code></pre>
        </li>
      </ul>
    </li>
    <li>
      <strong>🔑 Administrator Privileges:</strong>
      <p>Script must be run as Administrator to access WSUS and the WID (SUSDB).</p>
    </li>
    <li>
      <strong>📦 Required Modules:</strong>
      <p>Ensure <code>UpdateServices</code>, <code>sqlcmd</code> utility, and <code>ActiveDirectory</code> module are available.</p>
    </li>
    <li>
      <strong>🗂 Folder Permissions:</strong>
      <p>Create or ensure write permissions on <code>C:\Logs-TEMP</code>.</p>
    </li>
  </ol>

  <hr />

  <h2>📜 Script Usage</h2>
  <ol>
    <li><strong>Run as Administrator:</strong> Right-click the script and choose <em>Run with PowerShell</em>, or run manually with:
      <pre><code>powershell.exe -ExecutionPolicy Bypass -File .\Maintenance-WSUS-Admin-Tool.ps1</code></pre>
    </li>
    <li><strong>Select Maintenance Options:</strong> Use the checkboxes in the GUI to define what operations to execute.</li>
    <li><strong>Pick WSUS Server:</strong> Choose from detected WSUS servers (Auto-discovered from AD Forest).</li>
    <li><strong>Execute:</strong> Click <strong>Run Maintenance</strong> to launch the selected routines.</li>
    <li><strong>Review Results:</strong> Logs and CSVs will be written to <code>C:\Logs-TEMP</code>.</li>
  </ol>

  <hr />

  <h2>📁 Output Files</h2>
  <ul>
    <li><code>WSUS-Maintenance-[timestamp].log</code> — Detailed execution log</li>
    <li><code>WSUS-Maintenance-Declined-[timestamp].csv</code> — Declined updates listing</li>
    <li><code>SUSDB-[timestamp].bak</code> — Optional backup file if enabled</li>
  </ul>

  <hr />

  <h2>💡 Best Practices</h2>
  <ul>
    <li><strong>Schedule Regular Runs:</strong> Use Task Scheduler or Group Policy to run the script weekly or monthly.</li>
    <li><strong>Monitor Logs:</strong> Periodically review the logs in <code>C:\Logs-TEMP</code> for errors or anomalies.</li>
    <li><strong>Test on Dev:</strong> Run the tool in a test environment before rolling into production for large WSUS farms.</li>
    <li><strong>Backup Before Cleanups:</strong> Use the backup option especially before major declines or SQL actions.</li>
  </ul>

</div>
