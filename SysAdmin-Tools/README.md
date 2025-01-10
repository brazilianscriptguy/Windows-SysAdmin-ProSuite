<div>
  <h1>🔧 SysAdmin-Tools Suite</h1>

  <h2>📄 Overview</h2>
  <p>
    The <strong>SysAdmin-Tools</strong> suite provides a powerful collection of PowerShell scripts designed to streamline and automate the management of 
    Active Directory (AD), Windows Server roles, network infrastructure, and workstation configurations. These scripts simplify complex administrative tasks, 
    enhance operational efficiency, and ensure compliance and security across IT environments.
  </p>
  <ul>
    <li><strong>User-Friendly Interfaces:</strong> All scripts include a GUI for intuitive use.</li>
    <li><strong>Detailed Logging:</strong> All scripts generate <code>.log</code> files for audit trails and troubleshooting.</li>
    <li><strong>Exportable Reports:</strong> Reports are often exported in <code>.csv</code> format for integration with Reporting and Analytics Tools.</li>
  </ul>

  <hr />

  <h2>📂 Folder Structure and Categories</h2>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;"><strong>Folder Name</strong></th>
        <th style="padding: 8px;">Description</th>
        <th style="padding: 8px;">Scripts</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td style="padding: 8px;"><strong>ActiveDirectory-Management</strong></td>
        <td style="padding: 8px;">Tools for managing Active Directory, including user accounts, computer accounts, group policies, and directory synchronization.</td>
        <td style="padding: 8px;">
          <ul>
            <li><code>Add-ADComputers-GrantPermissions.ps1</code></li>
            <li><code>Manage-FSMOs-Roles.ps1</code></li>
            <li><code>Inventory-ADUserLastLogon.ps1</code></li>
            <li><code>Synchronize-ADForestDCs.ps1</code></li>
          </ul>
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;"><strong>GroupPolicyObjects-Templates</strong></td>
        <td style="padding: 8px;">A collection of ready-to-use GPO templates designed for seamless import into a new Windows Server Forest and Domain structure.</td>
        <td style="padding: 8px;">
          <ul>
            <li><code>enable-logon-message-workstations</code></li>
            <li><code>itsm-template-ALL-workstations</code></li>
            <li><code>install-cmdb-fusioninventory-agent</code></li>
            <li><code>wsus-update-workstation-MODEL</code></li>
          </ul>
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;"><strong>Network-and-Infrastructure-Management</strong></td>
        <td style="padding: 8px;">Scripts for managing network services (e.g., DHCP, DNS, WSUS) and ensuring reliable infrastructure operations.</td>
        <td style="padding: 8px;">
          <ul>
            <li><code>Create-NewDHCPReservations.ps1</code></li>
            <li><code>Update-DNS-and-Sites-Services.ps1</code></li>
            <li><code>Transfer-DHCPScopes.ps1</code></li>
            <li><code>Restart-NetworkAdapter.ps1</code></li>
          </ul>
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;"><strong>Security-and-Process-Optimization</strong></td>
        <td style="padding: 8px;">Tools for optimizing system performance, enforcing compliance, and enhancing security.</td>
        <td style="padding: 8px;">
          <ul>
            <li><code>Remove-Softwares-NonCompliance-Tool.ps1</code></li>
            <li><code>Unjoin-ADComputer-and-Cleanup.ps1</code></li>
            <li><code>Initiate-MultipleRDPSessions.ps1</code></li>
            <li><code>Remove-EmptyFiles-or-DateRange.ps1</code></li>
          </ul>
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;"><strong>SystemConfiguration-and-Deployment</strong></td>
        <td style="padding: 8px;">Tools for deploying and configuring software, managing group policies, and maintaining consistent system settings across the domain.</td>
        <td style="padding: 8px;">
          <ul>
            <li><code>Deploy-FusionInventoryAgent-viaGPO.ps1</code></li>
            <li><code>Install-KMSLicensingServer-Tool.ps1</code></li>
            <li><code>Clear-and-ReSyncGPOs-ADComputers.ps1</code></li>
            <li><code>Copy-and-Sync-Folder-to-ADComputers-viaGPO.ps1</code></li>
          </ul>
        </td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;"><strong>Requirement</strong></th>
        <th style="padding: 8px;">Details</th>
        <th style="padding: 8px;">Command</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td style="padding: 8px;"><strong>Remote Server Administration Tools (RSAT)</strong></td>
        <td style="padding: 8px;">Install RSAT components for managing AD, DNS, DHCP, and other server roles.</td>
        <td style="padding: 8px;"><code>Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online</code></td>
      </tr>
      <tr>
        <td style="padding: 8px;"><strong>PowerShell Version</strong></td>
        <td style="padding: 8px;">Use PowerShell 5.1 or later. Verify your version.</td>
        <td style="padding: 8px;"><code>$PSVersionTable.PSVersion</code></td>
      </tr>
      <tr>
        <td style="padding: 8px;"><strong>Administrator Privileges</strong></td>
        <td style="padding: 8px;">Scripts require elevated permissions to perform administrative tasks.</td>
        <td style="padding: 8px;">N/A</td>
      </tr>
      <tr>
        <td style="padding: 8px;"><strong>Execution Policy</strong></td>
        <td style="padding: 8px;">Temporarily allow script execution.</td>
        <td style="padding: 8px;"><code>Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process</code></td>
      </tr>
      <tr>
        <td style="padding: 8px;"><strong>Dependencies</strong></td>
        <td style="padding: 8px;">Ensure all required software components and modules (e.g., <code>ActiveDirectory</code>, <code>DHCPServer</code>) are installed.</td>
        <td style="padding: 8px;">N/A</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>📝 Logging and Reporting</h2>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;"><strong>Type</strong></th>
        <th style="padding: 8px;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td style="padding: 8px;"><strong>Logs</strong></td>
        <td style="padding: 8px;">Each script generates <code>.log</code> files for tracking operations and debugging.</td>
      </tr>
      <tr>
        <td style="padding: 8px;"><strong>Reports</strong></td>
        <td style="padding: 8px;">Many scripts export results in <code>.csv</code> format for reporting and analysis.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>❓ Additional Assistance</h2>
  <p>
    These scripts are fully customizable to fit your unique requirements. For more information on setup or assistance with specific tools, refer to the included <code>README.md</code> or the detailed documentation available in each subfolder.
  </p>

  <div align="center">
    <a href="mailto:luizhamilton.lhr@gmail.com" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail" alt="Email Badge">
    </a>
    <a href="https://www.patreon.com/c/brazilianscriptguy" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge&logo=patreon" alt="Support on Patreon Badge">
    </a>
    <a href="https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp" alt="WhatsApp Badge">
    </a>
    <a href="https://github.com/brazilianscriptguy/BlueTeam-Tools/issues" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github" alt="GitHub Issues Badge">
    </a>
  </div>
</div>
