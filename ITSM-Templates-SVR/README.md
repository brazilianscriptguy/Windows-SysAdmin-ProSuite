<div>
  <h1>🖥️ Efficient Server Management and ITSM Compliance on Windows Server Environments</h1>
  <p>
    Welcome to the <strong>ITSM-Templates-SVR</strong> repository! This collection includes essential 
    <code>PowerShell</code> and <code>VBScript tools</code> designed for IT Service Management (ITSM) in Windows Server environments. By automating server configurations, enhancing operational efficiency, and maintaining compliance, these tools provide a robust framework for managing Windows servers effectively.
  </p>

  <hr />

  <h2>🌟 Key Features</h2>
  <ul>
    <li><strong>Server-Specific Configurations:</strong> Streamlined ITSM implementation tailored to server needs.</li>
    <li><strong>Automated Processes:</strong> Automate domain services, role configurations, and server hardening.</li>
    <li><strong>Standardized Logs and Reports:</strong> Maintain traceable logs and generate actionable reports for auditing and compliance.</li>
    <li><strong>Reusable Templates:</strong> Quickly deploy and customize server configurations with modular scripts.</li>
  </ul>

  <hr />

  <h2>📄 Script Descriptions</h2>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;"><strong>Script Name</strong></th>
        <th style="padding: 8px;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>ITSM-DefaultServerConfig.ps1</strong></td>
        <td>Applies essential configurations for server setup, including DNS settings, role hardening, and administrative shares setup.</td>
      </tr>
      <tr>
        <td><strong>ITSM-ModifyServerRegistry.ps1</strong></td>
        <td>Modifies registry settings to enforce security and compliance standards, including disabling SMBv1 and configuring Windows Updates.</td>
      </tr>
      <tr>
        <td><strong>ITSM-DNSRegistration.ps1</strong></td>
        <td>Ensures proper DNS registration for seamless Active Directory integration.</td>
      </tr>
      <tr>
        <td><strong>ITSM-HardenServer.ps1</strong></td>
        <td>Applies security hardening configurations after domain join.</td>
      </tr>
      <tr>
        <td><strong>CheckServerRoles.ps1</strong></td>
        <td>Lists all installed roles and features on the server.</td>
      </tr>
      <tr>
        <td><strong>ExportServerConfig.ps1</strong></td>
        <td>Exports the server’s configuration to a <code>.csv</code> file for documentation and review.</td>
      </tr>
      <tr>
        <td><strong>FixNTFSPermissions.ps1</strong></td>
        <td>Corrects NTFS permission inconsistencies.</td>
      </tr>
      <tr>
        <td><strong>InventoryServerSoftware.ps1</strong></td>
        <td>Creates an inventory of installed software on the server.</td>
      </tr>
      <tr>
        <td><strong>ResetGPOSettings.ps1</strong></td>
        <td>Resets Group Policy Object (GPO)-related configurations to default values.</td>
      </tr>
      <tr>
        <td><strong>ServerTimeSync.ps1</strong></td>
        <td>Synchronizes server time with a domain time source.</td>
      </tr>
    </tbody>
  </table>

  <hr />

<h2>🚀 Getting Started</h2>
  <ol>
      <li>
      <strong>Clone or download the Main Repository:</strong>
      <pre><code>git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git</code></pre>
    </li>
    <li>
      <strong>Navigate to the Repository Folder:</strong>
      <p>Navigate to the <code>Windows-SysAdmin-ProSuite/ITSM-Templates-SVR/</code> directory that contains the desired scripts.</p>
    </li>
    <li>
      <strong>Review Documentation:</strong>
      <p>Open the <code>README.md</code> file in the chosen subfolder for detailed script descriptions and usage instructions.</p>
    </li>
    <li>
      <strong>Run the Script:</strong>
      <p>Execute the desired PowerShell script with the following command:</p>
      <pre><code>.\ScriptName.ps1</code></pre>
    </li>
    <li>
      <strong>Verify Logs and Reports:</strong>
      <p>Check the generated <code>.log</code> files for details on script execution and exported <code>.csv</code> files for results.</p>
    </li>
  </ol>

  <hr />

  <h2>📝 Logging and Reporting</h2>
  <ul>
    <li><strong>Logs:</strong> All scripts generate <code>.log</code> files that document executed actions and errors encountered.</li>
    <li><strong>Reports:</strong> Scripts export data in <code>.csv</code> format for analysis and compliance audits.</li>
  </ul>

  <hr />

  <h2>💡 Tips for Optimization</h2>
  <ul>
    <li><strong>Automate Execution:</strong> Schedule scripts to run periodically using task schedulers to ensure consistent results.</li>
    <li><strong>Centralize Logs and Reports:</strong> Save generated <code>.log</code> and <code>.csv</code> files in shared directories for collaborative analysis and auditing.</li>
    <li><strong>Customize Templates:</strong> Tailor script templates to fit specific organizational workflows and security requirements.</li>
  </ul>

  <hr />

  <p>Explore the <strong>ITSM-Templates-SVR</strong> repository and streamline your server management processes. With these tools, achieving ITSM compliance and operational efficiency has never been easier! 🎉</p>

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

  <h2>❓ Additional Assistance</h2>
  <p>
    These scripts are fully customizable to fit your unique requirements. For more information on setup or assistance with specific tools, refer to the included <code>README.md</code> or the detailed documentation available in each subfolder.
  </p>

  <div align="center">
    <a href="mailto:luizhamilton.lhr@gmail.com" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail" alt="Email Badge">
    </a>
    <a href="https://www.patreon.com/brazilianscriptguy" target="_blank" rel="noopener noreferrer">
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

  <hr />
  <h3>Document Classification</h3>
  <p>This document is <strong>RESTRICTED</strong> for internal use within the Company’s network.</p>
</div>
