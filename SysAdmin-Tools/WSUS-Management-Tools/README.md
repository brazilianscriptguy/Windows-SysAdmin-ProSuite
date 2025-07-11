<div>
  <h1>⚙️ WSUS Management Tools</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>WSUS Management</strong> folder contains a curated set of 
    <strong>PowerShell scripts</strong> for administering and maintaining Windows Server Update Services (WSUS). 
    This tool is optimized for scalable, secure, and automated management of WSUS servers and the 
    <strong>SUSDB (Windows Internal Database)</strong> in Active Directory (AD) environments.
  </p>

  <h3>✅ Key Features</h3>
  <ul>
    <li><strong>Graphical Interface:</strong> GUI-based script simplifies WSUS administration for administrators.</li>
    <li><strong>Centralized Logging:</strong> Each execution logs results in structured <code>.log</code> files.</li>
    <li><strong>Streamlined Maintenance:</strong> Automates update declines, WSUS API cleanups, and SUSDB optimization.</li>
    <li><strong>Policy Compliance:</strong> Enforces WSUS maintenance baselines with optional SQL backups.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell:</strong>
      <ul>
        <li>Requires PowerShell version 5.1 or later.</li>
        <li>Check version:
          <pre><code>$PSVersionTable.PSVersion</code></pre>
        </li>
      </ul>
    </li>
    <li>
      <strong>🔑 Administrator Privileges:</strong>
      <p>All scripts require elevated permissions to execute WSUS and SQL tasks.</p>
    </li>
    <li>
      <strong>📦 Required Modules:</strong>
      <p>Ensure modules such as <code>UpdateServices</code> (via WSUS Administration Console) and <code>ActiveDirectory</code> are available.</p>
    </li>
    <li>
      <strong>🗃 SQLCMD Tools:</strong>
      <p>Required for executing DBCC commands and custom SQL scripts on SUSDB. Ensure <code>sqlcmd.exe</code> is in the system <code>PATH</code> or specify its full path.</p>
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
        <td><strong>WSUS-Admin-Maintenance-Tool.ps1</strong></td>
        <td>
          All-in-one GUI script to automate WSUS administration. Offers update declining (expired, unapproved, superseded), 
          WSUS API cleanup with optional compression, SUSDB maintenance with custom SQL scripts 
          (<code>wsus-reindex.sql</code> for index rebuilding and <code>wsus-verify-fragmentation.sql</code> for fragmentation analysis), 
          and optional SQL backup. Auto-detects WSUS servers from the AD forest.
        </td>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Run the Script:</strong> Right-click on <code>WSUS-Admin-Maintenance-Tool.ps1</code> and choose <em>Run with PowerShell</em>.</li>
    <li><strong>Input Parameters:</strong> Select a WSUS server from the dropdown and check desired maintenance tasks via the GUI.</li>
    <li><strong>Check Results:</strong> Logs are saved in <code>$env:ProgramData\WSUS-GUI\Logs</code>, with optional CSV exports for declined updates.</li>
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
    <li><strong>Leverage GPO Scheduling:</strong> Use the <strong>Schedule Task</strong> button to trigger weekly maintenance via GPO.</li>
    <li><strong>Use Task Scheduler:</strong> Schedule repetitive tasks using Windows Task Scheduler for automation.</li>
    <li><strong>Centralize Logs:</strong> Modify the script’s <code>$logDir</code> to point to a network share for unified audit.</li>
    <li><strong>Parameterize for Reuse:</strong> Adjust variables like <code>$sqlScriptDir</code> to fit different environments.</li>
  </ul>
</div>
