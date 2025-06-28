<div>
  <h1>🖥️ Efficient Workstation Management, Configuration, and ITSM Compliance for Windows 10 & 11</h1>
  <p>
    Welcome to the <strong>ITSM-Templates-WKS</strong> repository — a curated suite of 
    <strong>PowerShell and VBScript automation tools</strong> purpose-built for managing and standardizing 
    Microsoft Windows 10 and 11 workstations. These scripts enable IT professionals to automate administrative tasks, 
    enforce ITSM policies, and streamline configuration workflows across the enterprise.
  </p>

  <hr />

  <h2>🌟 Key Features</h2>
  <ul>
    <li><strong>Graphical Interfaces (GUI):</strong> Intuitive interfaces designed for first- and second-level support teams.</li>
    <li><strong>Structured Logging:</strong> All actions are logged in standardized <code>.log</code> files for full traceability.</li>
    <li><strong>CSV Reporting:</strong> Exportable <code>.csv</code> files for audits, reporting, and documentation.</li>
  </ul>

  <hr />

  <h2>📄 Script Overview</h2>

  <h3>Folder: <code>/BeforeJoinDomain/</code></h3>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;"><strong>Script Name</strong></th>
        <th style="padding: 8px;">Purpose</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>ITSM-BeforeJoinDomain.hta</strong></td>
        <td>
          Automates 20 critical pre-domain configurations including registry updates, network reset, desktop and profile preparation, 
          WSUS certificate application, and security settings to ensure workstations meet domain readiness standards.
        </td>
      </tr>
    </tbody>
  </table>

  <h3>Folder: <code>/AfterJoinDomain/</code></h3>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;"><strong>Script Name</strong></th>
        <th style="padding: 8px;">Purpose</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>ITSM-AfterJoinDomain.hta</strong></td>
        <td>
          Finalizes the workstation's domain configuration, including DNS registration, GPO reapplication, user profile imprinting, 
          and offline authentication readiness. Ensures full integration with the domain infrastructure.
        </td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Getting Started</h2>
  <ol>
    <li>
      <strong>Clone the Repository:</strong>
      <pre><code>git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git</code></pre>
    </li>
    <li>
      <strong>Navigate to the Repository:</strong>
      <p>Access <code>Windows-SysAdmin-ProSuite/ITSM-Templates-WKS/</code> to find the scripts.</p>
    </li>
    <li>
      <strong>Review Instructions:</strong>
      <p>Each subfolder includes a <code>README.md</code> with detailed documentation and instructions.</p>
    </li>
    <li>
      <strong>Run the Script:</strong>
      <pre><code>.\ScriptName.ps1</code></pre>
    </li>
    <li>
      <strong>Review Outputs:</strong>
      <p>Logs (<code>.log</code>) and reports (<code>.csv</code>) will be generated in designated folders for review.</p>
    </li>
  </ol>

  <hr />

  <h2>📝 Logging & Reporting</h2>
  <ul>
    <li><strong>Logs:</strong> Script execution is fully documented in <code>.log</code> files.</li>
    <li><strong>Reports:</strong> Summary data and workstation results are exported in <code>.csv</code> format.</li>
  </ul>

  <hr />

  <h2>💡 Optimization Tips</h2>
  <ul>
    <li><strong>Automate Execution:</strong> Use Task Scheduler or GPO to enforce recurring script execution.</li>
    <li><strong>Centralize Results:</strong> Save logs and reports in shared folders for team access and compliance audits.</li>
    <li><strong>Customize as Needed:</strong> Modify the templates to reflect your IT governance and service delivery strategy.</li>
  </ul>

  <hr />

  <h2>📁 Log File Paths</h2>
  <p>All generated logs are stored in <code>C:\ITSM-Logs-WKS\</code>, including:</p>
  <ul>
    <li>Domain ingress activity logs</li>
    <li>DNS registration logs</li>
    <li>User profile imprint logs</li>
  </ul>

  <hr />

  <h2>❓ Need Help?</h2>
  <p style="text-align: justify; font-size: 16px; line-height: 1.6;">
    This project is fully modular and adaptable to your ITSM needs. For assistance or questions, consult the documentation in each folder 
    or reach out using the contact links below.
  </p>

  <div align="center">
    <a href="mailto:luizhamilton.lhr@gmail.com" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail" alt="Email Luiz">
    </a>
    <a href="https://www.patreon.com/brazilianscriptguy" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge&logo=patreon" alt="Support on Patreon">
    </a>
    <a href="https://buymeacoffee.com/brazilianscriptguy" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Support-yellow?style=for-the-badge&logo=buymeacoffee" alt="Buy Me a Coffee">
    </a>
    <a href="https://ko-fi.com/brazilianscriptguy" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Ko--fi-Support%20Me-blue?style=for-the-badge&logo=kofi" alt="Support on Ko-fi">
    </a>
    <a href="https://gofund.me/4599d3e6" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/GoFundMe-Donate-green?style=for-the-badge&logo=gofundme" alt="Donate via GoFundMe">
    </a>
    <a href="https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp" alt="Join WhatsApp Channel">
    </a>
    <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/ISSUE_TEMPLATE/CUSTOM_ISSUE_TEMPLATE.md" 
       target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github" alt="Report Issues on GitHub">
    </a>
  </div>

  <hr />

  <h3>📌 Document Classification</h3>
  <p>This documentation is classified as <strong>RESTRICTED</strong> and intended exclusively for internal use within the organization.</p>
</div>
