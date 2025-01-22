<div>
  <h1>🔵 BlueTeam-Tools Main Folder</h1>

  <h2>📄 Overview</h2>
  <p>
    Welcome to the <strong>BlueTeam-Tools</strong> repository! This comprehensive collection of <strong>PowerShell scripts</strong> is tailored for Forensics and Blue Team professionals to efficiently monitor, detect, and respond to security threats. Each tool extracts critical information from logs, system configurations, and processes, providing actionable insights through outputs in <code>.CSV</code> format for seamless analysis and reporting.
  </p>
  <ul>
    <li><strong>Extract Critical Data:</strong> Automate the collection of information from Windows Event Logs, running processes, configurations, and more.</li>
    <li><strong>Analyze Security Events:</strong> Gain insights into anomalies, suspicious activities, and compliance gaps.</li>
    <li><strong>Streamline Operations:</strong> Use built-in GUIs for enhanced usability and generate <code>.log</code> and <code>.csv</code> files for thorough analysis and reporting.</li>
  </ul>

  <hr />

  <h2>📂 Folder Structure and Categories</h2>

  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;">Folder Name</th>
        <th style="padding: 8px;">Description</th>
        <th style="padding: 8px;">Folder Link</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>EventLogMonitoring</strong></td>
        <td>Tools for processing and analyzing Windows Event Logs. Focuses on detecting anomalies, auditing logs, and generating actionable reports for key system events.</td>
        <td>
          <a href="EventLogMonitoring/README.md" target="_blank">
            <img src="https://img.shields.io/badge/EventLog%20Monitoring-README-blue?style=for-the-badge&logo=github" 
            alt="EventLogMonitoring README Badge">
          </a>
        </td>
      </tr>
      <tr>
        <td><strong>IncidentResponse</strong></td>
        <td>A suite of scripts designed to facilitate rapid response to security incidents. Assists in collecting and analyzing critical data during active investigations.</td>
        <td>
          <a href="IncidentResponse/README.md" target="_blank">
            <img src="https://img.shields.io/badge/Incident%20Response-README-blue?style=for-the-badge&logo=github" 
            alt="IncidentResponse README Badge">
          </a>
        </td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Future Updates</h2>
  <p>
    Stay tuned for additional tools and enhancements to expand the <strong>BlueTeam-Tools</strong> repository. Future updates will continue to focus on innovative and efficient solutions for Forensics and Security Teams.
  </p>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>🖥️ Remote Server Administration Tools (RSAT):</strong>
      <p>Install RSAT components for managing AD, DNS, DHCP, and other server roles.</p>
      <pre><code>Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online</code></pre>
    </li>
    <li>
      <strong>⚙️ PowerShell Version:</strong>
      <p>Use PowerShell 5.1 or later. Verify your version:</p>
      <pre><code>$PSVersionTable.PSVersion</code></pre>
    </li>
    <li><strong>🔑 Administrator Privileges:</strong> Scripts require elevated permissions to perform administrative tasks.</li>
    <li>
      <strong>🔧 Execution Policy:</strong>
      <p>Temporarily allow script execution with:</p>
      <pre><code>Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process</code></pre>
    </li>
    <li>
      <strong>📦 Dependencies:</strong>
      <p>Ensure all required software components and modules (e.g., <code>ActiveDirectory</code>, <code>DHCPServer</code>) are installed.</p>
    </li>
  </ol>

  <hr />

<h2>🚀 Getting Started</h2>
  <ol>
      <li>
      <strong>Clone or download the Main Repository:</strong>
      <pre><code>git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git</code></pre>
    </li>
    <li>
      <strong>Navigate to the Repository Folder:</strong>
      <p>Navigate to the <code>Windows-SysAdmin-ProSuite/BlueTeam-Tools/</code> directory that contains the desired scripts.</p>
    </li>
    <li>
      <strong>Review Documentation:</strong>
      <p>Open the <code>README.md</code> file in the chosen subfolder for detailed script descriptions and usage instructions.</p>
    </li>
    <li>
      <strong>Run the Script:</strong>
      <p>Execute the desired PowerShell script with the following command:</p>
      <pre><code>.\ScriptName.ps1</code></pre>
    </li>
    <li>
      <strong>Verify Logs and Reports:</strong>
      <p>Check the generated <code>.log</code> files for details on script execution and exported <code>.csv</code> files for results.</p>
    </li>
  </ol>

  <hr />

  <h2>❓ Additional Assistance</h2>
<p style="text-align: justify; font-size: 16px; line-height: 1.6;">
  These scripts are fully customizable to fit your unique requirements. For more information on setup or assistance with 
  specific tools, please refer to the included <code>README.md</code> files or explore the detailed documentation available 
  in each subfolder.
</p>

<div align="center">
  <a href="mailto:luizhamilton.lhr@gmail.com" target="_blank" rel="noopener noreferrer" aria-label="Email Luiz Hamilton">
    <img src="https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail" 
         alt="Contact via Email">
  </a>
  <a href="https://www.patreon.com/brazilianscriptguy" target="_blank" rel="noopener noreferrer" aria-label="Support on Patreon">
    <img src="https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge&logo=patreon" 
         alt="Support on Patreon">
  </a>
  <a href="https://buymeacoffee.com/brazilianscriptguy" target="_blank" rel="noopener noreferrer" aria-label="Buy Me a Coffee">
    <img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Support-yellow?style=for-the-badge&logo=buymeacoffee" 
         alt="Buy Me a Coffee">
  </a>
  <a href="https://ko-fi.com/brazilianscriptguy" target="_blank" rel="noopener noreferrer" aria-label="Support on Ko-fi">
    <img src="https://img.shields.io/badge/Ko--fi-Support%20Me-blue?style=for-the-badge&logo=kofi" 
         alt="Support on Ko-fi">
  </a>
  <a href="https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c" target="_blank" rel="noopener noreferrer" aria-label="Join WhatsApp Channel">
    <img src="https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp" 
         alt="Join WhatsApp Channel">
  </a>
  <a href="https://github.com/brazilianscriptguy/BlueTeam-Tools/issues" target="_blank" rel="noopener noreferrer" aria-label="Report Issues on GitHub">
    <img src="https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github" 
         alt="Report Issues on GitHub">
  </a>
</div>

