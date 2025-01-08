<div>
  <h1>🖥️ Efficient Server Management and ITSM Compliance on Windows Server Environments</h1>

  <h2>📄 Description</h2>
  <p>
    The <strong>ITSM-Templates-SVR</strong> repository is a comprehensive collection of PowerShell and VBScript tools designed for 
    IT Service Management (ITSM) in Windows Server environments. These tools enable IT administrators to automate server configurations, 
    enhance operational efficiency, and maintain compliance with organizational policies.
  </p>
  <ul>
    <li><strong>Server-Specific Configurations:</strong> Streamlined ITSM implementation.</li>
    <li><strong>Automated Processes:</strong> Domain services, roles, and server hardening.</li>
    <li><strong>Detailed Logs and Reports:</strong> Track and audit execution outcomes.</li>
  </ul>

  <hr />

  <h2>📄 Overview</h2>
  <p>The <strong>Check-List for Applying ITSM-Templates-SVR</strong> standardizes configurations for servers, improving compliance, security, and operational efficiency.</p>

  <h3>Objectives:</h3>
  <ul>
    <li>Maintain high server availability and reliability.</li>
    <li>Automate critical server-side ITSM tasks.</li>
    <li>Ensure compliance with security and governance policies.</li>
  </ul>

  <hr />

  <h2>📋 Steps to Use ITSM-Templates-SVR Scripts</h2>
  <ol>
    <li>
      <strong>Clone the Repository:</strong>
      <p>Clone the <code>ITSM-Templates-SVR</code> folder to your organization’s <strong>Definitive Media Library (DML)</strong> for centralized access and secure storage.</p>
    </li>
    <li>
      <strong>Deploy Locally to Servers:</strong>
      <p>
        Copy the <code>ITSM-Templates-SVR</code> folder from the DML to the <code>C:\</code> drive of each server to enable local execution.
        Running scripts locally reduces dependency on network connectivity and ensures smooth operation.
      </p>
    </li>
    <li>
      <strong>Maintain an Updated DML:</strong>
      <p>Keep the DML repository up-to-date with the latest ITSM-Templates-SVR scripts to align server configurations with current standards.</p>
    </li>
    <li>
      <strong>Configure Using Administrator Accounts:</strong>
      <p>Use the server’s local administrator account or a domain admin account for configurations, ensuring security and consistency.</p>
    </li>
    <li>
      <strong>Follow the Checklist:</strong>
      <p>Refer to the <code>Check-List for Applying ITSM-Templates on Windows Server Environments.pdf</code> for detailed guidance.</p>
    </li>
    <li>
      <strong>Customize Scripts:</strong>
      <p>Modify PowerShell and VBScript tools to fit your organization's specific server management requirements.</p>
    </li>
  </ol>

  <hr />

  <h2>📂 ITSM-Templates-SVR Folder Structure and Scripts</h2>

  <h3>Folder Descriptions:</h3>
  <ul>
    <li><strong>Certificates:</strong> Contains SSL/TLS and root certificates for secure server communication.</li>
    <li><strong>ConfigurationScripts:</strong> Scripts for configuring server roles and features.</li>
    <li><strong>MainDocs:</strong> Editable documentation, including the server configuration checklist.</li>
    <li><strong>ModifyReg:</strong> Registry modification scripts for initial server setup and hardening.</li>
    <li><strong>PostIngress:</strong> Scripts executed after a server joins a domain, finalizing configurations.</li>
    <li><strong>ScriptsAdditionalSupport:</strong> Tools for troubleshooting and resolving server configuration issues.</li>
  </ul>

  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;">Script Name</th>
        <th style="padding: 8px;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td>ITSM-DefaultServerConfig.ps1</td>
        <td>Applies essential configurations for server setup, including DNS settings, hardening roles, and administrative shares setup.</td>
      </tr>
      <tr>
        <td>ITSM-ModifyServerRegistry.ps1</td>
        <td>Modifies registry settings to enforce security and compliance, including disabling SMBv1 and configuring Windows Updates.</td>
      </tr>
      <tr>
        <td>ITSM-DNSRegistration.ps1</td>
        <td>Ensures proper DNS registration for Active Directory integration.</td>
      </tr>
      <tr>
        <td>ITSM-HardenServer.ps1</td>
        <td>Applies security hardening configurations after the server joins the domain.</td>
      </tr>
      <tr>
        <td>CheckServerRoles.ps1</td>
        <td>Lists all installed roles and features on the server.</td>
      </tr>
      <tr>
        <td>ExportServerConfig.ps1</td>
        <td>Exports the server’s configuration to a <code>.csv</code> file for documentation.</td>
      </tr>
      <tr>
        <td>FixNTFSPermissions.ps1</td>
        <td>Corrects NTFS permission inconsistencies.</td>
      </tr>
      <tr>
        <td>InventoryServerSoftware.ps1</td>
        <td>Creates an inventory of installed software on the server.</td>
      </tr>
      <tr>
        <td>ResetGPOSettings.ps1</td>
        <td>Resets GPO-related configurations to default values.</td>
      </tr>
      <tr>
        <td>ServerTimeSync.ps1</td>
        <td>Synchronizes server time with a domain time source.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Next Releases</h2>
  <ul>
    <li>Automated patch management tools.</li>
    <li>Enhanced reporting features for server compliance audits.</li>
    <li>Scripts for integrating cloud-based server services.</li>
  </ul>

  <hr />

  <h2>📝 Logging and Output</h2>
  <ul>
    <li><strong>Logs:</strong> All scripts generate <code>.log</code> files documenting execution steps and errors.</li>
    <li><strong>Reports:</strong> Scripts export data in <code>.csv</code> format for detailed analysis and compliance reporting.</li>
  </ul>

  <hr />

  <h2>📄 Log File Locations</h2>
  <p>Logs are stored in <code>C:\ITSM-Logs-SVR\</code> and include:</p>
  <ul>
    <li>DNS registration logs.</li>
    <li>Server role configuration logs.</li>
    <li>Domain join/removal logs.</li>
  </ul>

  <hr />

  <h2>🔗 References</h2>
  <p>
    <a href="https://github.com/brazilianscriptguy/PowerShell-codes-for-Windows-Server-Administrators" target="_blank">
      <img src="https://img.shields.io/badge/View%20Repository-GitHub-blue?style=flat-square&logo=github" alt="View Repository Badge">
    </a>
  </p>

  <hr />

  <h3>Document Classification</h3>
  <p>This document is <strong>RESTRICTED</strong> for internal use within the Company’s network.</p>
</div>
