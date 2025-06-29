<div>
  <h1>🌐 Network and Infrastructure Management Tools</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>Network and Infrastructure Management</strong> folder contains a curated set of 
    <strong>PowerShell scripts</strong> built to automate and optimize administration of core network services such as DNS, DHCP, WSUS, 
    and related infrastructure functions. These tools aim to improve consistency, availability, and compliance across enterprise networks.
  </p>

  <h3>Key Features:</h3>
  <ul>
    <li><strong>Graphical Interfaces:</strong> Several tools feature interactive GUIs to streamline configuration.</li>
    <li><strong>Comprehensive Logging:</strong> Each script produces <code>.log</code> files for tracking actions and diagnosing issues.</li>
    <li><strong>Exportable Reports:</strong> Scripts export <code>.csv</code> files with structured data for auditing and integration with analysis tools.</li>
    <li><strong>Network Services Automation:</strong> Reduces manual workload by automating DNS, DHCP, WSUS, and service management.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell</strong>
      <ul>
        <li>Requires PowerShell 5.1 or later.</li>
        <li>Check your version with:
          <pre><code>$PSVersionTable.PSVersion</code></pre>
        </li>
      </ul>
    </li>
    <li>
      <strong>🔑 Administrator Privileges</strong>
      <p>Required for modifying system and network configurations.</p>
    </li>
    <li>
      <strong>🖥️ RSAT Components</strong>
      <p>Install Remote Server Administration Tools (DNS, DHCP, etc.) with:</p>
      <pre><code>Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online</code></pre>
    </li>
    <li>
      <strong>🔧 Execution Policy</strong>
      <p>Temporarily allow script execution:</p>
      <pre><code>Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process</code></pre>
    </li>
    <li>
      <strong>📦 Dependencies</strong>
      <p>Ensure modules such as <code>ActiveDirectory</code>, <code>DHCPServer</code>, <code>DNSServer</code> are installed and imported.</p>
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
        <td>Verifies real-time connectivity of critical ports for network services.</td>
      </tr>
      <tr>
        <td><strong>Create-NewDHCPReservations.ps1</strong></td>
        <td>Creates new DHCP reservations with support for scope/domain selection.</td>
      </tr>
      <tr>
        <td><strong>Inventory-WSUSConfigs-Tool.ps1</strong></td>
        <td>Gathers and exports WSUS server configuration details using a GUI.</td>
      </tr>
      <tr>
        <td><strong>Restart-NetworkAdapter.ps1</strong></td>
        <td>Restarts network adapters via a graphical interface for quick recovery.</td>
      </tr>
      <tr>
        <td><strong>Restart-SpoolerPoolServices.ps1</strong></td>
        <td>Restarts the Print Spooler and LPD services with logging.</td>
      </tr>
      <tr>
        <td><strong>Retrieve-DHCPReservations.ps1</strong></td>
        <td>Exports DHCP reservations and supports filtering by hostname or description.</td>
      </tr>
      <tr>
        <td><strong>Retrieve-Empty-DNSReverseLookupZone.ps1</strong></td>
        <td>Identifies empty reverse lookup DNS zones for cleanup or review.</td>
      </tr>
      <tr>
        <td><strong>Retrieve-ServersDiskSpace.ps1</strong></td>
        <td>Collects and reports disk usage from target servers for capacity planning.</td>
      </tr>
      <tr>
        <td><strong>Synchronize-ADComputerTime.ps1</strong></td>
        <td>Standardizes time across AD-joined devices and adjusts by region/timezone.</td>
      </tr>
      <tr>
        <td><strong>Transfer-DHCPScopes.ps1</strong></td>
        <td>Transfers DHCP scopes between servers with options for inactivation and rollback.</td>
      </tr>
      <tr>
        <td><strong>Update-DNS-and-Sites-Services.ps1</strong></td>
        <td>Updates AD Sites and DNS Subnets based on DHCP reservations and exports logs.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Run the Script:</strong> Right-click the file and choose <code>Run with PowerShell</code> or run it from an elevated shell.</li>
    <li><strong>Provide Inputs:</strong> Follow any on-screen prompts or use preconfigured variables in the script.</li>
    <li><strong>Review Outputs:</strong> Inspect <code>.log</code> files for execution logs and <code>.csv</code> files for reports.</li>
  </ol>

  <hr />

  <h2>📄 Complementary Files Overview</h2>
  <ul>
    <li><strong>WSUS-Exported-Configs.csv:</strong> Export file containing WSUS server metadata and group settings.</li>
    <li><strong>DHCP-Scope-Transfer-Log.log:</strong> Output log capturing DHCP transfer activity and status.</li>
  </ul>

  <hr />

  <h2>💡 Tips for Optimization</h2>
  <ul>
    <li><strong>Automate Execution:</strong> Schedule tasks using Task Scheduler or deploy through GPO.</li>
    <li><strong>Centralize Output:</strong> Store logs and reports in a shared folder accessible to IT admins.</li>
    <li><strong>Adjust for Scale:</strong> Use filtering and error-handling features to support large environments.</li>
    <li><strong>Customize Scripts:</strong> Modify variables and settings for your network architecture.</li>
  </ul>
</div>
