<div>
  <h1>🛠️ ScriptsAdditionalSupport Suite</h1>

  <h2>📄 Overview</h2>
  <p>
    The <strong>ScriptsAdditionalSupport</strong> folder offers a robust collection of scripts designed to address configuration inconsistencies 
    identified by <strong>L1 Service Support Operators</strong>. These tools ensure seamless troubleshooting, maintenance, and optimization 
    for both workstation and server environments, aligning with IT compliance standards.
  </p>
  <p>
    Each script includes:
    <ul>
      <li><strong>Advanced error handling</strong></li>
      <li><strong>Detailed logging</strong></li>
      <li><strong>User-friendly GUI</strong>, where applicable</li>
    </ul>
    This suite improves operational efficiency and simplifies administrative workflows, addressing common configuration issues on workstations.
  </p>

  <hr />

  <h2>📋 Script Descriptions</h2>

  <h3>1. ActivateAllAdminShare</h3>
  <p><strong>Script:</strong> <code>Activate-All-AdminShares.ps1</code></p>
  <p>
    Enables administrative shares, activates Remote Desktop Protocol (RDP), disables Windows Firewall, and deactivates Windows Defender 
    to facilitate administrative access. Includes a GUI for task management.
  </p>

  <h3>2. ExportCustomThemesFiles</h3>
  <p><strong>Script:</strong> <code>Exports-CustomThemes-Files.ps1</code></p>
  <p>
    Standardizes desktop and user interface configurations by exporting custom Windows theme files, such as <code>LayoutModification.xml</code>, 
    <code>.msstyles</code>, and <code>.deskthemepack</code>, across the network.
  </p>

  <h3>3. FixPrinterDriverIssues</h3>
  <p><strong>Script:</strong> <code>Fix-PrinterDriver-Issues.ps1</code></p>
  <p>
    Troubleshoots common printer-related issues by:
    <ul>
      <li>Resetting the print spooler</li>
      <li>Clearing print jobs</li>
      <li>Managing printer drivers</li>
    </ul>
    Includes multiple resolution methods and a GUI for ease of use.
  </p>

  <h3>4. GetSID</h3>
  <p><strong>Tool:</strong> <code>PsGetsid64.exe</code> (MS Sysinternals)</p>
  <p>
    Translates <strong>Security Identifiers (SID)</strong> to display names and vice versa. Useful for diagnosing and managing builtin accounts, 
    domain accounts, and local accounts.
  </p>

  <h3>5. InventoryInstalledSoftwareList</h3>
  <p><strong>Script:</strong> <code>Inventory-InstalledSoftwareList.ps1</code></p>
  <p>
    Inventories all installed software on the workstation, generating a comprehensive report for auditing and compliance purposes.
  </p>

  <h3>6. LegacyWorkstationIngress</h3>
  <p><strong>Script:</strong> <code>LSA-NetJoin-Legacy.ps1</code></p>
  <p>
    Modifies registry settings to enable legacy operating systems to join modern domains. Fully compatible with Windows Server 2019 and newer.
  </p>

  <h3>7. RecallKESCert</h3>
  <p><strong>Script:</strong> <code>RecallKESCert.ps1</code></p>
  <p>
    Repoints the workstation to the antivirus server and renews the required certificate, ensuring continued protection and secure operations.
  </p>

  <h3>8. RenameDiskVolumes</h3>
  <p><strong>Script:</strong> <code>ChangeDiskVolumesNames.ps1</code></p>
  <p>
    Renames disk volumes:
    <ul>
      <li><strong>C:</strong> drive is labeled with the hostname.</li>
      <li><strong>D:</strong> drive is labeled for personal data or custom use.</li>
    </ul>
    Detailed logs ensure traceability.
  </p>

  <h3>9. ResyncGPOsDataStore</h3>
  <p><strong>Script:</strong> <code>Resync-GPOs-DataStore.ps1</code></p>
  <p>
    Resets all Group Policy Objects (GPOs) on the workstation and synchronizes them with domain policies. A GUI assists users and logs all actions 
    for accountability.
  </p>

  <h3>10. UnjoinADComputer-and-Cleanup</h3>
  <p><strong>Script:</strong> <code>Unjoin-ADComputer-and-Cleanup.ps1</code></p>
  <p>
    Unjoins the workstation from the domain and performs cleanup tasks, such as:
    <ul>
      <li>Clearing DNS cache</li>
      <li>Removing old domain profiles</li>
      <li>Resetting environment variables</li>
    </ul>
  </p>

  <h3>11. WorkStationConfigReport</h3>
  <p><strong>Script:</strong> <code>Workstation-Data-Report.ps1</code></p>
  <p>
    Compiles system configuration details, including OS, BIOS, and network information, into a <code>.CSV</code> file. Designed with a GUI for user 
    feedback and error handling.
  </p>

  <h3>12. WorkstationTimeSync</h3>
  <p><strong>Script:</strong> <code>Workstation-TimeSync.ps1</code></p>
  <p>
    Synchronizes the workstation’s time, date, and time zone with the domain controllers, ensuring network-wide consistency.
  </p>

  <hr />

  <h2>🚀 How to Use</h2>
  <ol>
    <li>Navigate to the <strong>ScriptsAdditionalSupport</strong> folder in the <strong>ITSM-Templates-WKS</strong> directory.</li>
    <li>Select and execute the script relevant to the issue or task at hand.</li>
    <li>Refer to the usage instructions included in the script headers or associated documentation for detailed guidance.</li>
  </ol>

  <hr />

  <h2>📝 Logging and Output</h2>
  <ul>
    <li><strong>Log Directory:</strong> Each script generates <code>.log</code> files saved in <code>C:\ITSM-Logs-WKS\</code>.</li>
    <li><strong>Details Logged:</strong> Logs capture all actions performed, outcomes, and errors encountered, ensuring transparency and aiding troubleshooting.</li>
  </ul>

  <hr />

  <h2>🔗 References</h2>
  <ul>
    <li>
      <a href="https://github.com/brazilianscriptguy/PowerShell-codes-for-Windows-Server-Administrators/blob/main/ITSM-Templates-WKS/README.md" 
         target="_blank" rel="noopener noreferrer">
        <img src="https://img.shields.io/badge/View%20Documentation-ITSM--Templates--WKS-blue?style=flat-square&logo=github" alt="ITSM-Templates-WKS Documentation Badge">
      </a>
    </li>
    <li>For further assistance, contact your <strong>L1 Service Support Coordinator</strong> or refer to the <code>README.md</code> in the root directory of <strong>ITSM-Templates-WKS</strong>.</li>
  </ul>

  <hr />

  <h2>❓ Additional Assistance</h2>
  <p>
    These scripts are fully customizable to fit your unique requirements. For more information on setup or assistance with specific tools, 
    refer to the included <code>README.md</code> or the detailed documentation available in each subfolder.
  </p>

  <div align="center">
    <a href="mailto:luizhamilton.lhr@gmail.com" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail" alt="Email Badge">
    </a>
    <a href="https://www.patreon.com/c/brazilianscriptguy" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge&logo=patreon" alt="Support on Patreon Badge">
    </a>
    <a href="https://github.com/brazilianscriptguy/BlueTeam-Tools/issues" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github" alt="GitHub Issues Badge">
    </a>
  </div>
</div>
