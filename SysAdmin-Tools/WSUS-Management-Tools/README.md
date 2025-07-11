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
        <li>Verify version:
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
      <p>Ensure modules such as <code>UpdateServices</code> (via WSUS Administration Console) and <code>ActiveDirectory</code> (optional, for server discovery) are available.</p>
    </li>
    <li>
      <strong>🗃 SQLCMD Tools:</strong>
      <p>
        Required for executing DBCC commands and custom SQL scripts on SUSDB.
        Ensure <code>sqlcmd.exe</code> is in the system <code>PATH</code> or specify its full path manually.
      </p>
    </li>
    <li>
      <strong>🔧 Execution Policy:</strong>
      <pre><code>Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned</code></pre>
    </li>
    <li>
      <strong>📂 SQL Scripts Location:</strong>
      <p>Ensure the following SQL files are placed in <code>C:\Scripts</code> (or adjust path accordingly):</p>
      <ul>
        <li><code>wsus-reindex-EXAMPLE.sql</code></li>
        <li><code>wsus-verify-fragmentation.sql</code></li>
      </ul>
    </li>
    <li>
      <strong>🧩 WSUS Admin Assembly:</strong>
      <p>To automate WSUS using PowerShell, ensure the <code>Microsoft.UpdateServices.Administration.dll</code> is available in GAC.</p>

      <p>📍 <strong>Default Location:</strong><br />
      <code>C:\Windows\Microsoft.NET\assembly\GAC_MSIL\Microsoft.UpdateServices.Administration</code></p>

      <p>✅ <strong>PowerShell Verification Script:</strong></p>
      <pre><code># Check if WSUS Admin Assembly is registered
$assembly = [AppDomain]::CurrentDomain.GetAssemblies() |
    Where-Object { $_.FullName -like "Microsoft.UpdateServices.Administration*" }

if (-not $assembly) {
    try {
        [Reflection.Assembly]::Load("Microsoft.UpdateServices.Administration") | Out-Null
        Write-Host "✅ WSUS Administration assembly loaded successfully."
    } catch {
        Write-Warning "❌ Microsoft.UpdateServices.Administration.dll not found. Install WSUS Console on this system."
    }
} else {
    Write-Host "✅ WSUS Administration assembly already loaded in current session."
}
</code></pre>

      <p><strong>To Install WSUS Console (if missing):</strong></p>
      <pre><code>Install-WindowsFeature -Name UpdateServices-UI</code></pre>
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
          (<code>wsus-reindex-EXAMPLE.sql</code> and <code>wsus-verify-fragmentation.sql</code>), 
          and optional SQL backup. Auto-detects WSUS servers from the AD forest.
        </td>
      </tr>
      <tr>
        <td><strong>Generate-WSUSReindexScript.ps1</strong></td>
        <td>PowerShell script that queries SUSDB for fragmented indexes and generates a reindex SQL file.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Run the Script:</strong> Right-click <code>WSUS-Admin-Maintenance-Tool.ps1</code> → <em>Run with PowerShell</em> as Administrator.</li>
    <li><strong>Select Options:</strong> Choose WSUS server and maintenance tasks via GUI.</li>
    <li><strong>View Logs:</strong> Check <code>$env:ProgramData\WSUS-GUI\Logs</code> for detailed logs.</li>
    <li><strong>Export:</strong> Optional CSV export of declined updates and SQL backup if enabled.</li>
  </ol>

  <hr />

  <h2>📁 Complementary Files</h2>
  <ul>
    <li><strong>*.log:</strong> Execution log with timestamps, stored in <code>$env:ProgramData\WSUS-GUI\Logs</code>.</li>
    <li><strong>*.csv:</strong> Declined update report after maintenance run.</li>
    <li><strong>*.bak:</strong> Optional SUSDB backup file (if selected).</li>
    <li><strong>*.sql:</strong> SQL scripts for database health (reindex and fragmentation audit).</li>
  </ul>

  <hr />

  <h2>💡 Optimization Tips</h2>
  <ul>
    <li><strong>GPO Scheduling:</strong> Trigger weekly runs using Task Scheduler and Group Policy.</li>
    <li><strong>Centralized Logging:</strong> Point <code>$logDir</code> to a network share for audit compliance.</li>
    <li><strong>SQL Prechecks:</strong> Use <code>wsus-verify-fragmentation.sql</code> before performing reindexing.</li>
    <li><strong>Backup First:</strong> Always take a database backup before shrinking or compressing.</li>
    <li><strong>Test Mode:</strong> Run in staging before applying to production WSUS servers.</li>
  </ul>
</div>
