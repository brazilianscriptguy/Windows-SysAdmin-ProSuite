<div>
  <h1>🌐 Network and Infrastructure Management Tools</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>Network and Infrastructure Management Folder</strong> contains a suite of 
    <strong>PowerShell scripts</strong> designed to simplify and automate the management of network services such as DNS, DHCP, and WSUS, 
    as well as maintaining key infrastructure components. These tools aim to enhance reliability, improve efficiency, and ensure accurate configurations 
    across your IT environment.
  </p>

  <h3>Key Features:</h3>
  <ul>
    <li><strong>User-Friendly GUI:</strong> Simplifies interaction with intuitive graphical interfaces for selected scripts.</li>
    <li><strong>Detailed Logging:</strong> All scripts generate <code>.log</code> files for comprehensive tracking and troubleshooting.</li>
    <li><strong>Exportable Reports:</strong> Outputs in <code>.csv</code> format for streamlined analysis and reporting.</li>
    <li><strong>Efficient Network Management:</strong> Automates critical network tasks, reducing manual effort and improving accuracy.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell</strong>
      <ul>
        <li>PowerShell 5.1 or later must be enabled on your system.</li>
        <li>Verify your version with:
          <pre><code>$PSVersionTable.PSVersion</code></pre>
        </li>
      </ul>
    </li>
    <li>
      <strong>🔑 Administrator Privileges</strong>
      <p>Scripts may require elevated permissions to access and configure network services.</p>
    </li>
    <li>
      <strong>🖥️ Remote Server Administration Tools (RSAT)</strong>
      <p>Install RSAT components for managing DNS, DHCP, and WSUS roles. Use the following command to install:</p>
      <pre><code>Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online</code></pre>
    </li>
    <li>
      <strong>⚙️ Execution Policy</strong>
      <p>Temporarily set the execution policy to allow running scripts:</p>
      <pre><code>Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process</code></pre>
    </li>
    <li>
      <strong>Required Modules:</strong> Ensure necessary modules such as <code>ActiveDirectory</code> and <code>DNSServer</code> are installed and imported as needed.
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
        <td>Verifies the real-time connectivity of specific service ports, ensuring that critical services are reachable and properly configured.</td>
      </tr>
      <tr>
        <td><strong>Create-NewDHCPReservations.ps1</strong></td>
        <td>Streamlines the creation of new DHCP reservations, enabling domain and scope selection along with available IP allocation.</td>
      </tr>
      <tr>
        <td><strong>Inventory-WSUSConfigs-Tool.ps1</strong></td>
        <td>Collects and exports WSUS server details, including update statistics, computer group configurations, and log file sizes, through an interactive GUI.</td>
      </tr>
      <tr>
        <td><strong>Restart-NetworkAdapter.ps1</strong></td>
        <td>Provides a user-friendly GUI to restart network adapters, ensuring consistent connectivity with minimal user effort.</td>
      </tr>
      <tr>
        <td><strong>Restart-SpoolerPoolServices.ps1</strong></td>
        <td>Restarts Spooler and LPD services with enhanced logging for troubleshooting and auditing purposes.</td>
      </tr>
      <tr>
        <td><strong>Retrieve-DHCPReservations.ps1</strong></td>
        <td>Retrieves DHCP reservations, allowing filtering by hostname or description to ensure accurate resource documentation.</td>
      </tr>
      <tr>
        <td><strong>Retrieve-Empty-DNSReverseLookupZone.ps1</strong></td>
        <td>Identifies empty DNS reverse lookup zones, aiding in DNS cleanup and ensuring proper configuration.</td>
      </tr>
      <tr>
        <td><strong>Retrieve-ServersDiskSpace.ps1</strong></td>
        <td>Collects disk space usage data from servers, providing actionable insights for resource management and compliance.</td>
      </tr>
      <tr>
        <td><strong>Synchronize-ADComputerTime.ps1</strong></td>
        <td>Ensures consistent time synchronization across AD computers, accommodating different time zones to maintain network reliability.</td>
      </tr>
      <tr>
        <td><strong>Transfer-DHCPScopes.ps1</strong></td>
        <td>Facilitates the export and import of DHCP scopes between servers, featuring error handling, progress tracking, and inactivation options.</td>
      </tr>
      <tr>
        <td><strong>Update-DNS-and-Sites-Services.ps1</strong></td>
        <td>Automates updates to DNS zones and AD Sites and Services subnets based on DHCP data, ensuring accurate and up-to-date network configurations.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Run the Script:</strong> Launch the desired script using the <code>Run With PowerShell</code> option.</li>
    <li><strong>Provide Inputs:</strong> Follow on-screen prompts or customize parameters as required.</li>
    <li><strong>Review Outputs:</strong> Check generated <code>.log</code> files and exported <code>.csv</code> reports for results.</li>
  </ol>

  <hr />

  <h2>📝 Logging and Output</h2>
  <ul>
    <li><strong>📄 Logs:</strong> Each script generates detailed logs in <code>.log</code> format.</li>
    <li><strong>📊 Reports:</strong> Scripts export data in <code>.csv</code> format for auditing and reporting.</li>
  </ul>

  <hr />

  <h2>💡 Tips for Optimization</h2>
  <ul>
    <li><strong>Automate Execution:</strong> Schedule scripts to run periodically using Task Scheduler.</li>
    <li><strong>Centralize Logs and Reports:</strong> Store <code>.log</code> and <code>.csv</code> files in a shared repository for collaboration and analysis.</li>
    <li><strong>Customize Scripts:</strong> Adjust script parameters to align with your organization's specific needs.</li>
  </ul>
</div>
