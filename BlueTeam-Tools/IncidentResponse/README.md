<div>
  <h1>🔵 BlueTeam-Tools - Incident Response Suite</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>IncidentResponse Folder</strong> provides a suite of 
    <strong>PowerShell scripts</strong> designed to streamline <strong>incident response</strong> activities in <strong>Active Directory (AD)</strong> and 
    <strong>Windows Server</strong> environments. These tools help administrators handle security incidents effectively, automate cleanup processes, and ensure system integrity during and after incidents.
  </p>

  <h3>Key Features:</h3>
  <ul>
    <li><strong>User-Friendly GUI:</strong> Simplifies usage with intuitive interfaces.</li>
    <li><strong>Detailed Logging:</strong> Generates <code>.log</code> files for thorough tracking and troubleshooting.</li>
    <li><strong>Exportable Reports:</strong> Outputs in <code>.csv</code> format for easy reporting and integration with audits.</li>
    <li><strong>Enhanced Incident Management:</strong> Automates critical response tasks to reduce downtime and accelerate system recovery.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell</strong>
      <ul>
        <li>PowerShell must be enabled on your system.</li>
        <li>Import the required module where applicable:
          <pre><code>Import-Module ActiveDirectory</code></pre>
        </li>
      </ul>
    </li>
    <li>
      <strong>🔑 Administrator Privileges</strong>
      <p>Elevated permissions may be needed to modify AD objects, manage server roles, or access sensitive configurations.</p>
    </li>
    <li>
      <strong>🖥️ Remote Server Administration Tools (RSAT)</strong>
      <p>Install RSAT on your Windows 10/11 workstation for managing AD and server functions remotely.</p>
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
        <td><strong>🔍 Decipher-EML-MailMessages-Tool.ps1</strong></td>
        <td>Decodes suspicious email messages using techniques like offset subtraction, encoding conversions, ROT13, and Caesar cipher brute force. Analyzes and identifies hidden threats in email content.</td>
      </tr>
      <tr>
        <td><strong>🗑️ Delete-FilesByExtensionBulk-Tool.ps1</strong></td>
        <td>Deletes files in bulk based on specified extensions, ideal for post-incident cleanup or routine maintenance. Uses <code>Delete-FilesByExtension-List.txt</code> for customizable cleanup parameters.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Run the Script:</strong> Right-click and select <code>Run With PowerShell</code>.</li>
    <li><strong>Provide Inputs:</strong> Follow on-screen prompts or update configuration files as necessary.</li>
    <li><strong>Review Outputs:</strong> Check the <code>.log</code> files for a summary of actions and results.</li>
  </ol>

  <h3>Example Scenarios:</h3>
  <ul>
    <li>
      <strong>🔍 Decipher-EML-MailMessages-Tool.ps1</strong>
      <ul>
        <li>Use the script to decode suspicious email messages, identifying hidden threats or harmful content.</li>
        <li>Analyze the logs for detailed decoding steps and results.</li>
      </ul>
    </li>
    <li>
      <strong>🗑️ Delete-FilesByExtensionBulk-Tool.ps1</strong>
      <ul>
        <li>Update <code>Delete-FilesByExtensionBulk-List.txt</code> to specify extensions for deletion (e.g., <code>.tmp</code>, <code>.bak</code>).</li>
        <li>Run the script to delete files in bulk from targeted directories.</li>
        <li>Review the generated log to verify file removal and identify any issues.</li>
      </ul>
    </li>
  </ul>

  <hr />

  <h2>📝 Logging and Output</h2>
  <ul>
    <li><strong>📄 Logs:</strong> Each script generates <code>.log</code> files that detail execution steps, actions taken, and errors encountered.</li>
    <li><strong>📊 Reports:</strong> Some scripts output data in <code>.csv</code> format, offering insights for audits and compliance reporting.</li>
  </ul>

  <hr />

  <h2>💡 Tips for Optimization</h2>
  <ul>
    <li><strong>Automate Execution:</strong> Use task schedulers to run scripts regularly for consistent incident response and cleanup.</li>
    <li><strong>Centralize Logs and Reports:</strong> Store <code>.log</code> and <code>.csv</code> files in a shared location to facilitate collaborative analysis.</li>
    <li><strong>Customize Configurations:</strong> Modify configuration files (e.g., <code>Delete-FilesByExtension-Bulk.txt</code>) to align with organizational policies and specific incident response needs.</li>
  </ul>
</div>
