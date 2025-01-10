<div>
  <h1>🖥️ Efficient Workstation Management, Configuration, and ITSM Compliance on Windows 10 and 11</h1>

  <h2>📄 Description</h2>
  <p>
    This repository contains a curated collection of VBScript and PowerShell tools specifically designed to streamline the management and 
    configuration of Windows 10 and 11 workstations within an IT Service Management (ITSM) framework. These tools automate essential 
    administrative tasks, enabling IT professionals to enhance workflows, ensure consistency, and maintain compliance across the organization.
  </p>
  <ul>
    <li><strong>Graphical User Interfaces (GUI):</strong> For user-friendly operation.</li>
    <li><strong>Comprehensive <code>.log</code> Files:</strong> For transparent process tracking.</li>
    <li><strong>Export to <code>.csv</code>:</strong> For streamlined reporting and auditing.</li>
  </ul>

  <hr />

  <h2>📂 ITSM-Templates-WKS Folder Structure and Scripts</h2>

  <h3>Folder: <code>/Folder UniqueScripts/</code></h3>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;"><strong>Script Name</strong></th>
        <th style="padding: 8px;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>ITSM-DefaultVBSing.vbs</strong></td>
        <td>Automates ten (10) key configurations to standardize workstation settings and prepare the environment for domain integration.</td>
      </tr>
      <tr>
        <td><strong>ITSM-ModifyREGing.vbs</strong></td>
        <td>Applies ten (10) registry modifications to align workstation configuration with organizational standards.</td>
      </tr>
    </tbody>
  </table>

  <h3>Folder: <code>/Folder PostIngress/</code></h3>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;"><strong>Script Name</strong></th>
        <th style="padding: 8px;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>ITSM-NewDNSRegistering.vbs</strong></td>
        <td>Updates the workstation’s hostname and domain details in Active Directory DNS servers for accurate registration.</td>
      </tr>
      <tr>
        <td><strong>ITSM-ProfileImprinting.vbs</strong></td>
        <td>Registers user domain profiles after three login cycles to ensure adherence to organizational policies.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>📝 Logging and Output</h2>
  <ul>
    <li><strong>Logging:</strong> Scripts generate <code>.log</code> files documenting execution processes and errors.</li>
    <li><strong>Export Functionality:</strong> Results are exported in <code>.csv</code> format for audits and reporting.</li>
  </ul>

  <hr />

  <h2>📄 Log File Locations</h2>
  <p>Logs are stored in <code>C:\ITSM-Logs-WKS\</code> and include:</p>
  <ul>
    <li>DNS registration logs.</li>
    <li>User profile imprinting logs.</li>
  </ul>

  <hr />

  <h2>❓ Additional Assistance</h2>
  <p>
    These scripts are fully customizable to fit your unique requirements. For more information on setup or assistance with specific tools, refer to the included <code>README.md</code> or the detailed documentation available in each subfolder.
  </p>

  <div align="center">
    <a href="mailto:luizhamilton.lhr@gmail.com" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail" alt="Email Badge">
    </a>
    <a href="https://www.patreon.com/c/brazilianscriptguy" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge&logo=patreon" alt="Support on Patreon Badge">
    </a>
    <a href="https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp" alt="WhatsApp Badge">
    </a>
    <a href="https://github.com/brazilianscriptguy/BlueTeam-Tools/issues" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github" alt="GitHub Issues Badge">
    </a>
  </div>

  <h3>Document Classification</h3>
  <p>This document is <strong>RESTRICTED</strong> for internal use within the Company’s network.</p>
</div>
