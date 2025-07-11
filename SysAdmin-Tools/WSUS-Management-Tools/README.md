<div>
  <h1>🧰 WSUS Management Tool</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>Maintenance-WSUS-Admin-Tool.ps1</strong> is a comprehensive PowerShell-based GUI script
    designed for automating <strong>WSUS maintenance</strong> and performing optional <strong>SUSDB (WID) SQL tasks</strong>.
    Built with enterprise environments in mind, it simplifies administrative tasks such as declining updates, executing cleanup,
    and maintaining the Windows Internal Database — all through an intuitive interface.
  </p>

  <h3>Key Features:</h3>
  <ul>
    <li><strong>Graphical Interface:</strong> Full-featured GUI with checkboxes, progress bar, and feedback.</li>
    <li><strong>Automated Update Decline:</strong> Handles expired, unapproved, and superseded updates.</li>
    <li><strong>WSUS API Cleanup:</strong> Executes <code>CleanupManager</code> operations including optional compression.</li>
    <li><strong>SUSDB Maintenance:</strong> Runs <code>DBCC CHECKDB</code>, index rebuild, and optional shrink on WID-based databases.</li>
    <li><strong>Optional Database Backup:</strong> Backs up <code>SUSDB</code> (optional, shown with warning for large deployments).</li>
    <li><strong>Remote WSUS Server Detection:</strong> Auto-detects all WSUS servers across the Active Directory forest.</li>
    <li><strong>Logging and CSV Export:</strong> Writes output to <code>C:\Logs-TEMP</code> for audit and reporting.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell 5.1+</strong>
      <ul>
        <li>Check version:
          <pre><code>$PSVersionTable.PSVersion</code></pre>
        </li>
      </ul>
    </li>
    <li><strong>🔑 Administrator Privileges</strong></li>
    <li>
      <strong>📦 Required Modules:</strong>
      <ul>
        <li><code>UpdateServices</code></li>
        <li><code>ActiveDirectory</code></li>
      </ul>
    </li>
    <li>
      <strong>🗃 SQL Tools (for WID Maintenance)</strong>
      <p>Ensure <code>sqlcmd.exe</code> is available in system <code>PATH</code>.</p>
    </li>
    <li>
      <strong>🔧 Execution Policy:</strong>
      <pre><code>Set-ExecutionPolicy RemoteSigned -Scope Process</code></pre>
    </li>
  </ol>

  <hr />

  <h2>📄 Script Details</h2>
  <table border="1" style="border-collapse: collapse; width: 100%;">
    <thead>
      <tr>
        <th style="padding: 8px;">Script Name</th>
        <th style="padding: 8px;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>Maintenance-WSUS-Admin-Tool.ps1</strong></td>
        <td>
          All-in-one GUI script for WSUS administration. Supports declining updates, WSUS cleanup via API, 
          SQL-based maintenance on WID (check DB, reindex, shrink), and automatic WSUS server discovery from AD forest.
        </td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 How to Use</h2>
  <ol>
    <li><strong>Right-click</strong> the script file and select <em>Run with PowerShell</em>.</li>
    <li>Choose a WSUS server from the dropdown (auto-filled from forest).</li>
    <li>Check the maintenance tasks you wish to perform.</li>
    <li>Click <strong>Run Maintenance</strong> and monitor the progress bar.</li>
    <li>After execution, review logs and optional CSV files in <code>C:\Logs-TEMP</code>.</li>
  </ol>

  <hr />

  <h2>📁 Output Files</h2>
  <ul>
    <li><strong>*.log</strong> — Execution logs with timestamps and results</li>
    <li><strong>*.csv</strong> — Declined update lists (if applicable)</li>
    <li><strong>*.bak</strong> — Database backup files (if enabled)</li>
  </ul>

  <hr />

  <h2>💡 Tips</h2>
  <ul>
    <li><strong>Run monthly:</strong> Schedule with Task Scheduler for recurring maintenance.</li>
    <li><strong>Skip compress on large WID:</strong> Use only when needed to reduce downtime.</li>
    <li><strong>Centralize logs:</strong> Redirect to a shared UNC path for organization-wide visibility.</li>
  </ul>
</div>
