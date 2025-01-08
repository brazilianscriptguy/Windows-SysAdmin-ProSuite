<div>
  <h1>🌐 Network and Infrastructure Management Tools</h1>

  <h2>📄 Overview</h2>
  <p>
    This folder contains a suite of PowerShell scripts aimed at simplifying and automating the management of network services such as DNS, DHCP, and WSUS, as well as maintaining key infrastructure components. These tools are designed to enhance reliability, improve efficiency, and ensure accurate configurations across your IT environment.
  </p>

  <hr />

  <h2>📜 Script List and Descriptions</h2>
  <table border="1" style="border-collapse: collapse; width: 100%;">
    <thead>
      <tr>
        <th style="padding: 8px; text-align: left;">Script Name</th>
        <th style="padding: 8px; text-align: left;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td>Check-ServicesPort-Connectivity.ps1</td>
        <td>
          Verifies the real-time connectivity of specific service ports, ensuring that critical services are reachable and properly configured.
        </td>
      </tr>
      <tr>
        <td>Create-NewDHCPReservations.ps1</td>
        <td>
          Streamlines the creation of new DHCP reservations, enabling domain and scope selection along with available IP allocation.
        </td>
      </tr>
      <tr>
        <td>Inventory-WSUSConfigs-Tool.ps1</td>
        <td>
          Collects and exports WSUS server details, including update statistics, computer group configurations, and log file sizes, through an interactive GUI.
        </td>
      </tr>
      <tr>
        <td>Restart-NetworkAdapter.ps1</td>
        <td>
          Provides a user-friendly GUI to restart network adapters, ensuring consistent connectivity with minimal user effort.
        </td>
      </tr>
      <tr>
        <td>Restart-SpoolerPoolServices.ps1</td>
        <td>
          Restarts Spooler and LPD services with enhanced logging for troubleshooting and auditing purposes.
        </td>
      </tr>
      <tr>
        <td>Retrieve-DHCPReservations.ps1</td>
        <td>
          Retrieves DHCP reservations, allowing filtering by hostname or description to ensure accurate resource documentation.
        </td>
      </tr>
      <tr>
        <td>Retrieve-Empty-DNSReverseLookupZone.ps1</td>
        <td>
          Identifies empty DNS reverse lookup zones, aiding in DNS cleanup and ensuring proper configuration.
        </td>
      </tr>
      <tr>
        <td>Retrieve-ServersDiskSpace.ps1</td>
        <td>
          Collects disk space usage data from servers, providing actionable insights for resource management and compliance.
        </td>
      </tr>
      <tr>
        <td>Synchronize-ADComputerTime.ps1</td>
        <td>
          Ensures consistent time synchronization across AD computers, accommodating different time zones to maintain network reliability.
        </td>
      </tr>
      <tr>
        <td>Transfer-DHCPScopes.ps1</td>
        <td>
          Facilitates the export and import of DHCP scopes between servers, featuring error handling, progress tracking, and inactivation options.
        </td>
      </tr>
      <tr>
        <td>Update-DNS-and-Sites-Services.ps1</td>
        <td>
          Automates updates to DNS zones and AD Sites and Services subnets based on DHCP data, ensuring accurate and up-to-date network configurations.
        </td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🔍 How to Use</h2>
  <p>
    Each script includes a comprehensive header with detailed instructions. Open the script in a PowerShell editor to review its prerequisites, parameters, and execution steps. Follow the provided comments to customize and execute the scripts effectively.
  </p>
</div>
