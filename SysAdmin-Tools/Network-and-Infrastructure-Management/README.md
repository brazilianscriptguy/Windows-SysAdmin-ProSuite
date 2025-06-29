<div>
  <h1>🌐 Network and Infrastructure Management Tools</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>Network and Infrastructure Management</strong> folder includes a curated collection of
    <strong>PowerShell automation scripts</strong> for managing core infrastructure services such as <code>DNS</code>, <code>DHCP</code>, <code>WSUS</code>, and server diagnostics. 
    These tools support IT administrators in optimizing availability, enforcing consistency, and improving operational visibility across enterprise networks.
  </p>

  <h3>Key Features:</h3>
  <ul>
    <li><strong>Automated Infrastructure Tasks:</strong> Covers DHCP scope transfers, DNS cleanup, WSUS audits, time sync, and more.</li>
    <li><strong>Interactive Interfaces:</strong> Scripts with graphical prompts for easy parameter input and execution.</li>
    <li><strong>Auditable Logging:</strong> Generates <code>.log</code> files for every operation, including success and error details.</li>
    <li><strong>CSV-Based Reports:</strong> Scripts export structured <code>.csv</code> outputs for post-analysis and audits.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell Version</strong><br>
      Required version: <code>5.1 or later</code><br>
      Check your version with:
      <pre><code>$PSVersionTable.PSVersion</code></pre>
    </li>
    <li>
      <strong>🔑 Administrator Privileges</strong><br>
      Scripts may require elevation to modify services or access protected configurations.
    </li>
    <li>
      <strong>📦 Required Modules</strong>
      <ul>
        <li><code>ActiveDirectory</code></li>
        <li><code>DNSServer</code></li>
      </ul>
    </li>
    <li>
      <strong>🖥️ Remote Server Administration Tools (RSAT)</strong><br>
      Required for DNS, DHCP, and WSUS features. Install with:
      <pre><code>Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online</code></pre>
    </li>
    <li>
      <strong>⚙️ Execution Policy</strong><br>
      Ensure scripts can run by setting:
      <pre><code>Set-ExecutionPolicy RemoteSigned -Scope Process</code></pre>
    </li>
  </ol>

  <hr />

  <h2>📄 Script List and Descriptions</h2>
  <table border="1" style="border-collapse: collapse; width: 100%;">
    <thead>
      <tr>
        <th style="padding: 8px;">Script Name</th>
        <th style="padding: 8px;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><code>Check-ServicesPort-Connectivity.ps1</code></td>
        <td>Tests service port availability across endpoints (e.g., RDP, DNS, HTTP).</td>
      </tr>
      <tr>
        <td><code>Create-NewDHCPReservations.ps1</code></td>
        <td>GUI tool for adding new DHCP reservations by MAC, hostname, and IP scope.</td>
      </tr>
      <tr>
        <td><code>Inventory-WSUSConfigs-Tool.ps1</code></td>
        <td>Extracts WSUS update data and computer groups; exports <code>.csv</code> reports.</td>
      </tr>
      <tr>
        <td><code>Restart-NetworkAdapter.ps1</code></td>
        <td>Restarts selected network interfaces with interactive input and confirmation.</td>
      </tr>
      <tr>
        <td><code>Restart-SpoolerPoolServices.ps1</code></td>
        <td>Restarts spooler and LPD services; useful for print spooler recovery.</td>
      </tr>
      <tr>
        <td><code>Retrieve-DHCPReservations.ps1</code></td>
        <td>Exports existing DHCP reservations with search/filter capabilities.</td>
      </tr>
      <tr>
        <td><code>Retrieve-Empty-DNSReverseLookupZone.ps1</code></td>
        <td>Finds and lists empty reverse DNS zones for cleanup tasks.</td>
      </tr>
      <tr>
        <td><code>Retrieve-ServersDiskSpace.ps1</code></td>
        <td>Gathers disk usage data from remote servers; outputs drive space metrics.</td>
      </tr>
      <tr>
        <td><code>Synchronize-ADComputerTime.ps1</code></td>
        <td>Triggers a time sync with the domain controller for all listed AD computers.</td>
      </tr>
      <tr>
        <td><code>Transfer-DHCPScopes.ps1</code></td>
        <td>Exports/imports DHCP scopes between servers; supports logging and rollback.</td>
      </tr>
      <tr>
        <td><code>Update-DNS-and-Sites-Services.ps1</code></td>
        <td>Updates DNS zones and AD Sites/Subnets using live DHCP lease data.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Launch:</strong> Right-click the script > <code>Run with PowerShell</code>, or launch from terminal.</li>
    <li><strong>Interact:</strong> Follow prompts (GUI or terminal-based) to complete execution.</li>
    <li><strong>Review Output:</strong> Check <code>.log</code> and <code>.csv</code> results in the script's working directory.</li>
  </ol>

  <hr />

  <h2>📁 Logging and Output</h2>
  <ul>
    <li><strong>📄 Log Files:</strong> Stored in <code>C:\Logs-TEMP\</code> or <code>C:\ITSM-Logs-WKS\</code> (for ITSM-tagged tools).</li>
    <li><strong>📊 Reports:</strong> Structured <code>.csv</code> exports suitable for Excel or dashboarding.</li>
  </ul>

  <hr />

  <h2>💡 Optimization Tips</h2>
  <ul>
    <li><strong>🗓️ Automate:</strong> Schedule regular jobs using Task Scheduler or SCCM for routine diagnostics.</li>
    <li><strong>🧠 Customize:</strong> Modify script filters or add logging hooks for specific environments.</li>
    <li><strong>📁 Centralize:</strong> Store outputs on a shared log server or version-controlled storage path.</li>
  </ul>
</div>
