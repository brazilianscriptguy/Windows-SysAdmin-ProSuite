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

  <h2>📄 Overview</h2>
  <p>
    The <strong>Check-List for Applying ITSM-Templates-WKS</strong> defines a standardized approach to configuring workstations and printers, 
    promoting compliance, operational efficiency, and secure deployment.
  </p>
  <h3>Objectives:</h3>
  <ul>
    <li>Enhance service quality and user satisfaction.</li>
    <li>Strengthen IT governance and risk management.</li>
    <li>Ensure operational efficiency and continuity.</li>
  </ul>

  <hr />

  <h2>📋 Steps to Use ITSM-Templates-WKS Scripts</h2>
  <ol>
    <li>
      <strong>Clone the Repository:</strong>
      <p>
        Clone the <code>ITSM-Templates-WKS</code> folder to your network’s <strong>Definitive Media Library (DML)</strong>. 
        This ensures centralized storage and easy accessibility for deployment across the organization.
      </p>
    </li>
    <li>
      <strong>Deploy Locally to Workstations:</strong>
      <p>
        Copy the <code>ITSM-Templates-WKS</code> folder from the DML to the <code>C:\</code> drive of each workstation requiring configuration. 
        Running scripts locally ensures efficient execution and reduces dependency on network connectivity.
      </p>
    </li>
    <li>
      <strong>Maintain an Updated DML:</strong>
      <p>Regularly update the DML repository with the latest version of the ITSM-Templates-WKS folder to align with organizational standards.</p>
    </li>
    <li>
      <strong>Standardize Local Administrative Privileges:</strong>
      <p>
        Limit each workstation to <strong>one local administrative account</strong> with elevated privileges. 
        Perform all configurations and management tasks using this designated account to ensure consistency and reduce security risks.
      </p>
    </li>
    <li>
      <strong>Follow the Checklist:</strong>
      <p>
        Refer to the <code>Check-List for Applying ITSM-Templates on Windows 10 and 11 Workstations.pdf</code> for detailed, 
        step-by-step guidance.
      </p>
    </li>
    <li>
      <strong>Customize Scripts:</strong>
      <p>Adjust <code>.vbs</code> and <code>.reg</code> scripts to suit specific organizational requirements.</p>
    </li>
    <li>
      <strong>Personalize Workstation Appearance:</strong>
      <p>
        Use files in the <code>C:\ITSM-Templates-WKS\CustomImages\</code> folder to customize wallpapers and user profiles. 
        Update themes and layouts using the <code>C:\ITSM-Templates-WKS\ModifyReg\UserDesktopTheme\</code> folder.
      </p>
    </li>
  </ol>

  <hr />

  <h2>📂 ITSM-Templates-WKS Folder Structure and Scripts</h2>

  <h3>Folder Descriptions:</h3>
  <ul>
    <li><strong>Certificates:</strong> Trusted root certificates for secure network communication.</li>
    <li><strong>CustomImages:</strong> Default wallpapers and user profile images.</li>
    <li><strong>MainDocs:</strong> Editable documentation, including the configuration checklist.</li>
    <li><strong>ModifyReg:</strong> Registry configuration scripts for initial setup.</li>
    <li><strong>PostIngress:</strong> Scripts executed after domain joining to finalize configurations.</li>
    <li><strong>ScriptsAdditionalSupport:</strong> Tools for troubleshooting and resolving workstation configuration issues.</li>
    <li><strong>UniqueScripts:</strong> Comprehensive scripts for registry and VBScript configurations.</li>
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
        <td>ITSM-DefaultVBSing.vbs</td>
        <td>Automates ten (10) key configurations to standardize workstation settings and prepare the environment for domain integration.</td>
      </tr>
      <tr>
        <td>ITSM-ModifyREGing.vbs</td>
        <td>Applies ten (10) registry modifications to align workstation configuration with organizational standards.</td>
      </tr>
      <tr>
        <td>ITSM-NewDNSRegistering.vbs</td>
        <td>Updates the workstation’s hostname and domain details in Active Directory DNS servers for accurate registration.</td>
      </tr>
      <tr>
        <td>ITSM-ProfileImprinting.vbs</td>
        <td>Registers user domain profiles after three login cycles to ensure adherence to organizational policies.</td>
      </tr>
      <tr>
        <td>ActivateAllAdminShare</td>
        <td>Enables administrative shares, activates RDP, disables Windows Firewall, and deactivates Windows Defender.</td>
      </tr>
      <tr>
        <td>ExportCustomThemesFiles</td>
        <td>Exports customized desktop themes.</td>
      </tr>
      <tr>
        <td>FixPrinterDriverIssues</td>
        <td>Resets printer drivers and clears the print spooler.</td>
      </tr>
      <tr>
        <td>InventoryInstalledSoftwareList</td>
        <td>Creates an inventory of installed software for compliance.</td>
      </tr>
      <tr>
        <td>RenameDiskVolumes</td>
        <td>Renames local C: and D: disk volumes.</td>
      </tr>
      <tr>
        <td>WorkStationConfigReport</td>
        <td>Generates detailed workstation configuration reports in <code>.csv</code> format.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Next Releases</h2>
  <ul>
    <li>New tools to address evolving ITSM requirements.</li>
    <li>Enhanced reporting features for compliance audits.</li>
    <li>Improved IT service delivery capabilities.</li>
  </ul>

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
