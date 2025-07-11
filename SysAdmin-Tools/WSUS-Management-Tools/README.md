<div>
  <h1>⚙️ WSUS Management Tools</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>WSUS Management Tools</strong> repository provides a curated set of <strong>PowerShell scripts</strong> for automating, maintaining, and optimizing Windows Server Update Services (WSUS) and its underlying <strong>SUSDB (Windows Internal Database)</strong>. 
    These tools are ideal for Active Directory environments and support both standalone and enterprise deployments.
  </p>

  <h3>✅ Key Features</h3>
  <ul>
    <li><strong>Graphical Interface:</strong> User-friendly GUI for WSUS administrators to execute routine tasks without console input.</li>
    <li><strong>Index Optimization:</strong> Generates SQL reindex scripts for fragmented WSUS database indexes.</li>
    <li><strong>Assembly Detection:</strong> Verifies if WSUS Admin assemblies are properly loaded from the GAC.</li>
    <li><strong>Centralized Logging:</strong> Structured <code>.log</code> and <code>.csv</code> outputs for documentation and audits.</li>
    <li><strong>Modular Design:</strong> Scripts are standalone and can be integrated or scheduled individually.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell:</strong>
      <ul>
        <li>PowerShell 5.1 or later is required.</li>
        <li>Check your version:
          <pre><code>$PSVersionTable.PSVersion</code></pre>
        </li>
      </ul>
    </li>
    <li>
      <strong>🔑 Administrator Privileges:</strong>
      <p>All scripts must be executed as Administrator to access WSUS API and SUSDB.</p>
    </li>
    <li>
      <strong>📦 Required Modules:</strong>
      <ul>
        <li><code>UpdateServices</code> – installed via WSUS Admin Console.</li>
        <li><code>ActiveDirectory</code> – optional for auto-discovery of WSUS servers.</li>
      </ul>
    </li>
    <li>
      <strong>🗃 SQLCMD Tools:</strong>
      <ul>
        <li>Required to run SQL queries on SUSDB using named pipes.</li>
        <li>Ensure <code>sqlcmd.exe</code> is available in PATH.</li>
      </ul>
    </li>
    <li>
      <strong>🔧 Execution Policy:</strong>
      <pre><code>Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned</code></pre>
    </li>
    <li>
      <strong>📂 SQL Scripts Location:</strong>
      <ul>
        <li><code>C:\Scripts\wsus-reindex-EXAMPLE.sql</code></li>
        <li><code>C:\Scripts\wsus-verify-fragmentation.sql</code></li>
      </ul>
    </li>
    <li>
      <strong>🧩 WSUS Admin Assembly:</strong>
      <p>Ensure <code>Microsoft.UpdateServices.Administration.dll</code> is available in the Global Assembly Cache (GAC).</p>
      <p>Run the script <code>Check-WSUS-AdminAssembly.ps1</code> to confirm installation.</p>
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
        <td><strong>Check-WSUS-AdminAssembly.ps1</strong></td>
        <td>Checks if <code>Microsoft.UpdateServices.Administration.dll</code> is registered in the GAC. If not, advises installation of WSUS Console.</td>
      </tr>
      <tr>
        <td><strong>Generate-WSUSReindexScript.ps1</strong></td>
        <td>Connects to SUSDB via SQLCMD and generates <code>wsus-reindex.sql</code> for indexes with fragmentation &gt;10% and more than 100 pages.</td>
      </tr>
      <tr>
        <td><strong>Maintenance-WSUS-Admin-Tool.ps1</strong></td>
        <td>GUI-based tool for declining updates (superseded, expired, unapproved), WSUS cleanup, WID SQL operations (checkdb, shrink, reindex), and CSV logging.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Run the Script:</strong> Right-click on the desired <code>.ps1</code> file and select <em>Run with PowerShell</em>.</li>
    <li><strong>Select Options:</strong> Use the GUI checkboxes or adjust thresholds/paths directly in script variables.</li>
    <li><strong>Check Logs:</strong> Review output files in <code>$env:ProgramData\WSUS-GUI\Logs</code> or your specified location.</li>
  </ol>

  <hr />

  <h2>📁 Complementary Files</h2>
  <ul>
    <li><strong>wsus-reindex-EXAMPLE.sql:</strong> SQL rebuild script for fragmented SUSDB indexes (auto-generated).</li>
    <li><strong>wsus-verify-fragmentation.sql:</strong> SQL script to list fragmentation levels per index.</li>
  </ul>

  <hr />

  <h2>💡 Optimization Tips</h2>
  <ul>
    <li><strong>Leverage GPO Scheduling:</strong> Trigger weekly maintenance via Task Scheduler or Group Policy.</li>
    <li><strong>Redirect Logs:</strong> Modify <code>$logDir</code> in the script to centralize logs to a shared UNC path.</li>
    <li><strong>Environment-Specific Paths:</strong> Adjust <code>$sqlcmd</code>, <code>$namedPipe</code>, or other variables per environment.</li>
    <li><strong>Test First:</strong> Always test cleanup and SQL actions in a staging WSUS instance before production.</li>
  </ul>
</div>
