<div>
  <h1>⚙️ WSUS Management Tools</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>WSUS Management Tools</strong> repository provides a robust suite of 
    <strong>PowerShell scripts</strong> to automate, maintain, and optimize 
    <strong>Windows Server Update Services (WSUS)</strong> and its associated 
    <strong>SUSDB</strong> (Windows Internal Database) in enterprise environments.
  </p>

  <h3>✅ Key Features</h3>
  <ul>
    <li><strong>Graphical Interface:</strong> User-friendly GUI for all WSUS operations.</li>
    <li><strong>Automated Maintenance:</strong> Declines expired/superseded/unapproved updates and performs WSUS cleanup via official APIs.</li>
    <li><strong>SUSDB Optimization:</strong> Supports reindexing, DBCC checks, shrink, and full backup operations.</li>
    <li><strong>SQL Script Integration:</strong> Uses <code>wsus-reindex-EXAMPLE.sql</code> and <code>wsus-verify-fragmentation.sql</code> for direct database maintenance.</li>
    <li><strong>Multi-threaded Execution:</strong> Background thread pooling for faster task execution.</li>
    <li><strong>Persistent Logs & Reports:</strong> Generates log and CSV output for auditing and tracking.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell:</strong>
      <ul>
        <li>Requires PowerShell 5.1 or higher.</li>
        <li>Check version:
          <pre><code>$PSVersionTable.PSVersion</code></pre>
        </li>
      </ul>
    </li>
    <li><strong>🔑 Run as Administrator:</strong> All scripts must be executed with elevated privileges.</li>
    <li><strong>📦 Required Modules:</strong> 
      <p>Ensure <code>UpdateServices</code> and optionally <code>ActiveDirectory</code> modules are installed.</p>
    </li>
    <li><strong>🗃 SQLCMD Utility:</strong>
      <p>Required for executing SQL commands against the SUSDB. Add <code>sqlcmd.exe</code> to the <code>PATH</code> or configure full path in the scripts.</p>
    </li>
    <li><strong>🔧 Execution Policy:</strong>
      <pre><code>Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned</code></pre>
    </li>
    <li><strong>📂 SQL Scripts Location:</strong>
      <p>Ensure the following SQL files are in <code>.\\Scripts</code> folder:</p>
      <ul>
        <li><code>wsus-reindex-EXAMPLE.sql</code></li>
        <li><code>wsus-verify-fragmentation.sql</code></li>
      </ul>
    </li>
    <li><strong>🧩 WSUS Admin Assembly:</strong>
      <p>Ensure WSUS Console is installed with <code>Microsoft.UpdateServices.Administration.dll</code> available under GAC.</p>
    </li>
  </ol>

  <hr />

  <h2>📜 Script Descriptions</h2>
  <table border="1" style="border-collapse: collapse; width: 100%;">
    <thead>
      <tr>
        <th style="padding: 8px;">Script</th>
        <th style="padding: 8px;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>Maintenance-WSUS-Admin-Tool.ps1</strong></td>
        <td>Graphical tool that automates WSUS update declines, executes official WSUS API cleanup, and performs SQL maintenance (reindex, backup, shrink, DBCC).</td>
      </tr>
      <tr>
        <td><strong>Generate-WSUSReindexScript.ps1</strong></td>
        <td>Generates <code>wsus-reindex.sql</code> dynamically by scanning SUSDB for highly fragmented indexes.</td>
      </tr>
      <tr>
        <td><strong>Scripts/wsus-reindex-EXAMPLE.sql</strong></td>
        <td>Static SQL example to rebuild commonly fragmented indexes on SUSDB.</td>
      </tr>
      <tr>
        <td><strong>Scripts/wsus-verify-fragmentation.sql</strong></td>
        <td>SQL query to identify index fragmentation levels in SUSDB, ordered by severity.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li>Clone the repo and open PowerShell as Administrator.</li>
    <li>Run: <code>.\Maintenance-WSUS-Admin-Tool.ps1</code></li>
    <li>Select your WSUS server, check maintenance tasks, and click <strong>Run Maintenance</strong>.</li>
    <li>Review logs and CSV output at <code>$env:ProgramData\WSUS-GUI\Logs</code>.</li>
  </ol>

  <hr />

  <h2>📁 Output Files</h2>
  <ul>
    <li><strong>*.log:</strong> Timestamped execution logs in <code>$env:ProgramData\WSUS-GUI\Logs</code>.</li>
    <li><strong>*.csv:</strong> Declined update reports exported after execution.</li>
    <li><strong>*.bak:</strong> Optional SUSDB backups saved in <code>$env:ProgramData\WSUS-GUI\Backups</code>.</li>
  </ul>

  <hr />

  <h2>💡 Tips</h2>
  <ul>
    <li>Use <strong>Task Scheduler</strong> to automate weekly execution via the script’s built-in scheduler button.</li>
    <li>Customize log and script paths by editing variables like <code>$logDir</code> or <code>$sqlScriptPath</code>.</li>
    <li>Run <code>Generate-WSUSReindexScript.ps1</code> weekly to update the reindexing SQL dynamically.</li>
    <li>Validate SQL output in test before applying on production.</li>
  </ul>
</div>
