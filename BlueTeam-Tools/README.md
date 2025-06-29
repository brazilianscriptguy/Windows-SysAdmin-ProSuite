<div>
  <h1>🔵 BlueTeam-Tools Suite</h1>

  <h2>📌 Overview</h2>
  <p>
    The <strong>BlueTeam-Tools Suite</strong> is a curated collection of forensic-grade PowerShell utilities designed for
    <strong>Cybersecurity Analysts</strong>, <strong>Blue Team operators</strong>, and <strong>Incident Responders</strong>. These tools support 
    real-time threat detection, anomaly investigation, and security policy enforcement across Windows environments.
  </p>

  <ul>
    <li>🔍 <strong>Forensics Automation:</strong> Extract event logs, registry data, network sessions, user activity, and volatile system states.</li>
    <li>🛡️ <strong>Incident Response:</strong> Assist in evidence collection, log correlation, and secure reporting during live attacks.</li>
    <li>📈 <strong>Security Visibility:</strong> Ensure policy compliance, audit system configurations, and generate actionable CSV reports.</li>
  </ul>

  <hr />

  <h2>🧩 Script Categories & Structure</h2>

  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;">📂 Category</th>
        <th style="padding: 8px;">Description</th>
        <th style="padding: 8px;">Link</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>EventLogMonitoring</strong></td>
        <td>Audit security logs and monitor high-risk system events (e.g., login failures, privilege escalations).</td>
        <td>
          <a href="EventLogMonitoring/README.md" target="_blank">
            <img src="https://img.shields.io/badge/View%20Docs-EventLogMonitoring-blue?style=for-the-badge&logo=github" alt="EventLogMonitoring Badge">
          </a>
        </td>
      </tr>
      <tr>
        <td><strong>IncidentResponse</strong></td>
        <td>Capture and analyze volatile artifacts: active sessions, system metadata, threat indicators.</td>
        <td>
          <a href="IncidentResponse/README.md" target="_blank">
            <img src="https://img.shields.io/badge/View%20Docs-IncidentResponse-blue?style=for-the-badge&logo=github" alt="IncidentResponse Badge">
          </a>
        </td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🛠️ Requirements</h2>
  <ul>
    <li><strong>⚙️ PowerShell:</strong> Version 5.1 or later (<code>$PSVersionTable.PSVersion</code>)</li>
    <li><strong>🖥️ RSAT Tools:</strong> Required for AD, DNS, DHCP support
      <br><code>Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online</code>
    </li>
    <li><strong>🔐 Admin Rights:</strong> Most scripts require elevated privileges</li>
    <li><strong>🧾 Execution Policy:</strong>
      <br><code>Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process</code>
    </li>
    <li><strong>📦 Required Modules:</strong> Ensure <code>ActiveDirectory</code>, <code>Defender</code>, <code>DHCPServer</code> (where applicable)</li>
  </ul>

  <hr />

  <h2>🚀 Getting Started</h2>
  <ol>
    <li>
      <strong>Clone the Repository:</strong>
      <pre><code>git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git</code></pre>
    </li>
    <li>
      <strong>Navigate to BlueTeam Suite:</strong>
      <pre><code>cd Windows-SysAdmin-ProSuite/BlueTeam-Tools/</code></pre>
    </li>
    <li>
      <strong>Explore Script Categories:</strong>
      <p>Open the relevant folder and review its <code>README.md</code> for specific guidance.</p>
    </li>
    <li>
      <strong>Run the Script:</strong>
      <pre><code>.\Your-Script-Name.ps1</code></pre>
    </li>
    <li>
      <strong>Review Output:</strong>
      <p>Each script generates <code>.log</code> and <code>.csv</code> files for traceability and analysis.</p>
    </li>
  </ol>

  <hr />

  <h2>📦 Features at a Glance</h2>
  <ul>
    <li>📂 Organized Logs: All scripts output to well-structured folders with timestamped logs.</li>
    <li>🧠 Intelligent Filters: Reduce noise using smart regex, PowerShell event selectors, and known IOCs.</li>
    <li>🎛️ GUI-Ready: Several scripts include GUI front-ends built with Windows Forms for ease of use.</li>
    <li>🔗 Interoperable: Can be chained into IR pipelines, GPOs, or task schedulers.</li>
  </ul>

  <hr />

  <h2>📬 Contact & Support</h2>
  <div align="center">
    <a href="mailto:luizhamilton.lhr@gmail.com" target="_blank">
      <img src="https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail" alt="Email">
    </a>
    <a href="https://patreon.com/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/Support-Patreon-red?style=for-the-badge&logo=patreon" alt="Patreon">
    </a>
    <a href="https://buymeacoffee.com/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge&logo=buymeacoffee" alt="Coffee">
    </a>
    <a href="https://ko-fi.com/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/Ko--fi-Support-blue?style=for-the-badge&logo=kofi" alt="Ko-fi">
    </a>
    <a href="https://gofundme.com/f/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/GoFundMe-Donate-green?style=for-the-badge&logo=gofundme" alt="GoFundMe">
    </a>
    <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/issues" target="_blank">
      <img src="https://img.shields.io/badge/Report%20Issue-GitHub-blue?style=for-the-badge&logo=github" alt="Issues">
    </a>
    <a href="https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c" target="_blank">
      <img src="https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp" alt="WhatsApp Channel">
    </a>
  </div>
</div>
