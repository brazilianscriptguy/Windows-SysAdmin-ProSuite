<div>
  <h1>🔵 BlueTeam-Tools: EventLog Monitoring Suite</h1>

  <h2>📌 Overview</h2>
  <p>
    The <strong>EventLogMonitoring</strong> folder offers a robust suite of <strong>PowerShell scripts</strong> tailored for security analysts and Windows admins seeking to analyze <code>.evtx</code> files efficiently.
    These tools streamline the process of auditing login events, print usage, object changes, and system restarts — generating <code>.log</code> and <code>.csv</code> reports for documentation, forensics, and compliance audits.
  </p>

  <ul>
    <li>🎛️ <strong>GUI Interfaces:</strong> Most scripts are GUI-based for ease of use.</li>
    <li>📈 <strong>Report Exports:</strong> Outputs structured <code>.csv</code> files for log correlation and dashboards.</li>
    <li>🧾 <strong>Execution Logs:</strong> Each run generates a traceable <code>.log</code> file.</li>
    <li>🔎 <strong>Security Insights:</strong> Track failed logons, admin group changes, explicit credentials, object deletions, etc.</li>
  </ul>

  <hr />

  <h2>📦 Script Inventory (Alphabetical)</h2>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;">Script</th>
        <th style="padding: 8px;">Purpose</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>EventID-Count-AllEvtx-Events.ps1</strong></td>
        <td>Counts all Event IDs in selected <code>.evtx</code> files. Exports a summary to <code>.csv</code>.</td>
      </tr>
      <tr>
        <td><strong>EventID307-PrintAudit.ps1</strong></td>
        <td>Audits print activity via Event ID 307. Includes setup guide: <code>PrintService-Operational-EventLogs.md</code>.</td>
      </tr>
      <tr>
        <td><strong>EventID4624-ADUserLoginViaRDP.ps1</strong></td>
        <td>Logs Event ID 4624 (logon) filtered by RDP logins. Useful for remote session audits.</td>
      </tr>
      <tr>
        <td><strong>EventID4624and4634-ADUserLoginTracking.ps1</strong></td>
        <td>Tracks login + logout (4624, 4634). Outputs full session details per user.</td>
      </tr>
      <tr>
        <td><strong>EventID4625-ADUserLoginAccountFailed.ps1</strong></td>
        <td>Captures failed login attempts. Filters Event ID 4625 and exports to <code>.csv</code>.</td>
      </tr>
      <tr>
        <td><strong>EventID4648-ExplicitCredentialsLogon.ps1</strong></td>
        <td>Reports on Event ID 4648 (use of explicit credentials). Helps detect lateral movement.</td>
      </tr>
      <tr>
        <td><strong>EventID4663-TrackingObjectDeletions.ps1</strong></td>
        <td>Monitors object deletions using Event ID 4663 and Access Mask 0x10000.</td>
      </tr>
      <tr>
        <td><strong>EventID4720to4756-PrivilegedAccessTracking.ps1</strong></td>
        <td>Audits privileged account creation, group changes, and access control events.</td>
      </tr>
      <tr>
        <td><strong>EventID4771-KerberosPreAuthFailed.ps1</strong></td>
        <td>Tracks failed Kerberos pre-authentication events (ID 4771). Useful for brute-force detection.</td>
      </tr>
      <tr>
        <td><strong>EventID4800and4801-WorkstationLockStatus.ps1</strong></td>
        <td>Logs workstation lock/unlock events. Visualize user presence timelines.</td>
      </tr>
      <tr>
        <td><strong>EventID5136-5137-5141-ADObjectChanges.ps1</strong></td>
        <td>Audits object creations, modifications, deletions in AD schema. Outputs object DN, who, what, when.</td>
      </tr>
      <tr>
        <td><strong>EventID6005-6006-6008-6009-6013-1074-1076-SystemRestarts.ps1</strong></td>
        <td>Tracks system reboots, shutdowns, crash events, user-initiated restarts.</td>
      </tr>
      <tr>
        <td><strong>Migrate-WinEvtStructure-Tool.ps1</strong></td>
        <td>Moves Windows Event Logs to a new location. Adjusts registry keys, preserves ACLs.</td>
      </tr>
    </tbody>
  </table>

  <blockquote>
    <strong>🧠 Migration Notes for <code>Migrate-WinEvtStructure-Tool.ps1</code>:</strong>
    <ul>
      <li>Use Safe Mode to safely stop EventLog service:
        <pre><code>bcdedit /set {current} safeboot minimal
shutdown /r /t 0</code></pre>
        <em>After migration:</em>
        <pre><code>bcdedit /deletevalue {current} safeboot
shutdown /r /t 0</code></pre>
      </li>
      <li>Backup DHCP server config (if needed):
        <pre><code>netsh dhcp server export C:\Backup\dhcpconfig.dat all</code></pre>
        Restore with:
        <pre><code>netsh dhcp server import C:\Backup\dhcpconfig.dat all</code></pre>
      </li>
    </ul>
  </blockquote>

  <hr />

  <h2>🚀 How to Use</h2>
  <ol>
    <li><strong>Run the Script:</strong> Right-click and choose <code>Run with PowerShell</code> or use terminal execution.</li>
    <li><strong>Select Input:</strong> Choose one or more <code>.evtx</code> files when prompted or via GUI.</li>
    <li><strong>Analyze Outputs:</strong> Review the <code>.csv</code> files for results and <code>.log</code> for runtime info.</li>
  </ol>

  <hr />

  <h2>🛠️ Requirements</h2>
  <ul>
    <li><strong>PowerShell 5.1+</strong></li>
    <li><strong>Admin Rights</strong> to access protected logs</li>
    <li><strong>RSAT Tools</strong> for AD-related filtering</li>
    <li><strong>Log Parser 2.2</strong> for advanced queries —
      <a href="https://www.microsoft.com/en-us/download/details.aspx?id=24659" target="_blank">
        <img src="https://img.shields.io/badge/Download-Log%20Parser-blue?style=flat-square&logo=microsoft" alt="Log Parser">
      </a>
    </li>
  </ul>

  <hr />

  <h2>📊 Logs and Exports</h2>
  <ul>
    <li><code>.log</code> files: Record execution steps, warnings, and user actions.</li>
    <li><code>.csv</code> exports: Cleanly formatted data for Excel or SIEM integration.</li>
  </ul>

  <hr />

  <h2>💡 Optimization Tips</h2>
  <ul>
    <li>Use Task Scheduler to run analysis daily or weekly.</li>
    <li>Redirect outputs to centralized logging paths (e.g., <code>\\logserver\exports</code>).</li>
    <li>Apply filters to reduce irrelevant events and improve accuracy.</li>
  </ul>
</div>
