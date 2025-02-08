<div>
  <h1>⚙️ System Configuration and Deployment Tools</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>System Configuration and Deployment Folder</strong> includes a collection of 
    <strong>PowerShell scripts</strong> designed for deploying and configuring software, group policies, and system settings. 
    These tools ensure consistent and efficient management of workstations and servers in Active Directory (AD) environments.
  </p>

  <h3>Key Features:</h3>
  <ul>
    <li><strong>User-Friendly GUI:</strong> Simplifies configuration and deployment tasks for administrators.</li>
    <li><strong>Detailed Logging:</strong> All scripts generate <code>.log</code> files for comprehensive tracking and troubleshooting.</li>
    <li><strong>Efficient Deployment:</strong> Automates software installation, updates, and policy synchronization across devices.</li>
    <li><strong>Compliance Management:</strong> Ensures adherence to organizational policies by removing unauthorized software and standardizing configurations.</li>
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
      <p>Necessary for deploying software, managing GPOs, and accessing sensitive configurations.</p>
    </li>
    <li>
      <strong>Dependencies:</strong> Ensure required modules such as <code>GroupPolicy</code> are installed and available.
    </li>
  </ol>

  <hr />

  <h2>📄 Script Descriptions (Alphabetical Order)</h2>
  <table border="1" style="border-collapse: collapse; width: 100%;">
    <thead>
      <tr>
        <th style="padding: 8px;">Script Name</th>
        <th style="padding: 8px;">Last Update</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>Broadcast-ADUser-LogonMessage-viaGPO.hta</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Broadcast-ADUser-LogonMessage-viaGPO.ps1</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Cleanup-WebBrowsers-Tool.ps1</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Clear-and-ReSyncGPOs-ADComputers.ps1</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Copy-and-Sync-Folder-to-ADComputers-viaGPO.ps1</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Deploy-FortiClientVPN-viaGPO.ps1</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Deploy-FusionInventoryAgent-viaGPO.ps1</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Deploy-GLPIAgent-viaGPO.ps1</strong></td>
        <td>13 minutes ago</td>
      </tr>
      <tr>
        <td><strong>Deploy-KasperskyAV-viaGPO.ps1</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Deploy-PowerShell-viaGPO.ps1</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Deploy-ZoomWorkplace-viaGPO.ps1</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Enhance-BGInfoDisplay-viaGPO.bgi</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Enhance-BGInfoDisplay-viaGPO.ps1</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Install-KMSLicensingServer-Tool.ps1</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Install-RDSLicensingServer-Tool.ps1</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>README.md</strong></td>
        <td>Now</td>
      </tr>
      <tr>
        <td><strong>Remove-SharedFolders-and-Drives-viaGPO.ps1</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Remove-Softwares-NonCompliance-Tool.ps1</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Remove-Softwares-NonCompliance-Tool.txt</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Remove-Softwares-NonCompliance-viaGPO.ps1</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Rename-DiskVolumes-viaGPO.ps1</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Reset-and-Sync-DomainGPOs-viaGPO.ps1</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Retrieve-LocalMachine-InstalledSoftwareList.ps1</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Uninstall-SelectedApp-Tool.ps1</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Update-ADComputer-Winget-Explicit.ps1</strong></td>
        <td>3 months ago</td>
      </tr>
      <tr>
        <td><strong>Update-ADComputer-Winget-viaGPO.ps1</strong></td>
        <td>3 months ago</td>
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

  <h2>💡 Tips for Optimization</h2>
  <ul>
    <li><strong>Automate Execution:</strong> Schedule scripts to run periodically using Task Scheduler.</li>
    <li><strong>Centralize Logs and Reports:</strong> Store <code>.log</code> and <code>.csv</code> files in a shared repository for collaboration and analysis.</li>
    <li><strong>Customize Scripts:</strong> Adjust parameters to meet organizational needs.</li>
  </ul>
</div>
