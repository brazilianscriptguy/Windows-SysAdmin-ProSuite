<div>
  <h1>WSUS Management Tools</h1>

  <h2>Overview</h2>
  <p>
    The <strong>WSUS-Management-Tools</strong> repository is a collection of professional-grade PowerShell scripts designed to automate, maintain, and optimize Windows Server Update Services (WSUS) and its underlying SUSDB (Windows Internal Database).
  </p>

  <h3>Key Features</h3>
  <ul>
    <li><strong>Graphical User Interface:</strong> Modern GUI-based script for end-to-end WSUS administration.</li>
    <li><strong>SQL Maintenance Automation:</strong> Generate and execute index rebuilds and fragmentation analysis on SUSDB.</li>
    <li><strong>Assembly Verification:</strong> Automatically checks for WSUS Administration Console dependencies.</li>
    <li><strong>Logging:</strong> Structured log and CSV output for declined updates and actions taken.</li>
    <li><strong>Scheduling Support:</strong> Built-in support for task automation via Windows Task Scheduler.</li>
  </ul>

  <hr />

  <h2>Prerequisites</h2>
  <ol>
    <li>
      <strong>PowerShell</strong>
      <ul>
        <li>PowerShell 5.1 or later is required.</li>
        <li>Check your version:
          <pre><code>$PSVersionTable.PSVersion</code></pre>
        </li>
      </ul>
    </li>
    <li>
      <strong>Administrator Privileges</strong>
      <p>All scripts must be run as Administrator due to WSUS and SQL access.</p>
    </li>
    <li>
      <strong>Required Modules</strong>
      <ul>
        <li><code>UpdateServices</code> — Installed with WSUS Admin Console.</li>
        <li><code>ActiveDirectory</code> — Optional, used for WSUS server auto-discovery.</li>
      </ul>
    </li>
    <li>
      <strong>SQLCMD Tools</strong>
      <ul>
        <li>Required for running queries on WID (SUSDB).</li>
        <li>Ensure <code>sqlcmd.exe</code> is in PATH or specify the full path in your script.</li>
      </ul>
    </li>
    <li>
      <strong>Execution Policy</strong>
      <pre><code>Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned</code></pre>
    </li>
    <li>
      <strong>SQL Scripts Location</strong>
      <p>Ensure the following SQL files are located in <code>C:\Scripts</code>:</p>
      <ul>
        <li><code>wsus-reindex-EXAMPLE.sql</code></li>
        <li><code>wsus-verify-fragmentation.sql</code></li>
      </ul>
    </li>
    <li>
      <strong>WSUS Administration Console</strong>
      <p>
        To verify that the <code>Microsoft.UpdateServices.Administration.dll</code> is available in the Global Assembly Cache (GAC), run:
      </p>
      <pre><code>.\Check-WSUS-AdminAssembly.ps1</code></pre>
      <p>
        This will check if the WSUS Admin assembly is already loaded or available in the GAC, and provide instructions if missing.
      </p>
    </li>
  </ol>

  <hr />

  <h2>Script Descriptions</h2>
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
        <td>All-in-one GUI tool for WSUS cleanup, decline rules, compression, SUSDB maintenance, backup, and logging. Integrates with Active Directory for WSUS auto-discovery.</td>
      </tr>
      <tr>
        <td><strong>Check-WSUS-AdminAssembly.ps1</strong></td>
        <td>Validates that the WSUS Console is installed and the required .NET assembly is available in the GAC.</td>
      </tr>
      <tr>
        <td><strong>Generate-WSUSReindexScript.ps1</strong></td>
        <td>Generates <code>wsus-reindex.sql</code> T-SQL script based on index fragmentation analysis. Uses <code>sqlcmd</code> to query SUSDB.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>Usage Instructions</h2>
  <ol>
    <li>Run <code>Maintenance-WSUS-Admin-Tool.ps1</code> with elevated privileges (Right-click → Run with PowerShell).</li>
    <li>Select a WSUS server and desired maintenance options via the graphical interface.</li>
    <li>Click “Run Maintenance” to begin. Logs and CSV files will be generated automatically.</li>
  </ol>

  <hr />

  <h2>Output Artifacts</h2>
  <ul>
    <li><strong>*.log</strong> — Detailed logs stored in <code>$env:ProgramData\WSUS-GUI\Logs</code></li>
    <li><strong>*.csv</strong> — Export of declined updates in CSV format</li>
    <li><strong>*.bak</strong> — Optional SUSDB backup files (if selected)</li>
    <li><strong>wsus-reindex-EXAMPLE.sql</strong> — SQL script for index optimization</li>
    <li><strong>wsus-verify-fragmentation.sql</strong> — SQL script for fragmentation analysis</li>
  </ul>

  <hr />

  <h2>Maintenance Recommendations</h2>
  <ul>
    <li>Run WSUS maintenance weekly using the “Schedule Task” button in the GUI.</li>
    <li>Review logs and reports regularly for update health and DB status.</li>
    <li>Ensure <code>sqlcmd</code> is available on all WSUS servers for database operations.</li>
    <li>Test custom SQL maintenance in staging environments before production use.</li>
  </ul>
</div>
