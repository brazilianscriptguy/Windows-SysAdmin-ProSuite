<div>
  <h1>🌐 Network and Infrastructure Management Tools</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>Network and Infrastructure Management</strong> folder provides a suite of 
    <strong>PowerShell scripts</strong> that automate critical operations across DNS, DHCP, WSUS, and core infrastructure services. 
    These tools are built to improve reliability, reduce manual workload, and maintain consistent network configurations 
    throughout your Active Directory (AD) environment.
  </p>

  <h3>✅ Key Features</h3>
  <ul>
    <li><strong>Graphical Interfaces:</strong> Many scripts offer GUI-based interactions for streamlined management.</li>
    <li><strong>Detailed Logging:</strong> Execution results are saved in structured <code>.log</code> files.</li>
    <li><strong>Exportable Data:</strong> Results are exported in <code>.csv</code> format for further analysis and documentation.</li>
    <li><strong>Service Optimization:</strong> Designed to automate DNS/DHCP/WSUS routines and improve service availability.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell:</strong>
      <ul>
        <li>PowerShell 5.1 or higher is required.</li>
        <li>Check your version:
          <pre><code>$PSVersionTable.PSVersion</code></pre>
        </li>
      </ul>
    </li>
    <li>
      <strong>🔑 Administrator Privileges:</strong>
      <p>Required to execute tasks related to network service configuration.</p>
    </li>
    <li>
      <strong>🖥️ Remote Server Administration Tools (RSAT):</strong>
      <p>Install relevant RSAT features (e.g., DHCP, DNS) using:</p>
      <pre><code>Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online</code></pre>
    </li>
    <li>
      <strong>🔧 Execution Policy:</strong>
      <p>Temporarily enable script execution if needed:</p>
      <pre><code>Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process</code></pre>
    </li>
    <li>
      <strong>📦 Required Modules:</strong>
      <p>Ensure availability of modules like <code>DNSServer</code>, <code>DHCPServer</code>, and <code>ActiveDirectory</code>.</p>
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
      <tr><td><strong>Check-ServicesPort-Connectivity.ps1</strong></td><td>Tests connectivity of key service ports to validate proper communication.</td></tr>
      <tr><td><strong>Create-NewDHCPReservations.ps1</strong></td><td>Facilitates the creation of DHCP reservations with domain/scope selection.</td></tr>
      <tr><td><strong>Inventory-WSUSConfigs-Tool.ps1</strong></td><td>Collects WSUS configuration details and update stats via a GUI interface.</td></tr>
      <tr><td><strong>Restart-NetworkAdapter.ps1</strong></td><td>Restarts selected network adapters using a simple GUI.</td></tr>
      <tr><td><strong>Restart-SpoolerPoolServices.ps1</strong></td><td>Restarts print spooler and LPD services with audit logging.</td></tr>
      <tr><td><strong>Retrieve-DHCPReservations.ps1</strong></td><td>Extracts DHCP reservations and supports filtering by hostname or description.</td></tr>
      <tr><td><strong>Retrieve-Empty-DNSReverseLookupZone.ps1</strong></td><td>Identifies unused or empty reverse lookup DNS zones.</td></tr>
      <tr><td><strong>Retrieve-ServersDiskSpace.ps1</strong></td><td>Gathers disk space data from multiple servers for storage audits.</td></tr>
      <tr><td><strong>Synchronize-ADComputerTime.ps1</strong></td><td>Standardizes time synchronization across AD computers, accounting for different time zones.</td></tr>
      <tr><td><strong>Transfer-DHCPScopes.ps1</strong></td><td>Exports and imports DHCP scopes between servers with progress and error handling.</td></tr>
      <tr><td><strong>Update-DNS-and-Sites-Services.ps1</strong></td><td>Updates DNS zones and AD Sites/Subnets based on DHCP allocation and logs changes.</td></tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Run the Script:</strong> Right-click and choose <em>Run with PowerShell</em> or execute from an elevated console.</li>
    <li><strong>Provide Input:</strong> Follow on-screen prompts or define variables within the script as needed.</li>
    <li><strong>Review Results:</strong> Analyze generated <code>.log</code> files and <code>.csv</code> exports for insight and validation.</li>
  </ol>

  <hr />

  <h2>📝 Logging and Output</h2>
  <ul>
    <li><strong>📄 Log Files:</strong> Execution results and errors are recorded in <code>.log</code> format.</li>
    <li><strong>📊 Reports:</strong> Exported <code>.csv</code> files provide structured output for data processing and compliance.</li>
  </ul>

  <hr />

  <h2>💡 Tips for Optimization</h2>
  <ul>
    <li><strong>Automate Execution:</strong> Use Task Scheduler or GPOs to run scripts on a schedule.</li>
    <li><strong>Centralize Logs:</strong> Redirect output to a shared folder for team access and historical tracking.</li>
    <li><strong>Customize Parameters:</strong> Tailor script arguments to your infrastructure needs and naming conventions.</li>
  </ul>
</div>
