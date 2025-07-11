<div>
  <h1>🛠️ WSUS Management Tools</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>WSUS Management</strong> folder includes a professional-grade PowerShell GUI script 
    for administering and maintaining Windows Server Update Services (WSUS). 
    This tool is purpose-built for automating update declines, WSUS API cleanups, and optional maintenance on 
    <strong>SUSDB (Windows Internal Database)</strong>. It is ideal for large-scale enterprise WSUS deployments.
  </p>

  <h3>✅ Key Features</h3>
  <ul>
    <li><strong>Graphical Interface:</strong> User-friendly GUI to perform WSUS tasks without command-line interaction.</li>
    <li><strong>Remote WSUS Server Detection:</strong> Dynamically finds and lists WSUS servers across the AD forest.</li>
    <li><strong>Update Decline Options:</strong> Handles expired, unapproved, and superseded updates automatically.</li>
    <li><strong>WSUS API Cleanup:</strong> Executes official WSUS cleanup methods including optional compression.</li>
    <li><strong>SQL WID Maintenance:</strong> Supports DBCC CHECKDB, index rebuild, and shrink for WID (SUSDB).</li>
    <li><strong>Optional SUSDB Backup:</strong> Toggle to back up the database before cleanup (with warnings for large deployments).</li>
    <li><strong>Logging and Reporting:</strong> Exports detailed logs and declined update reports in CSV format.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell</strong>
      <ul>
        <li>Requires PowerShell 5.1 or later.</li>
        <li>Verify version:
          <pre><code>$PSVersionTable.PSVersion</code></pre>
        </li>
      </ul>
    </li>
    <li><strong>🔑 Administrator Privileges:</strong> Required for all WSUS and SQL tasks.</li>
    <li>
      <strong>📦 Required Modules:</strong>
      <ul>
        <li><code>UpdateServices</code></li>
        <li><code>ActiveDirectory</code></li>
      </ul>
    </li>
    <li>
      <strong>🗃 SQLCMD Tools:</strong>
      <ul>
        <li>Required for executing DBCC commands on SUSDB.</li>
        <li>Ensure <code>sqlcmd.exe</code> is in system <code>PATH</code>.</li>
      </ul>
    </li>
    <li>
      <strong>🔧 Execution Policy:</strong>
      <pre><code>Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned</code></pre>
    </li>
  </ol>

  <hr />

  <h2>📜 Script Descriptions (Alphabetical Order)</h2>
  <table border="1" style="border-collapse: collapse; width: 100%;">
    <thead>
      <tr>
        <th style="padding: 8px;">Script Name</th>
        <th style="padding: 8px;">Function</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>Maintenance-WSUS-Admin-Tool.ps1</strong></td>
        <td>
          All-in-one GUI script to automate WSUS administration. Offers update declining, WSUS API cleanup, 
          SUSDB maintenance (DBCC, reindex, shrink), and optional SQL backup. Auto-detects WSUS servers from the AD forest.
        </td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Run the Script:</strong> Right-click the <code>.ps1</code> file and choose <em>Run with PowerShell</em>.</li>
    <li><strong>Server Selection:</strong> Pick a WSUS server from the dropdown (auto-populated from AD).</li>
    <li><strong>Select Actions:</strong> Use the checkboxes to define maintenance tasks.</li>
    <li><strong>Run:</strong> Click <strong>Run Maintenance</strong> and monitor the progress via GUI feedback.</li>
    <li><strong>Check Results:</strong> Logs and CSV exports will be available in <code>C:\Logs-TEMP</code>.</li>
  </ol>

  <hr />

  <h2>📁 Complementary Files</h2>
  <ul>
    <li><strong>*.log:</strong> Execution log with timestamps and detailed results.</li>
    <li><strong>*.csv:</strong> Declined update report exported after execution.</li>
    <li><strong>*.bak:</strong> Optional SUSDB database backup file (if enabled).</li>
  </ul>

  <hr />

  <h2>💡 Optimization Tips</h2>
  <ul>
    <li><strong>Use Task Scheduler:</strong> Automate regular cleanup with weekly/monthly triggers.</li>
    <li><strong>Backup Strategy:</strong> Perform DB backups before enabling compression on large databases.</li>
    <li><strong>Centralize Logs:</strong> Modify script to store logs on a shared network folder.</li>
    <li><strong>Safe Execution:</strong> Test new WSUS cleanup options in staging before production.</li>
  </ul>
</div>
