<div>
  <h1>🔵 BlueTeam-Tools Main Folder</h1>

  <h2>📄 Overview</h2>
  <p>
    Welcome to the <strong>BlueTeam-Tools</strong> repository! This comprehensive collection of 
    <strong>PowerShell scripts</strong> is crafted for Forensics and Blue Team professionals to effectively 
    <strong>monitor, detect, and respond</strong> to security threats in Windows environments.
    Each tool automates the collection of forensic data, analyzes system integrity, and exports findings in 
    <code>.csv</code> and <code>.log</code> formats for fast reporting and auditing.
  </p>

  <ul>
    <li><strong>🔍 Extract Critical Data:</strong> Gather evidence from logs, services, running processes, and registries.</li>
    <li><strong>📊 Analyze Security Events:</strong> Detect anomalies, policy violations, and suspicious behaviors.</li>
    <li><strong>🧰 Streamline Incident Response:</strong> Tools include intuitive GUIs, logs, and outputs for DFIR workflows.</li>
  </ul>

  <hr />

  <h2>📁 Folder Structure & Categories</h2>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;">📂 Folder Name</th>
        <th style="padding: 8px;">📝 Description</th>
        <th style="padding: 8px;">🔗 Folder Link</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>EventLogMonitoring</strong></td>
        <td>Tools for auditing Windows Event Logs, tracking logon events, policy changes, and generating security-focused reports.</td>
        <td>
          <a href="EventLogMonitoring/README.md" target="_blank">
            <img src="https://img.shields.io/badge/EventLog%20Monitoring-README-blue?style=for-the-badge&logo=github" alt="EventLogMonitoring Badge">
          </a>
        </td>
      </tr>
      <tr>
        <td><strong>IncidentResponse</strong></td>
        <td>Scripts for capturing volatile data during live incident response, user session tracking, and memory artifact collection.</td>
        <td>
          <a href="IncidentResponse/README.md" target="_blank">
            <img src="https://img.shields.io/badge/Incident%20Response-README-blue?style=for-the-badge&logo=github" alt="IncidentResponse Badge">
          </a>
        </td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>🖥️ Remote Server Administration Tools (RSAT):</strong>
      <p>Install RSAT components to manage Active Directory, DNS, and DHCP features.</p>
      <pre><code>Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online</code></pre>
    </li>
    <li>
      <strong>⚙️ PowerShell Version:</strong>
      <p>Ensure you are using PowerShell 5.1 or later:</p>
      <pre><code>$PSVersionTable.PSVersion</code></pre>
    </li>
    <li><strong>🔑 Administrator Privileges:</strong> Most scripts require elevation to interact with system-level components.</li>
    <li>
      <strong>🔐 Execution Policy:</strong>
      <p>Temporarily enable script execution if restricted:</p>
      <pre><code>Set-ExecutionPolicy RemoteSigned -Scope Process</code></pre>
    </li>
    <li>
      <strong>📦 Required Modules:</strong>
      <p>Ensure modules like <code>ActiveDirectory</code>, <code>Defender</code>, and <code>DHCPServer</code> are present.</p>
    </li>
  </ol>

  <hr />

  <h2>🚀 Getting Started</h2>
  <ol>
    <li>
      <strong>📥 Clone the Repository:</strong>
      <pre><code>git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git</code></pre>
    </li>
    <li>
      <strong>📂 Navigate to Folder:</strong>
      <p>Enter the <code>BlueTeam-Tools</code> directory and choose your desired script folder.</p>
    </li>
    <li>
      <strong>📘 Read Documentation:</strong>
      <p>Check the subfolder’s <code>README.md</code> file for detailed usage instructions and script logic.</p>
    </li>
    <li>
      <strong>💻 Run a Script:</strong>
      <p>Launch scripts via terminal with:</p>
      <pre><code>.\ScriptName.ps1</code></pre>
    </li>
    <li>
      <strong>📑 Review Logs:</strong>
      <p>Each script logs actions in <code>.log</code> and result data in <code>.csv</code> format.</p>
    </li>
  </ol>

  <hr />

  <h2>📈 Future Updates</h2>
  <p>
    Additional tools are continuously in development to support evolving threats and enhance incident response capabilities. 
    Follow the repository to receive notifications about new Blue Team utilities.
  </p>

  <hr />

  <h2>❓ Need Help?</h2>
  <p style="text-align: justify; font-size: 16px; line-height: 1.6;">
    All scripts are modular and can be customized to meet your team's security posture and workflow requirements.
    For support, contributions, or questions, feel free to contact me or use the issue tracker linked below.
  </p>

  <div align="center">
    <a href="mailto:luizhamilton.lhr@gmail.com" target="_blank">
      <img src="https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail" alt="Email Contact">
    </a>
    <a href="https://www.patreon.com/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge&logo=patreon" alt="Patreon Support">
    </a>
    <a href="https://buymeacoffee.com/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge&logo=buymeacoffee" alt="Buy Me Coffee">
    </a>
    <a href="https://ko-fi.com/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/Ko--fi-Support-blue?style=for-the-badge&logo=kofi" alt="Ko-fi Support">
    </a>
    <a href="https://www.gofundme.com/f/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/GoFundMe-Donate-green?style=for-the-badge&logo=gofundme" alt="GoFundMe">
    </a>
    <a href="https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c" target="_blank">
      <img src="https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp" alt="WhatsApp Channel">
    </a>
    <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/issues" target="_blank">
      <img src="https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github" alt="GitHub Issues">
    </a>
  </div>
</div>
