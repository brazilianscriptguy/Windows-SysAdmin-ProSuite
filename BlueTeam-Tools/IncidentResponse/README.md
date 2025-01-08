<div align="center">

  <h1>🔵 BlueTeam-Tools - Incident Response Suite</h1>

  <p>
    The <strong>IncidentResponse Folder</strong> provides a suite of <strong>PowerShell scripts</strong> designed to streamline <strong>incident response</strong> activities in <strong>Active Directory (AD)</strong> and <strong>Windows Server</strong> environments. These tools help administrators handle security incidents effectively, automate cleanup processes, and ensure system integrity during and after incidents.
  </p>

</div>

<hr />

<h2>🔑 Key Features</h2>
<ul>
  <li><strong>User-Friendly GUI:</strong> Simplifies usage with intuitive interfaces.</li>
  <li><strong>Detailed Logging:</strong> Generates <code>.LOG</code> files for thorough tracking and troubleshooting.</li>
  <li><strong>Exportable Reports:</strong> Outputs in <code>.CSV</code> format for easy reporting and integration with audits.</li>
  <li><strong>Enhanced Incident Management:</strong> Automates critical response tasks to reduce downtime and accelerate system recovery.</li>
</ul>

<hr />

<h2>🛠️ Prerequisites</h2>
<ul>
  <li>
    <strong>⚙️ PowerShell</strong><br>
    <ul>
      <li>PowerShell must be enabled on your system.</li>
      <li>Import the required module where applicable:
        <pre><code>Import-Module ActiveDirectory</code></pre>
      </li>
    </ul>
  </li>
  <li>
    <strong>🔑 Administrator Privileges</strong><br>
    <ul>
      <li>Elevated permissions may be needed to modify AD objects, manage server roles, or access sensitive configurations.</li>
    </ul>
  </li>
  <li>
    <strong>🖥️ Remote Server Administration Tools (RSAT)</strong><br>
    <ul>
      <li>Install RSAT on your Windows 10/11 workstation for managing AD and server functions remotely.</li>
    </ul>
  </li>
</ul>

<hr />

<h2>📄 Script Descriptions (Alphabetical Order)</h2>
<ol>
  <li>
    <strong>🔍 Decipher-EML-MailMessages-Tool.ps1</strong><br>
    <ul>
      <li><strong>Purpose:</strong> Decodes suspicious email messages using techniques like offset subtraction, encoding conversions, ROT13, and Caesar cipher brute force.</li>
      <li><strong>Output:</strong> Analyzes and identifies hidden threats in email content.</li>
    </ul>
  </li>
  <li>
    <strong>🗑️ Delete-FilesByExtensionBulk-Tool.ps1</strong><br>
    <ul>
      <li><strong>Purpose:</strong> Deletes files in bulk based on specified extensions, ideal for post-incident cleanup or routine maintenance.</li>
      <li><strong>Complementary File:</strong>
        <ul>
          <li><strong>Delete-FilesByExtension-List.txt:</strong> Lists file extensions to target for deletion. Modify this file to customize cleanup parameters.</li>
        </ul>
      </li>
    </ul>
  </li>
</ol>

<hr />

<h2>🚀 Usage Instructions</h2>
<p><strong>General Steps:</strong></p>
<ol>
  <li>Run the Script: Right-click and select <code>Run With PowerShell</code>.</li>
  <li>Provide Inputs: Follow on-screen prompts or update configuration files as necessary.</li>
  <li>Review Outputs: Check the <code>.LOG</code> files for a summary of actions and results.</li>
</ol>

<p><strong>Example Scenarios:</strong></p>
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
  <li><strong>📄 Logs:</strong> Each script generates <code>.LOG</code> files that detail execution steps, actions taken, and errors encountered.</li>
  <li><strong>📊 Reports:</strong> Some scripts output data in <code>.CSV</code> format, offering insights for audits and compliance reporting.</li>
</ul>

<hr />

<h2>💡 Tips for Optimization</h2>
<ul>
  <li><strong>Automate Execution:</strong> Use task schedulers to run scripts regularly for consistent incident response and cleanup.</li>
  <li><strong>Centralize Logs and Reports:</strong> Store <code>.LOG</code> and <code>.CSV</code> files in a shared location to facilitate collaborative analysis.</li>
  <li><strong>Customize Configurations:</strong> Modify configuration files (e.g., <code>Delete-FilesByExtension-Bulk.txt</code>) to align with organizational policies and specific incident response needs.</li>
</ul>

<hr />

<h2>🎯 Contributions and Feedback</h2>
<p>
  For improvements, suggestions, or bug reports, feel free to contact:
</p>
<div align="center">
  <a href="mailto:luizhamilton.lhr@gmail.com" target="_blank" rel="noopener noreferrer">
    <img src="https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail" alt="Email Badge">
  </a>
  <a href="https://github.com/brazilianscriptguy/BlueTeam-Tools/issues" target="_blank" rel="noopener noreferrer">
    <img src="https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github" alt="GitHub Issues Badge">
  </a>
  <a href="https://patreon.com/brazilianscriptguy" target="_blank" rel="noopener noreferrer">
    <img src="https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge&logo=patreon" alt="Support on Patreon Badge">
  </a>
  <a href="https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c" target="_blank" rel="noopener noreferrer">
    <img src="https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp" alt="WhatsApp Badge">
  </a>
</div>
