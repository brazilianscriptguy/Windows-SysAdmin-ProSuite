<div>
  <h1>⚙️ System Configuration and Deployment Tools</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>System Configuration and Deployment</strong> folder contains a curated set of 
    <strong>PowerShell scripts</strong> for deploying and configuring software, enforcing GPO policies, and applying consistent system settings. 
    These tools are optimized for scalable, secure, and automated management of workstations and servers in Active Directory (AD) environments.
  </p>

  <h3>✅ Key Features</h3>
  <ul>
    <li><strong>Graphical Interface:</strong> GUI-based scripts simplify use for administrators and support staff.</li>
    <li><strong>Centralized Logging:</strong> Each execution logs results in structured <code>.log</code> files.</li>
    <li><strong>Streamlined Deployment:</strong> Automates software installs, policy updates, and environment standardization.</li>
    <li><strong>Policy Compliance:</strong> Removes unauthorized software and enforces configuration baselines.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell:</strong>
      <ul>
        <li>Requires PowerShell version 5.1 or later.</li>
        <li>Check version:
          <pre><code>$PSVersionTable.PSVersion</code></pre>
        </li>
      </ul>
    </li>
    <li>
      <strong>🔑 Administrator Privileges:</strong>
      <p>All scripts require elevated permissions to execute configuration and deployment actions.</p>
    </li>
    <li>
      <strong>📦 Required Modules:</strong>
      <p>Ensure modules such as <code>GroupPolicy</code> and <code>PSWindowsUpdate</code> are available.</p>
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
      <tr><td><strong>Broadcast-ADUser-LogonMessage-viaGPO.ps1</strong></td><td>Displays custom logon messages via GPO to domain users.</td></tr>
      <tr><td><strong>Cleanup-WebBrowsers-Tool.ps1</strong></td><td>Clears browser cache, cookies, and session data for better performance and privacy.</td></tr>
      <tr><td><strong>Clear-and-ReSyncGPOs-ADComputers.ps1</strong></td><td>Resets and re-applies GPOs across all domain-joined machines.</td></tr>
      <tr><td><strong>Copy-and-Sync-Folder-to-ADComputers-viaGPO.ps1</strong></td><td>Synchronizes local folders from a network share using GPO scripting.</td></tr>
      <tr><td><strong>Deploy-FortiClientVPN-viaGPO.ps1</strong></td><td>Installs FortiClient VPN across endpoints via GPO for secure access.</td></tr>
      <tr><td><strong>Deploy-FusionInventoryAgent-viaGPO.ps1</strong></td><td>Deploys FusionInventory Agent for inventory tracking and reporting.</td></tr>
      <tr><td><strong>Deploy-GLPIAgent-viaGPO.ps1</strong></td><td>Installs GLPI Agent for asset and inventory management.</td></tr>
      <tr><td><strong>Deploy-KasperskyAV-viaGPO.ps1</strong></td><td>Deploys Kaspersky Endpoint Security using GPO deployment methods.</td></tr>
      <tr><td><strong>Deploy-PowerShell-viaGPO.ps1</strong></td><td>Ensures correct installation and updates of PowerShell runtime.</td></tr>
      <tr><td><strong>Deploy-ZoomWorkplace-viaGPO.ps1</strong></td><td>Deploys Zoom app to domain computers for enterprise communication.</td></tr>
      <tr><td><strong>Enhance-BGInfoDisplay-viaGPO.ps1</strong></td><td>Applies BGInfo to display system metadata on desktops.</td></tr>
      <tr><td><strong>Install-KMSLicensingServer-Tool.ps1</strong></td><td>Sets up a KMS server for centralized license activation.</td></tr>
      <tr><td><strong>Install-RDSLicensingServer-Tool.ps1</strong></td><td>Configures RDS Licensing Server for CAL management.</td></tr>
      <tr><td><strong>Remove-ReaQtaHive-Services-Tool.ps1</strong></td><td>Uninstalls ReaQta services and cleans up all associated artifacts.</td></tr>
      <tr><td><strong>Remove-SharedFolders-and-Drives-viaGPO.ps1</strong></td><td>Removes non-compliant shares and mapped drives using GPO.</td></tr>
      <tr><td><strong>Remove-Softwares-NonCompliance-Tool.ps1</strong></td><td>Uninstalls manually defined non-compliant software on the local machine.</td></tr>
      <tr><td><strong>Remove-Softwares-NonCompliance-viaGPO.ps1</strong></td><td>Automates unauthorized software removal via GPO execution.</td></tr>
      <tr><td><strong>Rename-DiskVolumes-viaGPO.ps1</strong></td><td>Applies standardized labels to volumes across systems via GPO.</td></tr>
      <tr><td><strong>Reset-and-Sync-DomainGPOs-viaGPO.ps1</strong></td><td>Force-resets and reapplies all domain GPOs.</td></tr>
      <tr><td><strong>Retrieve-LocalMachine-InstalledSoftwareList.ps1</strong></td><td>Exports all installed software to a clean CSV (ANSI encoded).</td></tr>
      <tr><td><strong>Uninstall-SelectedApp-Tool.ps1</strong></td><td>Interactive GUI for selecting and removing specific apps.</td></tr>
      <tr><td><strong>Update-ADComputer-Winget-Explicit.ps1</strong></td><td>Uses <code>winget</code> to update selected packages on workstations.</td></tr>
      <tr><td><strong>Update-ADComputer-Winget-viaGPO.ps1</strong></td><td>Pushes scheduled <code>winget</code> updates using GPO mechanisms.</td></tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Run the Script:</strong> Right-click on the <code>.ps1</code> file and choose <em>Run with PowerShell</em>.</li>
    <li><strong>Input Parameters:</strong> Follow GUI prompts or configure script variables as needed.</li>
    <li><strong>Check Results:</strong> Logs are saved in <code>C:\Logs-TEMP\</code> or a predefined directory. CSV exports may be generated for reporting.</li>
  </ol>

  <hr />

  <h2>📁 Complementary Files</h2>
  <ul>
    <li><strong>Broadcast-ADUser-LogonMessage-viaGPO.hta:</strong> GUI editor for customizing domain logon messages.</li>
    <li><strong>Enhance-BGInfoDisplay-viaGPO.bgi:</strong> Custom BGInfo configuration template for system data overlays.</li>
    <li><strong>Remove-Softwares-NonCompliance-Tool.txt:</strong> Text-based config file listing software titles to remove.</li>
  </ul>

  <hr />

  <h2>💡 Optimization Tips</h2>
  <ul>
    <li><strong>Leverage GPO Scheduling:</strong> Trigger scripts during computer startup using GPO scripts.</li>
    <li><strong>Use Task Scheduler:</strong> Schedule repetitive maintenance tasks using Windows Task Scheduler.</li>
    <li><strong>Centralize Logs:</strong> Redirect logs to a network share for unified audit and monitoring.</li>
    <li><strong>Parameterize for Reuse:</strong> Adjust variables and arguments to fit different deployment profiles.</li>
  </ul>
</div>
