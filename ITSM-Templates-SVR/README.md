<div>
  <h1>🖥️ ITSM-Templates-SVR Suite — Windows Server Management & Compliance</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>ITSM-Templates-SVR</strong> folder contains a suite of <strong>PowerShell</strong> and <strong>VBScript</strong> tools tailored to 
    Windows Server ITSM operations. These scripts help automate server provisioning, enforce IT compliance, and streamline daily administrative tasks across enterprise server environments.
  </p>

  <ul>
    <li><strong>🔧 Server Hardening & Setup:</strong> Automate secure baseline configurations and domain-ready deployments.</li>
    <li><strong>⚙️ Registry & DNS Fixes:</strong> Improve reliability by correcting registry values and enforcing dynamic DNS registration.</li>
    <li><strong>📊 Logging & Reports:</strong> Scripts generate <code>.log</code> files and export <code>.csv</code> reports for auditing.</li>
    <li><strong>📦 Reusable Templates:</strong> Easily adapt scripts for new roles, GPO resets, time sync, and role inventories.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell Version:</strong> PowerShell 5.1 or later recommended.<br>
      <pre><code>$PSVersionTable.PSVersion</code></pre>
    </li>
    <li>
      <strong>🔑 Administrator Privileges:</strong> Required to run scripts that affect system services or domain bindings.</li>
    <li>
      <strong>🖥️ RSAT Tools:</strong> Remote Server Administration Tools must be installed to manage roles.<br>
      <pre><code>Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online</code></pre>
    </li>
    <li>
      <strong>🔧 Execution Policy:</strong> Enable script execution for the current process:<br>
      <pre><code>Set-ExecutionPolicy RemoteSigned -Scope Process</code></pre>
    </li>
    <li>
      <strong>📦 Dependencies:</strong> Confirm that modules such as <code>ActiveDirectory</code> and <code>DHCPServer</code> are present if referenced.</li>
  </ol>

  <hr />

  <h2>📄 Script Descriptions (Alphabetical Order)</h2>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;"><strong>Script Name</strong></th>
        <th style="padding: 8px;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr><td><strong>CheckServerRoles.ps1</strong></td><td>Lists installed roles and features to validate the server's intended purpose and role scope.</td></tr>
      <tr><td><strong>ExportServerConfig.ps1</strong></td><td>Exports server configuration into a <code>.csv</code> file for documentation and review.</td></tr>
      <tr><td><strong>FixNTFSPermissions.ps1</strong></td><td>Corrects inconsistencies in NTFS file system permissions across critical paths.</td></tr>
      <tr><td><strong>InventoryServerSoftware.ps1</strong></td><td>Compiles a list of installed software to help maintain an accurate software asset inventory.</td></tr>
      <tr><td><strong>ITSM-DefaultServerConfig.ps1</strong></td><td>Applies standard server configurations such as disabling guest shares, configuring NTP, and adjusting firewall rules.</td></tr>
      <tr><td><strong>ITSM-DNSRegistration.ps1</strong></td><td>Enforces DNS re-registration for proper AD communication and name resolution.</td></tr>
      <tr><td><strong>ITSM-HardenServer.ps1</strong></td><td>Applies domain-aware hardening post-join: disables SMBv1, disables local accounts, and enforces lockout policies.</td></tr>
      <tr><td><strong>ITSM-ModifyServerRegistry.ps1</strong></td><td>Updates registry keys related to security compliance: SMB, Remote UAC, and Windows Update behavior.</td></tr>
      <tr><td><strong>ResetGPOSettings.ps1</strong></td><td>Resets all GPO-controlled configurations on the server to a default (clean) state.</td></tr>
      <tr><td><strong>ServerTimeSync.ps1</strong></td><td>Synchronizes the server clock with domain time sources to prevent replication and authentication issues.</td></tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Getting Started</h2>
  <ol>
    <li><strong>Clone the Repository:</strong><br>
      <pre><code>git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git</code></pre>
    </li>
    <li><strong>Navigate to:</strong> <code>Windows-SysAdmin-ProSuite/ITSM-Templates-SVR/</code></li>
    <li><strong>Read the Docs:</strong> Review each script's internal comments or <code>README.md</code> for usage instructions.</li>
    <li><strong>Execute:</strong><br>
      <pre><code>.\ScriptName.ps1</code></pre>
    </li>
    <li><strong>Review Logs and Reports:</strong> Analyze <code>.log</code> and <code>.csv</code> files output by the scripts.</li>
  </ol>

  <hr />

  <h2>📝 Logging and Output</h2>
  <ul>
    <li><strong>📄 Logs:</strong> Scripts generate <code>.log</code> files in structured folders for troubleshooting and history tracking.</li>
    <li><strong>📊 Reports:</strong> Configuration and inventory outputs are exported to <code>.csv</code> format.</li>
  </ul>

  <hr />

  <h2>💡 Optimization Tips</h2>
  <ul>
    <li><strong>Automate with Task Scheduler:</strong> Schedule periodic execution for drift remediation.</li>
    <li><strong>Centralize Output:</strong> Direct logs and reports to a shared folder for audit trails.</li>
    <li><strong>Customize Templates:</strong> Adjust configurations per role (e.g., file server vs. DC) for environment-specific compliance.</li>
  </ul>

  <hr />

  <h2>❓ Additional Assistance</h2>
  <p style="text-align: justify; font-size: 16px; line-height: 1.6;">
    These scripts are highly adaptable to fit your infrastructure. Review embedded comments or the related documentation within 
    each script's header to understand variables, dependencies, and specific behaviors.
  </p>

  <div align="center" style="margin-top: 20px;">
    <a href="mailto:luizhamilton.lhr@gmail.com" target="_blank">
      <img src="https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail" alt="Email Badge">
    </a>
    <a href="https://patreon.com/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/Support-Patreon-red?style=for-the-badge&logo=patreon" alt="Patreon Badge">
    </a>
    <a href="https://buymeacoffee.com/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge&logo=buymeacoffee" alt="Buy Me Coffee">
    </a>
    <a href="https://ko-fi.com/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/Ko--fi-Support-blue?style=for-the-badge&logo=kofi" alt="Ko-fi Badge">
    </a>
    <a href="https://gofund.me/4599d3e6" target="_blank">
      <img src="https://img.shields.io/badge/GoFundMe-Donate-green?style=for-the-badge&logo=gofundme" alt="GoFundMe Badge">
    </a>
    <a href="https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c" target="_blank">
      <img src="https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp" alt="WhatsApp Badge">
    </a>
    <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/issues" target="_blank">
      <img src="https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github" alt="GitHub Issues Badge">
    </a>
  </div>

  <hr />
  <h3>📂 Document Classification</h3>
  <p><strong>RESTRICTED:</strong> For internal use within the organization's network only.</p>
</div>
