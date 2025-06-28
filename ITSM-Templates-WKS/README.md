<div>
  <h1>🖥️ Efficient Workstation Management, Configuration, and ITSM Compliance for Windows 10 & 11</h1>
  <p>
    Welcome to the <strong>ITSM-Templates-WKS</strong> repository — a curated suite of 
    <strong>PowerShell and VBScript automation tools</strong> purpose-built for managing and standardizing 
    Microsoft Windows 10 and 11 workstations. These scripts help IT teams automate core administrative operations, 
    enforce compliance, and optimize configuration workflows across the organization.
  </p>

  <hr />

  <h2>🌟 Key Features</h2>
  <ul>
    <li><strong>Graphical Interfaces (GUI):</strong> User-friendly execution with accessible graphical input forms.</li>
    <li><strong>Structured Logging:</strong> All operations are logged to structured <code>.log</code> files for full traceability.</li>
    <li><strong>CSV Reporting:</strong> Audit-ready output in <code>.csv</code> format for asset tracking and documentation.</li>
  </ul>

  <hr />

  <h2>📄 Script Overview</h2>

  <h3>Folder: <code>/UniqueScripts/</code></h3>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;"><strong>Script Name</strong></th>
        <th style="padding: 8px;">Purpose</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>ITSM-DefaultVBSing.vbs</strong></td>
        <td>Applies default system settings to prepare the workstation for domain integration.</td>
      </tr>
      <tr>
        <td><strong>ITSM-ModifyREGing.vbs</strong></td>
        <td>Implements registry-level configurations to align the system with corporate policies.</td>
      </tr>
    </tbody>
  </table>

  <h3>Folder: <code>/PostIngress/</code></h3>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;"><strong>Script Name</strong></th>
        <th style="padding: 8px;">Purpose</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>ITSM-NewDNSRegistering.vbs</strong></td>
        <td>Registers the workstation’s hostname and domain metadata with Active Directory DNS.</td>
      </tr>
      <tr>
        <td><strong>ITSM-ProfileImprinting.vbs</strong></td>
        <td>Ensures persistent user profile registration after three domain logon sessions.</td>
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
      <strong>Access the Scripts:</strong>
      <p>Navigate to the <code>Windows-SysAdmin-ProSuite/ITSM-Templates-WKS/</code> directory to find the script set.</p>
    </li>
    <li>
      <strong>Review Instructions:</strong>
      <p>Open the <code>README.md</code> in each subfolder for usage instructions and script details.</p>
    </li>
    <li>
      <strong>Execute:</strong>
      <p>Run PowerShell scripts with:</p>
      <pre><code>.\ScriptName.ps1</code></pre>
    </li>
    <li>
      <strong>Audit Outputs:</strong>
      <p>Check generated <code>.log</code> and <code>.csv</code> files for execution results and diagnostics.</p>
    </li>
  </ol>

  <hr />

  <h2>📝 Logging & Reporting</h2>
  <ul>
    <li><strong>Execution Logs:</strong> All actions are logged to <code>.log</code> files for traceability and auditing.</li>
    <li><strong>Exported Reports:</strong> Script outputs are saved as <code>.csv</code> files to simplify reporting.</li>
  </ul>

  <hr />

  <h2>💡 Optimization Tips</h2>
  <ul>
    <li><strong>Automate Tasks:</strong> Schedule recurring scripts using Task Scheduler or GPO for consistency.</li>
    <li><strong>Centralize Logs:</strong> Use shared directories to store logs and reports for easy collaboration.</li>
    <li><strong>Adapt Templates:</strong> Customize scripts and configurations to meet your organization's unique ITSM strategy.</li>
  </ul>

  <hr />

  <h2>📄 Log File Paths</h2>
  <p>Execution logs are stored in <code>C:\ITSM-Logs-WKS\</code>, including:</p>
  <ul>
    <li>DNS registration logs</li>
    <li>User profile imprint logs</li>
    <li>Domain ingress and system customization logs</li>
  </ul>

  <hr />

  <h2>❓ Need Help?</h2>
  <p style="text-align: justify; font-size: 16px; line-height: 1.6;">
    The scripts in this repository are modular and customizable. For guidance on implementation or 
    troubleshooting, refer to the README files within each subfolder or reach out via the contact options below.
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
  <p>This documentation is <strong>RESTRICTED</strong> for internal use only. Unauthorized distribution or modification outside the organization's network is prohibited.</p>
</div>
