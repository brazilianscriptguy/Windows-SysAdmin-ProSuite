<div>
  <h1>🛡️ Security and Process Optimization Tools</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>Security and Process Optimization</strong> folder includes a collection of <strong>PowerShell tools</strong> 
    designed to enhance endpoint protection, enforce compliance, and streamline administrative workflows. These scripts automate repetitive tasks, 
    strengthen policy enforcement, and improve user/system hygiene in enterprise environments.
  </p>

  <h3>Key Features:</h3>
  <ul>
    <li><strong>Automation-Driven:</strong> Reduces manual operations and promotes consistent execution.</li>
    <li><strong>Security-Focused:</strong> Applies hardened configurations, disables risky services, and enforces policy compliance.</li>
    <li><strong>Performance Insights:</strong> Analyzes resource usage, logon history, and system responsiveness.</li>
    <li><strong>Compliance Audits:</strong> Extracts data for reporting, risk assessments, and audit documentation.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell</strong>
      <ul>
        <li>Requires <strong>PowerShell 5.1+</strong> on workstations or servers.</li>
        <li>Verify with:
          <pre><code>$PSVersionTable.PSVersion</code></pre>
        </li>
      </ul>
    </li>
    <li>
      <strong>🔑 Administrator Rights</strong>
      <p>Most scripts should be run with elevated privileges to apply system-level changes.</p>
    </li>
    <li>
      <strong>📂 Execution Policy</strong>
      <p>Enable script execution for your session:</p>
      <pre><code>Set-ExecutionPolicy RemoteSigned -Scope Process</code></pre>
    </li>
  </ol>

  <hr />

  <h2>📄 Script Descriptions (Alphabetical Order)</h2>
  <table border="1" style="border-collapse: collapse; width: 100%;">
    <thead>
      <tr>
        <th style="padding: 8px;">Script Name</th>
        <th style="padding: 8px;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>Analyze-SlowLogonEvents.ps1</strong></td>
        <td>Parses Event Viewer data to identify slow logon events across systems and recommends actions.</td>
      </tr>
      <tr>
        <td><strong>Clean-TempFiles-And-Logs.ps1</strong></td>
        <td>Clears temp folders, old log files, and recycle bin contents to improve performance.</td>
      </tr>
      <tr>
        <td><strong>Disable-USB-StorageAccess.ps1</strong></td>
        <td>Disables USB mass storage driver support to reduce data exfiltration risks.</td>
      </tr>
      <tr>
        <td><strong>Enforce-SecureScreensaverPolicy.ps1</strong></td>
        <td>Applies screen lock and timeout GPOs for idle sessions across user environments.</td>
      </tr>
      <tr>
        <td><strong>Identify-LegacyTLSConfigurations.ps1</strong></td>
        <td>Scans for outdated TLS/SSL registry settings to ensure compliance with modern protocols.</td>
      </tr>
      <tr>
        <td><strong>Lock-Workstation-AfterTimeout.ps1</strong></td>
        <td>Configures auto-lock policy via local group policy objects for unattended systems.</td>
      </tr>
      <tr>
        <td><strong>Monitor-HighCPUProcesses.ps1</strong></td>
        <td>Monitors system resource usage and generates alerts or logs when thresholds are exceeded.</td>
      </tr>
      <tr>
        <td><strong>Remove-UnapprovedSoftware.ps1</strong></td>
        <td>Uninstalls listed applications that violate corporate software usage policies.</td>
      </tr>
      <tr>
        <td><strong>Secure-LocalAdministratorsGroup.ps1</strong></td>
        <td>Audits and resets local Administrators group membership based on organizational rules.</td>
      </tr>
      <tr>
        <td><strong>Track-LogonHistory.ps1</strong></td>
        <td>Generates login/logout activity reports for security monitoring and forensic analysis.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Run the Script:</strong> Right-click the script file and choose <code>Run with PowerShell</code>.</li>
    <li><strong>Provide Inputs:</strong> Follow any GUI prompts or CLI instructions where required.</li>
    <li><strong>Review Outputs:</strong> Examine logs and reports in the designated output folders.</li>
  </ol>

  <hr />

  <h2>📝 Logging and Output</h2>
  <ul>
    <li><strong>📄 Logs:</strong> Logs are written to <code>C:\Logs-TEMP</code> or <code>C:\ITSM-Logs-WKS</code> by default.</li>
    <li><strong>📊 Reports:</strong> Generated <code>.csv</code> files provide structured audit and inventory data.</li>
  </ul>

  <hr />

  <h2>💡 Tips for Optimization</h2>
  <ul>
    <li><strong>Automate Recurring Scripts:</strong> Use Task Scheduler or logon triggers to automate daily hygiene tasks.</li>
    <li><strong>Maintain a Baseline:</strong> Apply consistent policies across devices using standardized scripts.</li>
    <li><strong>Centralize Evidence:</strong> Send all logs to a shared network location for centralized review and SIEM ingestion.</li>
  </ul>
</div>
