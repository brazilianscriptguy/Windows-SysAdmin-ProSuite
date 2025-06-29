<div>
  <h1>🔵 BlueTeam-Tools: Incident Response Suite</h1>

  <h2>📌 Overview</h2>
  <p>
    The <strong>IncidentResponse</strong> folder offers a targeted set of <strong>PowerShell scripts</strong> designed to assist with real-time <strong>incident response</strong> in <strong>Active Directory</strong> and <strong>Windows Server</strong> environments.
    These tools help security teams rapidly assess, remediate, and document cyber incidents with minimal downtime — all while maintaining robust audit trails.
  </p>

  <ul>
    <li>🧠 <strong>Forensic Precision:</strong> Deciphers encoded messages, logs attacker activity, and sanitizes compromised systems.</li>
    <li>🛡️ <strong>Rapid Cleanup:</strong> Scripts for targeted post-incident actions like file deletions and content decodings.</li>
    <li>📝 <strong>Audit-Friendly:</strong> Generates structured <code>.log</code> and <code>.csv</code> outputs for forensic evidence and compliance.</li>
    <li>🎛️ <strong>GUI-Enhanced:</strong> User-friendly interfaces where applicable to reduce analyst fatigue.</li>
  </ul>

  <hr />

  <h2>📦 Script Inventory (Alphabetical)</h2>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;">Script</th>
        <th style="padding: 8px;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>Decipher-EML-MailMessages-Tool.ps1</strong></td>
        <td>Analyzes suspicious emails by applying decoding methods (ROT13, Caesar cipher, base64, ASCII shift). Helps identify hidden payloads.</td>
      </tr>
      <tr>
        <td><strong>Delete-FilesByExtensionBulk-Tool.ps1</strong></td>
        <td>Deletes files in bulk by extension. Uses <code>Delete-FilesByExtension-List.txt</code> to specify file types for secure cleanup.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 How to Use</h2>
  <ol>
    <li><strong>Run the Script:</strong> Right-click and choose <code>Run with PowerShell</code>, or use CLI.</li>
    <li><strong>Provide Inputs:</strong> Follow prompts or load config file depending on the script.</li>
    <li><strong>Review Outputs:</strong> Analyze the generated <code>.log</code> and <code>.csv</code> reports for post-execution validation.</li>
  </ol>

  <h3>🔬 Example Scenarios</h3>
  <ul>
    <li>
      <strong>🧩 Decipher-EML-MailMessages-Tool.ps1</strong>
      <ul>
        <li>Decode embedded threats in suspicious emails (e.g., phishing payloads, C2 beacons).</li>
        <li>Review log for successful decoding operations and matches.</li>
      </ul>
    </li>
    <li>
      <strong>🧹 Delete-FilesByExtensionBulk-Tool.ps1</strong>
      <ul>
        <li>Update <code>Delete-FilesByExtension-List.txt</code> (e.g., <code>.tmp</code>, <code>.bak</code>, <code>.vbs</code>).</li>
        <li>Use the script for secure removal of post-attack remnants.</li>
      </ul>
    </li>
  </ul>

  <hr />

  <h2>🛠️ Requirements</h2>
  <ul>
    <li><strong>PowerShell 5.1+</strong></li>
    <li><strong>Administrator Privileges</strong> for registry/file/object operations</li>
    <li><strong>RSAT (Remote Server Admin Tools)</strong> for AD-related scripts</li>
    <li><strong>ActiveDirectory Module:</strong>
      <pre><code>Import-Module ActiveDirectory</code></pre>
    </li>
  </ul>

  <hr />

  <h2>📊 Logs and Reports</h2>
  <ul>
    <li><code>.log</code>: Captures script flow, exceptions, and summary of changes.</li>
    <li><code>.csv</code>: Structured exports for integration into incident reports or SIEM ingestion.</li>
  </ul>

  <hr />

  <h2>💡 Optimization Tips</h2>
  <ul>
    <li>🕓 <strong>Automate Actions:</strong> Use Task Scheduler for recurring cleanup jobs.</li>
    <li>📁 <strong>Centralize Outputs:</strong> Store <code>.log</code> and <code>.csv</code> in a shared folder for SOC/SIEM access.</li>
    <li>🔧 <strong>Customize Templates:</strong> Adjust included config files to fit specific use cases.</li>
  </ul>
</div>
