<div>
  <h1>🛠️ WSUS Management Tools</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>WSUS Management</strong> folder contains a professional-grade PowerShell GUI script 
    for administering and maintaining Windows Server Update Services (WSUS). 
    This tool automates update declines, WSUS API cleanups, and advanced maintenance on the 
    <strong>SUSDB (Windows Internal Database)</strong> using custom SQL scripts. It is tailored for 
    large-scale enterprise WSUS deployments with specific index optimization and fragmentation analysis.
  </p>

  <h3>✅ Key Features</h3>
  <ul>
    <li><strong>Graphical Interface:</strong> User-friendly GUI to perform WSUS tasks without command-line interaction.</li>
    <li><strong>Remote WSUS Server Detection:</strong> Dynamically finds and lists WSUS servers across the AD forest.</li>
    <li><strong>Update Decline Options:</strong> Automatically handles expired, unapproved, and superseded updates.</li>
    <li><strong>WSUS API Cleanup:</strong> Executes official WSUS cleanup methods, including optional compression.</li>
    <li><strong>SQL WID Maintenance:</strong> Supports DBCC CHECKDB, custom index rebuilding with <code>wsus-reindex.sql</code>, 
      and fragmentation analysis with <code>wsus-verificar-fragmentacao.sql</code> for SUSDB.</li>
    <li><strong>Optional SUSDB Backup:</strong> Toggle to back up the database before cleanup (recommended for large deployments).</li>
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
        <li>Required for executing DBCC commands and custom SQL scripts on SUSDB.</li>
        <li>Ensure <code>sqlcmd.exe</code> is in the system <code>PATH</code> or specify its full path.</li>
      </ul>
    </li>
    <li>
      <strong>🔧 Execution Policy:</strong>
      <pre><code>Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned</code></pre>
    </li>
    <li>
      <strong>📂 SQL Script Files:</strong>
      <ul>
        <li>Place <code>wsus-reindex.sql</code> and <code>wsus-verificar-fragmentacao.sql</code> in <code>C:\Scripts</code> (adjust path in script if needed).</li>
      </ul>
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
          SUSDB maintenance with custom SQL scripts (<code>wsus-reindex.sql</code> for index rebuilding and 
          <code>wsus-verificar-fragmentacao.sql</code> for fragmentation analysis), and optional SQL backup. 
          Auto-detects WSUS servers from the AD forest.
        </td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Run the Script:</strong> Right-click the <code>.ps1</code> file and choose <em>Run with PowerShell</em>.</li>
    <li><strong>Server Selection:</strong> Pick a WSUS server from the dropdown (auto-populated from AD).</li>
    <li><strong>Select Actions:</strong> Use the checkboxes to define maintenance tasks, including custom index rebuilding and fragmentation checks.</li>
    <li><strong>Run:</strong> Click <strong>Run Maintenance</strong> and monitor the progress via GUI feedback.</li>
    <li><strong>Check Results:</strong> Logs and CSV exports will be available in <code>$env:ProgramData\WSUS-GUI\Logs</code>.</li>
  </ol>

  <hr />

  <h2>📁 Complementary Files</h2>
  <ul>
    <li><strong>*.log:</strong> Execution log with timestamps and detailed results, stored in <code>$env:ProgramData\WSUS-GUI\Logs</code>.</li>
    <li><strong>*.csv:</strong> Declined update report exported after execution, saved in <code>$env:ProgramData\WSUS-GUI\Logs</code>.</li>
    <li><strong>*.bak:</strong> Optional SUSDB database backup file (if enabled), stored in <code>$env:ProgramData\WSUS-GUI\Backups</code>.</li>
  </ul>

  <hr />

  <h2>💡 Optimization Tips</h2>
  <ul>
    <li><strong>Use Task Scheduler:</strong> Automate regular cleanup with weekly or monthly triggers using the <strong>Schedule Task</strong> button.</li>
    <li><strong>Backup Strategy:</strong> Perform DB backups before enabling compression or reindexing on large SUSDB databases.</li>
    <li><strong>Centralize Logs:</strong> Modify the script’s <code>$logDir</code> to point to a shared network folder for centralized logging.</li>
    <li><strong>Safe Execution:</strong> Test new WSUS cleanup or SQL maintenance options in a staging environment before production.</li>
  </ul>
</div>
