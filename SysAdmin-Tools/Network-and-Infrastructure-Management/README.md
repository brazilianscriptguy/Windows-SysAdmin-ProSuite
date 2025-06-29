<div>
  <h1>🌐 Network and Infrastructure Management Tools</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>Network and Infrastructure Management</strong> folder contains a suite of 
    <strong>PowerShell automation tools</strong> for managing critical network components such as 
    <strong>DNS</strong>, <strong>DHCP</strong>, <strong>WSUS</strong>, and system-level infrastructure 
    across Windows Server environments. Each script is designed with accuracy, logging, and modularity in mind 
    to improve operational workflows and maintain enterprise-grade compliance.
  </p>

  <h3>Key Features:</h3>
  <ul>
    <li><strong>Automated Network Tasks:</strong> Automates DNS, DHCP, WSUS, and time sync operations.</li>
    <li><strong>Graphical Interfaces:</strong> GUI-based scripts simplify task execution and parameter input.</li>
    <li><strong>Auditable Logs:</strong> Generates detailed <code>.log</code> files for tracking and troubleshooting.</li>
    <li><strong>CSV Reports:</strong> All scripts export structured <code>.csv</code> reports for auditing and reporting.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell Version</strong>
      <p>Minimum required: <code>PowerShell 5.1+</code></p>
      <pre><code>$PSVersionTable.PSVersion</code></pre>
    </li>
    <li>
      <strong>🔑 Administrator Rights</strong>
      <p>Scripts may need elevated privileges to configure DNS/DHCP/WSUS roles and access protected services.</p>
    </li>
    <li>
      <strong>🖥️ RSAT Components</strong>
      <p>Install RSAT tools on your workstation using:</p>
      <pre><code>Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online</code></pre>
    </li>
    <li>
      <strong>📦 Required Modules</strong>
      <ul>
        <li><code>ActiveDirectory</code></li>
        <li><code>DNSServer</code></li>
      </ul>
    </li>
    <li>
      <strong>⚙️ Execution Policy</strong>
      <p>Set policy temporarily (if needed):</p>
      <pre><code>Set-ExecutionPolicy RemoteSigned -Scope Process</code></pre>
    </li>
  </ol>

  <hr />

  <h2>📄 Script Descriptions (Alphabetical Order)</h2>
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
        <td>Tests the availability of service ports (e.g., RDP, DNS, SMTP) for network validation.</td>
      </tr>
      <tr>
        <td><code>Create-NewDHCPReservations.ps1</code></td>
        <td>Creates new DHCP reservations via GUI—supports OU filtering and auto IP suggestions.</td>
      </tr>
      <tr>
        <td><code>Inventory-WSUSConfigs-Tool.ps1</code></td>
        <td>Extracts WSUS server details, update statistics, and configurations to <code>.csv</code>.</td>
      </tr>
      <tr>
        <td><code>Restart-NetworkAdapter.ps1</code></td>
        <td>GUI tool to safely restart adapters—resolves stuck interfaces or driver glitches.</td>
      </tr>
      <tr>
        <td><code>Restart-SpoolerPoolServices.ps1</code></td>
        <td>Restarts Spooler/LPD services on demand with verbose logging and status feedback.</td>
      </tr>
      <tr>
        <td><code>Retrieve-DHCPReservations.ps1</code></td>
        <td>Retrieves reservations by hostname or MAC; exports filtered data to <code>.csv</code>.</td>
      </tr>
      <tr>
        <td><code>Retrieve-Empty-DNSReverseLookupZone.ps1</code></td>
        <td>Finds empty reverse lookup zones for DNS hygiene and cleanup tasks.</td>
      </tr>
      <tr>
        <td><code>Retrieve-ServersDiskSpace.ps1</code></td>
        <td>Gathers free/used disk space data across remote servers and logs usage ratios.</td>
      </tr>
      <tr>
        <td><code>Synchronize-ADComputerTime.ps1</code></td>
        <td>Force-syncs time on AD-joined computers for Kerberos and log integrity.</td>
      </tr>
      <tr>
        <td><code>Transfer-DHCPScopes.ps1</code></td>
        <td>Exports/imports DHCP scopes between servers. Includes rollback and progress logging.</td>
      </tr>
      <tr>
        <td><code>Update-DNS-and-Sites-Services.ps1</code></td>
        <td>Updates DNS Zones and AD Sites/Subnets from DHCP leases for hybrid environments.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Run the Script:</strong> Right-click > <code>Run with PowerShell</code> or launch via console.</li>
    <li><strong>Input Parameters:</strong> Follow GUI prompts or CLI options as needed.</li>
    <li><strong>Review Results:</strong> Check <code>.log</code> files and exported <code>.csv</code> in the script’s working directory.</li>
  </ol>

  <hr />

  <h2>📄 Logging and Reports</h2>
  <ul>
    <li><strong>📂 Log Directory:</strong> <code>C:\Logs-TEMP\</code> (or <code>C:\ITSM-Logs-WKS\</code> for ITSM-tagged tools).</li>
    <li><strong>📄 Log Format:</strong> Verbose and timestamped <code>.log</code> files for diagnostics.</li>
    <li><strong>📊 Report Format:</strong> Clean, structured <code>.csv</code> exports for import into Excel or SIEMs.</li>
  </ul>

  <hr />

  <h2>💡 Optimization Tips</h2>
  <ul>
    <li><strong>🗓️ Schedule Execution:</strong> Use Task Scheduler for periodic network health checks.</li>
    <li><strong>📁 Centralize Logs:</strong> Store output files on a shared SMB path for team visibility.</li>
    <li><strong>⚙️ Customize Logic:</strong> Tailor script filters and modules for your infrastructure zones.</li>
  </ul>
</div>
