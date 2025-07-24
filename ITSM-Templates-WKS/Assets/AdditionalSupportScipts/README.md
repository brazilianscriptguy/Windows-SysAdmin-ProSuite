<div>
  <h1>🛠️ ScriptsAdditionalSupport Suite</h1>

  <h2>📄 Overview</h2>
  <p>
    The <strong>ScriptsAdditionalSupport</strong> folder provides a robust collection of PowerShell tools tailored to address system configuration issues, maintenance, and administrative troubleshooting, especially for <strong>L1 Service Support Operators</strong>. 
  </p>
  <p>
    Each script in this suite includes:
    <ul>
      <li><strong>Advanced error handling</strong></li>
      <li><strong>Consistent logging to <code>C:\ITSM-Logs-WKS\</code></strong></li>
      <li><strong>GUI interfaces</strong> (when appropriate) for intuitive use</li>
    </ul>
  </p>

  <hr />

  <h2>📋 Script Descriptions</h2>
  <table border="1" style="border-collapse: collapse; width: 100%;">
    <thead>
      <tr>
        <th style="padding: 8px; text-align: left;">Script Name</th>
        <th style="padding: 8px; text-align: left;">Description</th>
      </tr>
    </thead>
    <tbody>

      <tr>
        <td><strong>Activate-All-AdminShares.ps1</strong></td>
        <td>
          Activates administrative shares, Remote Desktop, disables Defender and Firewall to restore full IT support access.
        </td>
      </tr>

      <tr>
        <td><strong>Exports-CustomThemes-Files.ps1</strong></td>
        <td>
          Exports Windows themes like <code>LayoutModification.xml</code>, <code>.deskthemepack</code>, etc., to standardize desktop appearance across workstations.
        </td>
      </tr>

      <tr>
        <td><strong>Fix-PrinterDriver-Issues.ps1</strong></td>
        <td>
          Provides a GUI tool for resetting the spooler, clearing print queues, and removing printer drivers.
        </td>
      </tr>

      <tr>
        <td><strong>PsGetsid64.exe</strong></td>
        <td>
          Utility to map usernames to SIDs and vice versa. Useful for profile cleanup or SID resolution in enterprise environments.
        </td>
      </tr>

      <tr>
        <td><strong>Inventory-InstalledSoftwareList.ps1</strong></td>
        <td>
          Generates a CSV report of all installed applications for software audits and compliance.
        </td>
      </tr>

      <tr>
        <td><strong>LegacyWorkstationIngress.ps1</strong></td>
        <td>
          Enables legacy OS (e.g., Windows 7) to rejoin the domain with the same hostname by setting <code>NetJoinLegacyAccountReuse</code> registry key.
        </td>
      </tr>

      <tr>
        <td><strong>RenameDiskVolumes.ps1</strong></td>
        <td>
          Renames drive letters:
          <ul>
            <li><code>C:\</code> becomes the hostname</li>
            <li><code>D:\</code> becomes <code>Personal-Files</code></li>
          </ul>
        </td>
      </tr>

      <tr>
        <td><strong>System-Maintenance-Workstations.ps1</strong></td>
        <td>
          Executes system repair and reconfiguration routines:
          <ul>
            <li>Runs <code>SFC</code> and <code>DISM</code></li>
            <li>Clears GPO registry/folder</li>
            <li>Resets Windows Update cache</li>
            <li>Deletes avatar .DAT files</li>
            <li>Optionally reboots the system</li>
          </ul>
        </td>
      </tr>

      <tr>
        <td><strong>Unjoin-ADComputer-and-Cleanup.ps1</strong></td>
        <td>
          GUI-assisted domain unjoin script that:
          <ul>
            <li>Requests admin credentials</li>
            <li>Unjoins from AD</li>
            <li>Clears DNS cache and domain profiles</li>
            <li>Resets environment variables</li>
            <li>Logs all actions</li>
          </ul>
        </td>
      </tr>

      <tr>
        <td><strong>Update-KasperskyAgent.ps1</strong></td>
        <td>
          Reassigns Kaspersky agent to correct administration server and refreshes local certificates.
        </td>
      </tr>

      <tr>
        <td><strong>Workstation-ConfigReport.ps1</strong></td>
        <td>
          Collects detailed BIOS, OS, memory, and IP configuration into a CSV file for diagnostics or asset tracking. ANSI-compliant log included.
        </td>
      </tr>

      <tr>
        <td><strong>Workstation-TimeSync.ps1</strong></td>
        <td>
          Forces immediate synchronization of workstation time, date, and time zone with domain controllers.
        </td>
      </tr>

    </tbody>
  </table>

  <hr />

  <h2>🚀 How to Use</h2>
  <ol>
    <li>Open <code>PowerShell</code> as administrator.</li>
    <li>Navigate to: <code>C:\ITSM-Templates-WKS\Assets\AdditionalSupportScipts</code></li>
    <li>Run the script you need: <code>.\ScriptName.ps1</code></li>
  </ol>

  <hr />

  <h2>📝 Logging & Output</h2>
  <ul>
    <li><strong>Logs:</strong> Saved in <code>C:\ITSM-Logs-WKS\</code> with timestamped entries.</li>
    <li><strong>CSV Reports:</strong> For scripts like <code>Workstation-ConfigReport.ps1</code>, outputs are saved in the same directory as the script.</li>
  </ul>

  <hr />

  <h2>📚 Reference & Support</h2>
  <ul>
    <li>
      <a href="https://github.com/brazilianscriptguy/PowerShell-codes-for-Windows-Server-Administrators/blob/main/ITSM-Templates-WKS/README.md" target="_blank">
        <img src="https://img.shields.io/badge/View%20Documentation-ITSM--Templates--WKS-blue?style=flat-square&logo=github" />
      </a>
    </li>
    <li>Need help? Contact your <strong>L1 Support Coordinator</strong> or check the <code>README.md</code> in each script folder.</li>
  </ul>

  <hr />

  <h2>❤️ Contribute or Support</h2>
  <div align="center">
    <a href="mailto:luizhamilton.lhr@gmail.com" target="_blank">
      <img src="https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail" />
    </a>
    <a href="https://www.patreon.com/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge&logo=patreon" />
    </a>
    <a href="https://github.com/brazilianscriptguy/BlueTeam-Tools/issues" target="_blank">
      <img src="https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github" />
    </a>
  </div>
</div>
