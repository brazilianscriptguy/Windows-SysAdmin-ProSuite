<div>
  <h1>⚙️ GroupPolicyObjects-Templates</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>GroupPolicyObjects-Templates</strong> folder provides a robust collection of reusable 
    <strong>GPO templates</strong> designed to streamline administrative tasks across 
    <strong>Windows Server Forest and Domain</strong> environments. These templates focus on security, performance, 
    user experience, and compliance, offering out-of-the-box configurations for both workstation and server infrastructure.
  </p>

  <h3>Key Features:</h3>
  <ul>
    <li><strong>Preconfigured GPOs:</strong> Ready-to-import templates for typical enterprise scenarios.</li>
    <li><strong>Cross-Domain Compatibility:</strong> Applicable to both domain-level and forest-wide deployments.</li>
    <li><strong>Script-Driven Automation:</strong> Integrated with import/export tools and log generation.</li>
    <li><strong>Security and Compliance:</strong> Templates implement best practices for account policies, firewall, RDS, and more.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>🖥️ Domain or Forest Controller:</strong>
      <p>Ensure you have a properly configured Windows Server with Domain Controller or Global Catalog role.</p>
    </li>
    <li>
      <strong>📦 Import Script:</strong>
      <p>Use the following script to import/export GPOs:</p>
      <pre><code>SysAdmin-Tools\ActiveDirectory-Management\Export-n-Import-GPOsTool.ps1</code></pre>
    </li>
    <li>
      <strong>📂 Deployment Path:</strong>
      <p>Templates are deployed to:</p>
      <code>\\your-forest-domain\SYSVOL\your-domain\Policies\</code>
    </li>
    <li>
      <strong>📝 Log Output:</strong>
      <p>Logs are saved to:</p>
      <code>C:\Logs-TEMP\</code>
    </li>
  </ol>

  <hr />

  <h2>📄 Template Descriptions (Alphabetical Order)</h2>
  <table border="1" style="border-collapse: collapse; width: 100%;">
    <thead>
      <tr>
        <th style="padding: 8px;">Template Name</th>
        <th style="padding: 8px;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr><td>admin-entire-Forest-LEVEL3</td><td>Elevated GPO for Forest-level administrative access (ITSM Level 3).</td></tr>
      <tr><td>admin-local-Workstations-LEVEL1-2</td><td>Grants local admin rights for support staff (Level 1 and 2).</td></tr>
      <tr><td>deploy-printer-template</td><td>Deploys preconfigured printers to user workstations via GPO.</td></tr>
      <tr><td>disable-firewall-domain-workstations</td><td>Disables built-in Windows Firewall for managed domains using third-party security solutions.</td></tr>
      <tr><td>enable-audit-logs-DC-servers</td><td>Enables auditing on Domain Controllers for event tracking.</td></tr>
      <tr><td>enable-audit-logs-FILE-servers</td><td>Activates audit logs on file servers for data access visibility.</td></tr>
      <tr><td>enable-biometrics-logon</td><td>Enables fingerprint or facial recognition on supported endpoints.</td></tr>
      <tr><td>enable-ldap-bind-servers</td><td>Configures secure LDAP binding policies.</td></tr>
      <tr><td>enable-licensing-RDS</td><td>Sets up Remote Desktop licensing via Group Policy.</td></tr>
      <tr><td>enable-logon-message-workstations</td><td>Displays legal disclaimer or welcome messages at user logon.</td></tr>
      <tr><td>enable-network-discovery</td><td>Turns on Network Discovery for trusted internal networks.</td></tr>
      <tr><td>enable-RDP-configs-users-RPC-gpos</td><td>Applies RDP settings for specific users or OUs.</td></tr>
      <tr><td>enable-WDS-ports</td><td>Opens ports required for Windows Deployment Services.</td></tr>
      <tr><td>enable-WinRM-service</td><td>Enables WinRM for PowerShell remoting and remote management.</td></tr>
      <tr><td>enable-zabbix-ports-servers</td><td>Allows Zabbix monitoring communication on servers.</td></tr>
      <tr><td>install-certificates-forest</td><td>Deploys SSL or internal PKI certificates across all domain members.</td></tr>
      <tr><td>install-cmdb-fusioninventory-agent</td><td>Installs FusionInventory agents for asset tracking.</td></tr>
      <tr><td>install-forticlient-vpn</td><td>Distributes FortiClient VPN across eligible machines.</td></tr>
      <tr><td>install-kasperskyfull-workstations</td><td>Rolls out full Kaspersky installation to workstations.</td></tr>
      <tr><td>install-powershell7</td><td>Deploys PowerShell 7 runtime to client machines.</td></tr>
      <tr><td>install-update-winget-apps</td><td>Schedules software updates using Winget package manager.</td></tr>
      <tr><td>install-zoom-workplace-32bits</td><td>Installs 32-bit Zoom client for compatibility in legacy devices.</td></tr>
      <tr><td>itsm-disable-monitor-after-06hours</td><td>Applies energy-saving settings by turning off inactive displays.</td></tr>
      <tr><td>itsm-template-ALL-servers</td><td>Base policy template applied to all server-class machines.</td></tr>
      <tr><td>itsm-template-ALL-workstations</td><td>Standard configuration baseline for Windows workstations.</td></tr>
      <tr><td>itsm-VMs-dont-shutdown</td><td>Prevents unexpected shutdown on virtualized endpoints.</td></tr>
      <tr><td>mapping-storage-template</td><td>Applies mapped network drives for enterprise shares.</td></tr>
      <tr><td>password-policy-all-domain-users</td><td>Enforces secure password requirements domain-wide.</td></tr>
      <tr><td>password-policy-all-servers-machines</td><td>Applies stricter password rules to server accounts.</td></tr>
      <tr><td>password-policy-only-IT-TEAM-users</td><td>Sets custom password expiration and length for IT staff only.</td></tr>
      <tr><td>purge-expired-certificates</td><td>Automatically removes expired certs via scheduled task.</td></tr>
      <tr><td>remove-shared-local-folders-workstations</td><td>Removes unauthorized shared folders.</td></tr>
      <tr><td>remove-softwares-non-compliance</td><td>Uninstalls software flagged as non-compliant.</td></tr>
      <tr><td>rename-disks-volumes-workstations</td><td>Enforces naming standards on disk volumes (e.g., “OS”, “DATA”).</td></tr>
      <tr><td>wsus-update-servers-template</td><td>Sets WSUS update behavior for domain servers.</td></tr>
      <tr><td>wsus-update-workstation-template</td><td>Applies WSUS policies for workstation updates.</td></tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Run Import Tool:</strong> Launch <code>Export-n-Import-GPOsTool.ps1</code> with elevated PowerShell.</li>
    <li><strong>Select Mode:</strong> Choose <em>Import Templates</em> option in the tool interface.</li>
    <li><strong>Confirm Import:</strong> Review CLI or GUI feedback to verify success.</li>
    <li><strong>Validate Results:</strong> Inspect <code>C:\Logs-TEMP\</code> for log output and status codes.</li>
  </ol>

  <hr />

  <h2>📝 Logging and Reports</h2>
  <ul>
    <li><strong>📄 Logs:</strong> Saved in <code>.log</code> format under <code>C:\Logs-TEMP\</code>.</li>
    <li><strong>📊 Reports:</strong> Exported in <code>.csv</code> format for audits, imports, and results tracking.</li>
  </ul>

  <hr />

  <h2>💡 Optimization Tips</h2>
  <ul>
    <li><strong>Schedule Policy Reviews:</strong> Periodically validate applied GPOs across OUs.</li>
    <li><strong>Version Control:</strong> Maintain a Git-based backup of your exported GPOs.</li>
    <li><strong>Tag Critical GPOs:</strong> Use naming conventions like <code>[SEC]</code>, <code>[CORE]</code> or <code>[AUDIT]</code> to improve traceability.</li>
  </ul>
</div>
