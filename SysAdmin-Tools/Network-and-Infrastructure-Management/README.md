<div>
  <h1>🌐 Network and Infrastructure Management Tools</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>Network and Infrastructure Management</strong> folder provides a set of 
    <strong>PowerShell scripts</strong> that automate and streamline administrative tasks related to network services such as 
    <strong>DNS, DHCP, WSUS</strong>, and <strong>infrastructure diagnostics</strong>. These tools are tailored to help IT administrators 
    ensure service availability, accurate configurations, and efficient infrastructure operations.
  </p>

  <h3>Key Features:</h3>
  <ul>
    <li><strong>User-Friendly GUI:</strong> Intuitive interfaces for selected scripts to simplify execution and data input.</li>
    <li><strong>Detailed Logging:</strong> Generates <code>.log</code> files to assist with execution traceability and troubleshooting.</li>
    <li><strong>Exportable Reports:</strong> Provides <code>.csv</code> outputs for reporting, documentation, and audits.</li>
    <li><strong>Automated Infrastructure Tasks:</strong> Scripts cover real-world use cases like DHCP migration, DNS cleanup, WSUS audits, and more.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell</strong>
      <ul>
        <li>Ensure <strong>PowerShell 5.1 or later</strong> is installed and enabled.</li>
        <li>Check your version with:
          <pre><code>$PSVersionTable.PSVersion</code></pre>
        </li>
      </ul>
    </li>
    <li>
      <strong>🔑 Administrator Privileges</strong>
      <p>Most scripts require elevated permissions to access system-level and network configurations.</p>
    </li>
    <li>
      <strong>🖥️ Remote Server Administration Tools (RSAT)</strong>
      <p>Install RSAT features to support roles such as DNS, DHCP, and WSUS:</p>
      <pre><code>Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online</code></pre>
    </li>
    <li>
      <strong>⚙️ Execution Policy</strong>
      <p>Ensure script execution is allowed within your session:</p>
      <pre><code>Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process</code></pre>
    </li>
    <li>
      <strong>Required Modules:</strong> Confirm the following modules are available as needed:
      <ul>
        <li><code>ActiveDirectory</code></li>
        <li><code>DNSServer</code></li>
      </ul>
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
        <td><strong>Check-ServicesPort-Connectivity.ps1</strong></td>
        <td>Verifies connectivity of specific service ports across endpoints to validate availability and firewall rules.</td>
      </tr>
      <tr>
        <td><strong>Create-NewDHCPReservations.ps1</strong></td>
        <td>Creates new DHCP reservations using GUI input for hostname, MAC, and IP address, including scope and domain selection.</td>
      </tr>
      <tr>
        <td><strong>Inventory-WSUSConfigs-Tool.ps1</strong></td>
        <td>Collects WSUS configuration data and exports update group stats, patch activity, and repository size information.</td>
      </tr>
      <tr>
        <td><strong>Restart-NetworkAdapter.ps1</strong></td>
        <td>Provides a friendly interface to restart local or remote network adapters and restore connectivity.</td>
      </tr>
      <tr>
        <td><strong>Restart-SpoolerPoolServices.ps1</strong></td>
        <td>Restarts Spooler and LPD services on print servers with execution logging for auditing.</td>
      </tr>
      <tr>
        <td><strong>Retrieve-DHCPReservations.ps1</strong></td>
        <td>Exports DHCP reservations for a selected scope; supports filtering by description or hostname.</td>
      </tr>
      <tr>
        <td><strong>Retrieve-Empty-DNSReverseLookupZone.ps1</strong></td>
        <td>Detects and lists unused reverse DNS zones, supporting DNS cleanup and zone accuracy efforts.</td>
      </tr>
      <tr>
        <td><strong>Retrieve-ServersDiskSpace.ps1</strong></td>
        <td>Queries disk usage and available storage across multiple servers and exports usage stats.</td>
      </tr>
      <tr>
        <td><strong>Synchronize-ADComputerTime.ps1</strong></td>
        <td>Forces time synchronization from domain-joined computers to the domain controller.</td>
      </tr>
      <tr>
        <td><strong>Transfer-DHCPScopes.ps1</strong></td>
        <td>Exports and imports DHCP scopes between servers. Includes options for inactivating source scopes.</td>
      </tr>
      <tr>
        <td><strong>Update-DNS-and-Sites-Services.ps1</strong></td>
        <td>Updates DNS zones and Active Directory Sites/Subnets based on live DHCP lease data.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Run the Script:</strong> Right-click the script file and choose <code>Run with PowerShell</code>.</li>
    <li><strong>Provide Inputs:</strong> Enter required data via GUI or console prompts where applicable.</li>
    <li><strong>Review Outputs:</strong> Review <code>.log</code> and <code>.csv</code> outputs in the default log directories.</li>
  </ol>

  <hr />

  <h2>📝 Logging and Output</h2>
  <ul>
    <li><strong>📄 Logs:</strong> Scripts generate detailed logs in <code>.log</code> format at <code>C:\Logs-TEMP</code> or <code>C:\ITSM-Logs-WKS</code>.</li>
    <li><strong>📊 Reports:</strong> Exported data is available in <code>.csv</code> format for further analysis or documentation.</li>
  </ul>

  <hr />

  <h2>💡 Tips for Optimization</h2>
  <ul>
    <li><strong>🗓️ Automate Execution:</strong> Use Task Scheduler to run health and audit scripts on a recurring basis.</li>
    <li><strong>🧠 Customize Filters:</strong> Modify scope filters or sorting logic inside the scripts to fit enterprise policies.</li>
    <li><strong>📁 Centralize Output:</strong> Send logs and reports to a shared folder or log repository for team access.</li>
  </ul>
</div>
