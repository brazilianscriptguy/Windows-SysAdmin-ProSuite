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

  <h3>1. ActiveDirectory-Management</h3>
  <p>
    Tools for managing Active Directory, including user accounts, computer accounts, group policies, and directory synchronization.
  </p>
  <ul>
    <li><code>Add-ADComputers-GrantPermissions.ps1</code></li>
    <li><code>Manage-FSMOs-Roles.ps1</code></li>
    <li><code>Inventory-ADUserLastLogon.ps1</code></li>
    <li><code>Synchronize-ADForestDCs.ps1</code></li>
  </ul>
  <p>
    📄 
    <a href="ActiveDirectory-Management/README.md" target="_blank">
      <img src="https://img.shields.io/badge/View%20ActiveDirectory%20Management-README-blue?style=flat-square&logo=github" 
      alt="ActiveDirectory-Management README Badge">
    </a>
  </p>

  <h3>2. GroupPolicyObjects-Templates</h3>
  <p>
    A collection of ready-to-use GPO templates designed for seamless import into a new Windows Server Forest and Domain structure.
  </p>
  <ul>
    <li><code>enable-logon-message-workstations</code></li>
    <li><code>itsm-template-ALL-workstations</code></li>
    <li><code>install-cmdb-fusioninventory-agent</code></li>
    <li><code>wsus-update-workstation-MODEL</code></li>
  </ul>
  <p>
    📄 
    <a href="GPOs-Templates/README.md" target="_blank">
      <img src="https://img.shields.io/badge/View%20GPO%20Templates-README-blue?style=flat-square&logo=github" 
      alt="GPOs-Templates README Badge">
    </a>
  </p>

  <h3>3. Network-and-Infrastructure-Management</h3>
  <p>
    Scripts for managing network services (e.g., DHCP, DNS, WSUS) and ensuring reliable infrastructure operations.
  </p>
  <ul>
    <li><code>Create-NewDHCPReservations.ps1</code></li>
    <li><code>Update-DNS-and-Sites-Services.ps1</code></li>
    <li><code>Transfer-DHCPScopes.ps1</code></li>
    <li><code>Restart-NetworkAdapter.ps1</code></li>
  </ul>
  <p>
    📄 
    <a href="Network-and-Infrastructure-Management/README.md" target="_blank">
      <img src="https://img.shields.io/badge/View%20Network%20Management-README-blue?style=flat-square&logo=github" 
      alt="Network Management README Badge">
    </a>
  </p>

  <h3>4. Security-and-Process-Optimization</h3>
  <p>
    Tools for optimizing system performance, enforcing compliance, and enhancing security.
  </p>
  <ul>
    <li><code>Remove-Softwares-NonCompliance-Tool.ps1</code></li>
    <li><code>Unjoin-ADComputer-and-Cleanup.ps1</code></li>
    <li><code>Initiate-MultipleRDPSessions.ps1</code></li>
    <li><code>Remove-EmptyFiles-or-DateRange.ps1</code></li>
  </ul>
  <p>
    📄 
    <a href="Security-and-Process-Optimization/README.md" target="_blank">
      <img src="https://img.shields.io/badge/View%20Security%20Optimization-README-blue?style=flat-square&logo=github" 
      alt="Security Optimization README Badge">
    </a>
  </p>

  <h3>5. SystemConfiguration-and-Deployment</h3>
  <p>
    Tools for deploying and configuring software, managing group policies, and maintaining consistent system settings across the domain.
  </p>
  <ul>
    <li><code>Deploy-FusionInventoryAgent-viaGPO.ps1</code></li>
    <li><code>Install-KMSLicensingServer-Tool.ps1</code></li>
    <li><code>Clear-and-ReSyncGPOs-ADComputers.ps1</code></li>
    <li><code>Copy-and-Sync-Folder-to-ADComputers-viaGPO.ps1</code></li>
  </ul>
  <p>
    📄 
    <a href="SystemConfiguration-and-Deployment/README.md" target="_blank">
      <img src="https://img.shields.io/badge/View%20System%20Deployment-README-blue?style=flat-square&logo=github" 
      alt="System Deployment README Badge">
    </a>
  </p>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>🖥️ Remote Server Administration Tools (RSAT):</strong>
      <p>Install RSAT components for managing AD, DNS, DHCP, and other server roles.</p>
      <pre><code>Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online</code></pre>
    </li>
    <li>
      <strong>⚙️ PowerShell Version:</strong>
      <p>Use PowerShell 5.1 or later. Verify your version:</p>
      <pre><code>$PSVersionTable.PSVersion</code></pre>
    </li>
    <li><strong>🔑 Administrator Privileges:</strong> Scripts require elevated permissions to perform administrative tasks.</li>
    <li>
      <strong>🔧 Execution Policy:</strong>
      <p>Temporarily allow script execution with:</p>
      <pre><code>Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process</code></pre>
    </li>
    <li>
      <strong>📦 Dependencies:</strong>
      <p>Ensure all required software components and modules (e.g., <code>ActiveDirectory</code>, <code>DHCPServer</code>) are installed.</p>
    </li>
  </ol>

  <hr />

  <h2>🚀 Getting Started</h2>
  <ol>
    <li>
      Clone or download this repository:
      <pre><code>git clone https://github.com/brazilianscriptguy/SysAdmin-Tools.git</code></pre>
    </li>
    <li>Navigate to the relevant subfolder and review the <code>README.md</code> file for detailed script descriptions and usage instructions.</li>
    <li>Run scripts using PowerShell:
      <pre><code>.\ScriptName.ps1</code></pre>
    </li>
  </ol>

  <hr />

  <h2>📝 Logging and Reporting</h2>
  <ul>
    <li><strong>Logs:</strong> Each script generates <code>.log</code> files for tracking operations and debugging.</li>
    <li><strong>Reports:</strong> Many scripts export results in <code>.csv</code> format for reporting and analysis.</li>
  </ul>

  <hr />

  <h2>❓ Support and Contributions</h2>
  <p>
    For questions or contributions:
    <ul>
      <li>Open an issue or submit a pull request on GitHub.</li>
      <li>Your feedback and collaboration are always welcome!</li>
    </ul>
  </p>
</div>
