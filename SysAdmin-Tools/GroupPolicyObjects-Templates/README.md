<div>
  <h1>⚙️ GroupPolicyObjects-Templates Folder</h1>

  <h2>📄 Overview</h2>
  <p>
    This folder contains a curated collection of <strong>Group Policy Object (GPO) templates</strong> designed to streamline and standardize the configuration of <strong>Windows Server Forest and Domain</strong> structures. These templates address a broad range of use cases, enhancing <strong>security</strong>, <strong>productivity</strong>, and <strong>compliance</strong> within your IT infrastructure.
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
      <ul>
        <li>Ensure a functional <strong>Windows Server Domain Controller (DC)</strong> or <strong>Forest Server</strong>, configured as a <strong>Global Catalog Server</strong>.</li>
      </ul>
    </li>
    <li>
      <strong>Importing Templates:</strong>
      <ul>
        <li>Execute the script located at:</li>
        <li><code>SysAdmin-Tools/ActiveDirectory-Management/Export-n-Import-GPOsTool.ps1</code>.</li>
        <li>This script includes options for importing GPO templates into your server environment.</li>
      </ul>
    </li>
    <li>
      <strong>Log File Generation:</strong>
      <ul>
        <li>A log file is generated at:</li>
        <li><code>C:\Logs-TEMP\</code></li>
        <li>Review the log file to verify the import process and resolve any issues.</li>
      </ul>
    </li>
    <li>
      <strong>Deployment Location:</strong>
      <ul>
        <li>Once imported, all templates and associated scripts will be accessible at:</li>
        <li><code>\\your-forest-domain\SYSVOL\your-domain\Policies\</code></li>
        <li>This ensures the templates are available for deployment across the domain.</li>
      </ul>
    </li>
  </ol>

  <hr />

  <h2>📜 Template List and Descriptions</h2>
  <table border="1" style="border-collapse: collapse; width: 100%;">
    <thead>
      <tr>
        <th style="padding: 8px; text-align: left;">Template Name</th>
        <th style="padding: 8px; text-align: left;">Description</th>
      </tr>
    </thead>
    <tbody>
      <!-- Template List -->
      <tr><td>admin-entire-Forest-LEVEL3</td><td>Grants elevated administrative privileges across the AD Forest for restricted groups with ITSM Level 3 profiles.</td></tr>
      <tr><td>admin-local-Workstations-LEVEL1-2</td><td>Assigns local administrative rights to IT team members with ITSM Level 1 and Level 2 profiles for workstation support.</td></tr>
      <tr><td>deploy-printer-template</td><td>Automates printer deployment across specified Organizational Units (OUs).</td></tr>
      <tr><td>disable-firewall-domain-workstations</td><td>Disables the Windows Firewall on domain-joined workstations in antivirus-managed environments.</td></tr>
      <tr><td>enable-audit-logs-DC-servers</td><td>Enables auditing logs on domain controllers for enhanced security monitoring.</td></tr>
      <tr><td>enable-audit-logs-FILE-servers</td><td>Configures file server auditing logs to track access and modifications.</td></tr>
      <tr><td>enable-biometrics-logon</td><td>Activates biometric authentication methods, such as tokens, fingerprint readers, and image recognition.</td></tr>
      <tr><td>enable-ldap-bind-servers</td><td>Configures secure LDAP binding to improve directory security.</td></tr>
      <tr><td>enable-licensing-RDS</td><td>Configures licensing for Remote Desktop Services (RDS) across the domain.</td></tr>
      <tr><td>enable-logon-message-workstations</td><td>Displays custom logon messages on workstations. Associated script: <code>Broadcast-ADUser-LogonMessage-viaGPO.ps1</code>.</td></tr>
      <tr><td>enable-network-discovery</td><td>Activates network discovery for better connectivity within the domain.</td></tr>
      <tr><td>enable-RDP-configs-users-RPC-gpos</td><td>Configures Remote Desktop Protocol (RDP) settings for specified users.</td></tr>
      <tr><td>enable-WDS-ports</td><td>Opens necessary ports for Windows Deployment Services (WDS).</td></tr>
      <tr><td>enable-WinRM-service</td><td>Activates Windows Remote Management (WinRM) for remote administration.</td></tr>
      <tr><td>enable-zabbix-ports-servers</td><td>Opens ports required for Zabbix server monitoring.</td></tr>
      <tr><td>install-certificates-forest</td><td>Deploys certificates across the AD Forest. Ensure certificates are installed in the GPO configuration.</td></tr>
      <tr><td>install-cmdb-fusioninventory-agent</td><td>Automates the installation of FusionInventory Agent for asset management.</td></tr>
      <tr><td>install-forticlient-vpn</td><td>Deploys FortiClient VPN software.</td></tr>
      <tr><td>install-kasperskyfull-workstations</td><td>Installs Kaspersky antivirus software.</td></tr>
      <tr><td>install-powershell7</td><td>Automates the installation of PowerShell 7.</td></tr>
      <tr><td>install-update-winget-apps</td><td>Updates applications using Winget.</td></tr>
      <tr><td>install-zoom-workplace-32bits</td><td>Deploys the 32-bit version of Zoom software.</td></tr>
      <tr><td>itsm-disable-monitor-after-06hours</td><td>Disables monitors after six hours of inactivity to save energy.</td></tr>
      <tr><td>itsm-template-ALL-servers</td><td>Standardized template for server configuration.</td></tr>
      <tr><td>itsm-template-ALL-workstations</td><td>Standardized template for workstation configuration.</td></tr>
      <tr><td>itsm-VMs-dont-shutdown</td><td>Prevents virtual machines from shutting down automatically.</td></tr>
      <tr><td>mapping-storage-template</td><td>Configures enterprise shared folder mappings for storage management.</td></tr>
      <tr><td>password-policy-all-domain-users</td><td>Enforces robust password policies for domain users.</td></tr>
      <tr><td>password-policy-all-servers-machines</td><td>Implements strict password policies for server accounts.</td></tr>
      <tr><td>password-policy-only-IT-TEAM-users</td><td>Applies stricter password policies for IT team members.</td></tr>
      <tr><td>purge-expired-certificates</td><td>Removes expired certificates from servers and workstations.</td></tr>
      <tr><td>remove-shared-local-folders-workstations</td><td>Deletes unauthorized shared folders.</td></tr>
      <tr><td>remove-softwares-non-compliance</td><td>Uninstalls non-compliant software.</td></tr>
      <tr><td>rename-disks-volumes-workstations</td><td>Standardizes disk volume names for better management.</td></tr>
      <tr><td>wsus-update-servers-template</td><td>Configures WSUS updates for servers.</td></tr>
      <tr><td>wsus-update-workstation-template</td><td>Configures WSUS updates for workstations.</td></tr>
    </tbody>
  </table>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ul>
    <li><strong>Active Directory Environment:</strong> A functioning AD Forest and Domain structure.</li>
    <li><strong>PowerShell 5.1 or Later:</strong> Required for executing scripts. Verify with:</li>
    <pre><code>$PSVersionTable.PSVersion</code></pre>
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
