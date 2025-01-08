<div>
  <h1>⚙️ System Configuration and Deployment Tools</h1>

  <h2>📄 Overview</h2>
  <p>
    This folder includes a collection of PowerShell scripts for deploying and configuring software, group policies, and system settings, ensuring consistent and efficient management of workstations and servers in Active Directory (AD) environments.
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
        <td>Broadcast-ADUser-LogonMessage-viaGPO.ps1</td>
        <td>
          Displays customizable logon messages to users via Group Policy Object (GPO), facilitating communication across managed environments.
          <br /><strong>Complementary File:</strong>
          <ul>
            <li>Broadcast-ADUser-LogonMessage-viaGPO.hta: A GUI file for configuring and previewing the logon messages.</li>
          </ul>
        </td>
      </tr>
      <tr>
        <td>Cleanup-WebBrowsers-Tool.ps1</td>
        <td>
          Thoroughly removes cookies, cache, session data, history, and other residual files from web browsers (e.g., Firefox, Chrome, Edge) and WhatsApp, improving system performance and privacy.
        </td>
      </tr>
      <tr>
        <td>Clear-and-ReSyncGPOs-ADComputers.ps1</td>
        <td>
          Resets and re-synchronizes Group Policy Objects (GPOs) across domain computers to ensure consistent policy application.
        </td>
      </tr>
      <tr>
        <td>Copy-and-Sync-Folder-to-ADComputers-viaGPO.ps1</td>
        <td>
          Synchronizes folders from a network location to AD computers, ensuring only updated files are copied while outdated files are removed. Full logging is included for traceability.
        </td>
      </tr>
      <tr>
        <td>Deploy-FortiClientVPN-viaGPO.ps1</td>
        <td>
          Automates the deployment of FortiClient VPN software via GPO to support secure remote access. Handles version checks, uninstalling outdated versions, and configuring VPN tunnels.
        </td>
      </tr>
      <tr>
        <td>Deploy-FusionInventoryAgent-viaGPO.ps1</td>
        <td>
          Deploys the FusionInventory Agent to workstations for seamless inventory management and reporting.
        </td>
      </tr>
      <tr>
        <td>Deploy-KasperskyAV-viaGPO.ps1</td>
        <td>
          Automates the installation and configuration of Kaspersky Endpoint Security (KES) and Network Agent on domain workstations using GPO. Includes MSI validation and version management.
        </td>
      </tr>
      <tr>
        <td>Deploy-PowerShell-viaGPO.ps1</td>
        <td>
          Simplifies the deployment of PowerShell to workstations and servers via GPO. Ensures proper version checks, uninstalls older versions, and installs updates as needed.
        </td>
      </tr>
      <tr>
        <td>Deploy-ZoomWorkplace-viaGPO.ps1</td>
        <td>
          Automates the deployment of Zoom software on workstations via GPO for streamlined collaboration.
        </td>
      </tr>
      <tr>
        <td>Enhance-BGInfoDisplay-viaGPO.ps1</td>
        <td>
          Integrates BGInfo with GPO to display critical system information on desktops.
          <br /><strong>Complementary File:</strong>
          <ul>
            <li>Enhance-BGInfoDisplay-viaGPO.bgi: Configuration file for customizing BGInfo desktop displays.</li>
          </ul>
        </td>
      </tr>
      <tr>
        <td>Install-KMSLicensingServer-Tool.ps1</td>
        <td>
          Installs and configures a Key Management Service (KMS) Licensing Server in an AD forest. Includes a GUI for ease of use and standardized logging.
        </td>
      </tr>
      <tr>
        <td>Install-RDSLicensingServer-Tool.ps1</td>
        <td>
          Configures a Remote Desktop Services (RDS) Licensing Server to manage client access licenses (CALs). Includes error handling and detailed logs for compliance.
        </td>
      </tr>
      <tr>
        <td>Rename-DiskVolumes-viaGPO.ps1</td>
        <td>
          Renames disk volumes uniformly across workstations using GPO, improving consistency in disk management.
        </td>
      </tr>
      <tr>
        <td>Reset-and-Sync-DomainGPOs-viaGPO.ps1</td>
        <td>
          Resets and re-synchronizes domain GPOs to maintain compliance and uniform policy application across workstations.
        </td>
      </tr>
      <tr>
        <td>Retrieve-LocalMachine-InstalledSoftwareList.ps1</td>
        <td>
          Audits installed software across Active Directory computers, generating detailed reports to verify compliance with software policies.
        </td>
      </tr>
      <tr>
        <td>Remove-SharedFolders-and-Drives-viaGPO.ps1</td>
        <td>
          Removes unauthorized shared folders and drives using GPO, ensuring data-sharing compliance and mitigating data breach risks.
        </td>
      </tr>
      <tr>
        <td>Remove-Softwares-NonCompliance-Tool.ps1</td>
        <td>
          Uninstalls non-compliant or unauthorized software on workstations to ensure adherence to organizational policies.
          <br /><strong>Complementary File:</strong>
          <ul>
            <li>Remove-Softwares-NonCompliance-Tool.txt: A configuration file listing the software to be uninstalled.</li>
          </ul>
        </td>
      </tr>
      <tr>
        <td>Remove-Softwares-NonCompliance-viaGPO.ps1</td>
        <td>
          Enforces software compliance by removing unauthorized applications via GPO across domain machines.
        </td>
      </tr>
      <tr>
        <td>Uninstall-SelectedApp-Tool.ps1</td>
        <td>
          Provides a GUI for selecting and uninstalling unwanted applications, automating software removal with minimal manual intervention.
        </td>
      </tr>
      <tr>
        <td>Update-ADComputer-Winget-Explicit.ps1</td>
        <td>
          Updates software on workstations explicitly using the <code>winget</code> tool, ensuring that systems run the latest software versions.
        </td>
      </tr>
      <tr>
        <td>Update-ADComputer-Winget-viaGPO.ps1</td>
        <td>
          Automates software updates across workstations using <code>winget</code> with deployment managed via GPO.
        </td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🔍 How to Use</h2>
  <p>
    Each script includes detailed headers with usage instructions. Open the scripts in a PowerShell editor to review prerequisites, permissions, and execution steps. Use the complementary files as necessary to configure or enhance the script’s operation.
  </p>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <p>
    Before using the scripts, ensure the following prerequisites are met:
  </p>
  <ul>
    <li>
      <strong>PowerShell 5.1 or Later:</strong> Required for script execution. Verify your version with:
      <pre style="background: #f4f4f4; padding: 10px;">$PSVersionTable.PSVersion</pre>
    </li>
    <li>
      <strong>Administrative Privileges:</strong> Necessary for deploying software, managing GPOs, and accessing sensitive configurations.
    </li>
    <li>
      <strong>Dependencies:</strong> Ensure the required modules, such as <code>GroupPolicy</code>, are installed and available.
    </li>
  </ul>

  <hr />

  <h2>📄 Complementary Files Overview</h2>
  <ul>
    <li><strong>Broadcast-ADUser-LogonMessage-viaGPO.hta:</strong> A GUI-based tool for configuring and previewing logon messages for deployment via GPO.</li>
    <li><strong>Enhance-BGInfoDisplay-viaGPO.bgi:</strong> Customizable configuration file for enriching desktop displays with BGInfo.</li>
    <li><strong>Remove-Softwares-NonCompliance-Tool.txt:</strong> A plain text file listing unauthorized software to be uninstalled by the associated script.</li>
  </ul>

  <hr />
