<div align="center">

  <h1>🔵 BlueTeam-Tools Main Folder</h1>

  <p>
    Welcome to the <strong>BlueTeam-Tools</strong> repository! This comprehensive collection of <strong>PowerShell scripts</strong> is tailored for Forensics and Blue Team professionals to efficiently monitor, detect, and respond to security threats. Each tool extracts critical information from logs, system configurations, and processes, providing actionable insights through outputs in <code>.CSV</code> format for seamless analysis and reporting.
  </p>

</div>

<hr />

<h2>🛠️ Prerequisites</h2>
<ul>
  <li>
    <strong>⚙️ PowerShell</strong><br>
    <ul>
      <li><strong>Version Requirement:</strong> PowerShell 5.1 or later is recommended.</li>
      <li>
        <strong>Check Version:</strong> Use the command below to verify your PowerShell version:<br>
        <pre><code>$PSVersionTable.PSVersion</code></pre>
      </li>
    </ul>
  </li>

  <li>
    <strong>🖥️ Remote Server Administration Tools (RSAT)</strong><br>
    <ul>
      <li><strong>Installation:</strong> Necessary on Windows 10/11 workstations.</li>
      <li>
        <strong>Usage:</strong> Enables remote management of <strong>Active Directory, DNS, DHCP</strong>, and other server roles by importing modules such as:<br>
        <pre><code>Import-Module ActiveDirectory</code></pre>
        <pre><code>Import-Module DHCPServer</code></pre>
      </li>
    </ul>
  </li>

  <li>
    <strong>📝 Microsoft Log Parser Utility</strong><br>
    <ul>
      <li>
        <strong>Installation:</strong> Download from the 
        <a href="https://www.microsoft.com/en-us/download/details.aspx?id=24659" target="_blank" rel="noopener noreferrer">
          <img src="https://img.shields.io/badge/Log%20Parser-Download-blue?style=for-the-badge&logo=microsoft" alt="Log Parser Badge">
        </a>
      </li>
      <li>
        <strong>Usage:</strong> Facilitates advanced querying and analysis of Windows Event Logs and other log formats.
      </li>
    </ul>
  </li>

  <li>
    <strong>🔑 Administrator Privileges</strong><br>
    <ul>
      <li>
        <strong>Note:</strong> Some scripts require elevated permissions to access system information, modify settings, or analyze restricted logs.
      </li>
    </ul>
  </li>
</ul>

<hr />

<h2>📄 Description</h2>
<p>
  This repository offers a versatile suite of <strong>PowerShell scripts</strong> to support forensic investigations and enhance the operational efficiency of Blue Teams. These tools empower administrators to:
</p>
<ul>
  <li><strong>Extract Critical Data:</strong> Automate the collection of information from Windows Event Logs, running processes, configurations, and more.</li>
  <li><strong>Analyze Security Events:</strong> Gain insights into anomalies, suspicious activities, and compliance gaps.</li>
  <li><strong>Streamline Operations:</strong> Use built-in GUIs for enhanced usability and generate <code>.log</code> and <code>.csv</code> files for thorough analysis and reporting.</li>
</ul>

<div align="center">
  <h3>✨ Why BlueTeam-Tools?</h3>
  <ul>
    <li><strong>User-Friendly:</strong> Scripts feature graphical interfaces for intuitive use.</li>
    <li><strong>Detailed Logging:</strong> Actions are tracked in <code>.log</code> files for transparency and troubleshooting.</li>
    <li><strong>Actionable Reports:</strong> Outputs are provided in <code>.csv</code> format for easy integration with reporting workflows.</li>
  </ul>
</div>

<hr />

<h2>📁 Folder Structure</h2>
<ul>
  <li>
    <strong>📄 EventLogMonitoring</strong><br>
    Tools for processing and analyzing Windows Event Logs. Focuses on detecting anomalies, auditing logs, and generating actionable reports for key system events.
  </li>
  <li>
    <strong>🛡️ IncidentResponse</strong><br>
    A suite of scripts designed to facilitate rapid response to security incidents. Assists in collecting and analyzing critical data during active investigations.
  </li>
</ul>

<hr />

<h2>🚀 Future Updates</h2>
<p>
  Stay tuned for additional tools and enhancements to expand the <strong>BlueTeam-Tools</strong> repository. Future updates will continue to focus on innovative and efficient solutions for Forensics and Security Teams.
</p>

<hr />

<h2>❓ Additional Assistance</h2>
<p>
  These scripts are fully customizable to fit your unique requirements. For more information on setup or assistance with specific tools, refer to the included <code>README.md</code> or the detailed documentation available in each subfolder.
</p>

<div align="center">
  <a href="mailto:luizhamilton.lhr@gmail.com" target="_blank" rel="noopener noreferrer">
    <img src="https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail" alt="Email Badge">
  </a>
  <a href="https://www.patreon.com/c/brazilianscriptguy" target="_blank" rel="noopener noreferrer">
    <img src="https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge&logo=patreon" alt="Support on Patreon Badge">
  </a>
  <a href="https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c" target="_blank" rel="noopener noreferrer">
    <img src="https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp" alt="WhatsApp Badge">
  </a>
  <a href="https://github.com/brazilianscriptguy/BlueTeam-Tools/issues" target="_blank" rel="noopener noreferrer">
    <img src="https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github" alt="GitHub Issues Badge">
  </a>
</div>
