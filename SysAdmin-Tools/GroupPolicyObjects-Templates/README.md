<div>
  <h1>⚙️ GroupPolicyObjects-Templates Folder</h1>

  <h2>📄 Overview</h2>
  <p>
    This folder contains a curated collection of <strong>Group Policy Object (GPO) templates</strong> designed to streamline and standardize the configuration of 
    <strong>Windows Server Forest and Domain</strong> structures. These templates address a broad range of use cases, enhancing 
    <strong>security</strong>, <strong>productivity</strong>, and <strong>compliance</strong> within your IT infrastructure.
  </p>

  <h3>Key Examples:</h3>
  <ul>
    <li><strong>Enable Logon Message for Workstations:</strong> Ensures users see critical logon messages using an <code>.HTA</code> file.</li>
    <li><strong>Disable Firewall for Domain Workstations:</strong> Optimizes workstation management by disabling the native Windows Firewall in scenarios requiring third-party antivirus firewalls.</li>
    <li><strong>Install CMDB FusionInventory Agent:</strong> Automates deployment of asset management tools, such as the FusionInventory Agent.</li>
    <li><strong>Password Policy for All Domain Users:</strong> Implements robust password policies to ensure compliance across domain-wide user accounts.</li>
  </ul>

  <hr />

  <h2>How to Import These GPO Templates into Your Domain or Forest Server</h2>
  <ol>
    <li>
      <strong>Prerequisites:</strong>
      <p>Ensure a functional <strong>Windows Server Domain Controller (DC)</strong> or <strong>Forest Server</strong>, configured as a <strong>Global Catalog Server</strong>.</p>
    </li>
    <li>
      <strong>Importing Templates:</strong>
      <p>Execute the script located at:</p>
      <p><code>SysAdmin-Tools/ActiveDirectory-Management/Export-n-Import-GPOsTool.ps1</code></p>
      <p>This script includes options for importing GPO templates into your server environment.</p>
    </li>
    <li>
      <strong>Log File Generation:</strong>
      <p>A log file is generated at:</p>
      <p><code>C:\Logs-TEMP\</code></p>
      <p>Review the log file to verify the import process and resolve any issues.</p>
    </li>
    <li>
      <strong>Deployment Location:</strong>
      <p>Once imported, all templates and associated scripts will be accessible at:</p>
      <p><code>\\your-forest-domain\SYSVOL\your-domain\Policies\</code></p>
      <p>This ensures the templates are available for deployment across the domain.</p>
    </li>
  </ol>

  <hr />

  <h2>📜 Template List and Descriptions</h2>
  <table border="1" style="border-collapse: collapse; width: 100%;">
    <thead>
      <tr>
        <th style="padding: 8px;">Template Name</th>
        <th style="padding: 8px;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td style="padding: 8px;">admin-entire-Forest-LEVEL3</td>
        <td style="padding: 8px;">Grants elevated administrative privileges across the AD Forest for restricted groups with ITSM Level 3 profiles.</td>
      </tr>
      <tr>
        <td style="padding: 8px;">admin-local-Workstations-LEVEL1-2</td>
        <td style="padding: 8px;">Assigns local administrative rights to IT team members with ITSM Level 1 and Level 2 profiles for workstation support.</td>
      </tr>
      <tr>
        <td style="padding: 8px;">deploy-printer-template</td>
        <td style="padding: 8px;">Automates printer deployment across specified Organizational Units (OUs).</td>
      </tr>
      <tr>
        <td style="padding: 8px;">disable-firewall-domain-workstations</td>
        <td style="padding: 8px;">Disables the Windows Firewall on domain-joined workstations in antivirus-managed environments.</td>
      </tr>
      <tr>
        <td style="padding: 8px;">enable-audit-logs-DC-servers</td>
        <td style="padding: 8px;">Enables auditing logs on domain controllers for enhanced security monitoring.</td>
      </tr>
      <tr>
        <td style="padding: 8px;">enable-audit-logs-FILE-servers</td>
        <td style="padding: 8px;">Configures file server auditing logs to track access and modifications.</td>
      </tr>
      <tr>
        <td style="padding: 8px;">enable-biometrics-logon</td>
        <td style="padding: 8px;">Activates biometric authentication methods, such as tokens, fingerprint readers, and image recognition.</td>
      </tr>
      <tr>
        <td style="padding: 8px;">enable-ldap-bind-servers</td>
        <td style="padding: 8px;">Configures secure LDAP binding to improve directory security.</td>
      </tr>
      <tr>
        <td style="padding: 8px;">enable-licensing-RDS</td>
        <td style="padding: 8px;">Configures licensing for Remote Desktop Services (RDS) across the domain.</td>
      </tr>
      <tr>
        <td style="padding: 8px;">enable-logon-message-workstations</td>
        <td style="padding: 8px;">
          Displays custom logon messages on workstations. Associated script:
          <code>SysAdmin-Tools/SystemConfiguration-and-Deployment/Broadcast-ADUser-LogonMessage-viaGPO.ps1</code>.
        </td>
      </tr>
      <tr>
        <td style="padding: 8px;">install-cmdb-fusioninventory-agent</td>
        <td style="padding: 8px;">
          Automates the installation of FusionInventory Agent for asset management. Associated script:
          <code>SysAdmin-Tools/SystemConfiguration-and-Deployment/Deploy-FusionInventoryAgent-viaGPO.ps1</code>.
        </td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ul>
    <li><strong>Active Directory Environment:</strong> A functioning AD Forest and Domain structure.</li>
    <li>
      <strong>PowerShell 5.1 or Later:</strong> Required for executing scripts. Verify with:
      <pre><code>$PSVersionTable.PSVersion</code></pre>
    </li>
    <li><strong>Administrator Privileges:</strong> Required for GPO management.</li>
    <li><strong>Required Modules:</strong> Ensure the <code>GroupPolicy</code> module is installed.</li>
  </ul>

  <hr />

  <h2>📄 Complementary Resources</h2>
  <ul>
    <li><strong>Documentation:</strong> Detailed comments in each template.</li>
    <li><strong>Feedback and Contributions:</strong> Submit issues or pull requests to improve the repository.</li>
  </ul>
</div>
