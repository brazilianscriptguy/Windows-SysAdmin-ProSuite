<div>
  <h1>🖥️ Efficient Workstation Management, Configuration, and ITSM Compliance on Windows 10 and 11</h1>
  <p>
    Welcome to the <strong>ITSM-Templates-WKS</strong> repository! This curated collection of 
    <strong>VBScript and PowerShell tools</strong> is specifically designed to streamline the management and configuration 
    of Windows 10 and 11 workstations. These tools enhance workflows, ensure consistency, and maintain compliance across 
    the organization, enabling IT professionals to automate essential administrative tasks effectively.
  </p>

  <hr />

  <h2>🌟 Key Features</h2>
  <ul>
    <li><strong>Graphical User Interfaces (GUI):</strong> Simplify operation with intuitive user-friendly interfaces.</li>
    <li><strong>Comprehensive Logs:</strong> Generate transparent <code>.log</code> files for process tracking and troubleshooting.</li>
    <li><strong>Exportable Results:</strong> Automate reporting and auditing with results in <code>.csv</code> format.</li>
  </ul>

  <hr />

  <h2>📄 Script Descriptions</h2>

  <h3>Folder: <code>/UniqueScripts/</code></h3>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;"><strong>Script Name</strong></th>
        <th style="padding: 8px;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>ITSM-DefaultVBSing.vbs</strong></td>
        <td>Automates key configurations to standardize workstation settings and prepare for domain integration.</td>
      </tr>
      <tr>
        <td><strong>ITSM-ModifyREGing.vbs</strong></td>
        <td>Applies registry modifications to align workstation configurations with organizational standards.</td>
      </tr>
    </tbody>
  </table>

  <h3>Folder: <code>/PostIngress/</code></h3>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;"><strong>Script Name</strong></th>
        <th style="padding: 8px;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>ITSM-NewDNSRegistering.vbs</strong></td>
        <td>Updates workstation hostname and domain details in Active Directory DNS servers.</td>
      </tr>
      <tr>
        <td><strong>ITSM-ProfileImprinting.vbs</strong></td>
        <td>Registers user domain profiles after three login cycles to ensure compliance.</td>
      </tr>
    </tbody>
  </table>

  <hr />

<h2>🚀 Getting Started</h2>
  <ol>
      <li>
      <strong>Clone or download the Main Repository:</strong>
      <pre><code>git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git</code></pre>
    </li>
    <li>
      <strong>Navigate to the Repository Folder:</strong>
      <p>Navigate to the <code>Windows-SysAdmin-ProSuite/ITSM-Templates-WKS/</code> directory that contains the desired scripts.</p>
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

  <h2>📝 Logging and Reporting</h2>
  <ul>
    <li><strong>Logs:</strong> Scripts generate <code>.log</code> files to document execution processes and errors.</li>
    <li><strong>Reports:</strong> Results are exported in <code>.csv</code> format for audits and reporting.</li>
  </ul>

  <hr />

  <h2>💡 Tips for Optimization</h2>
  <ul>
    <li><strong>Automate Execution:</strong> Schedule scripts to run periodically using task schedulers for consistent results.</li>
    <li><strong>Centralize Logs and Reports:</strong> Save generated <code>.log</code> and <code>.csv</code> files in shared directories for collaborative analysis and auditing.</li>
    <li><strong>Customize Templates:</strong> Tailor script templates to fit specific organizational workflows and security requirements.</li>
  </ul>

  <hr />

  <p>Explore the <strong>ITSM-Templates-WKS</strong> repository and elevate your workstation management processes. These tools make ITSM compliance and configuration a seamless experience! 🎉</p>

  <hr />

  <h2>📄 Log File Locations</h2>
  <p>Logs are stored in <code>C:\ITSM-Logs-WKS\</code> and include:</p>
  <ul>
    <li>DNS registration logs.</li>
    <li>User profile imprinting logs.</li>
  </ul>

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
  <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/ISSUE_TEMPLATE/CUSTOM_ISSUE_TEMPLATE.md" 
     target="_blank" rel="noopener noreferrer" aria-label="Report Issues on GitHub">
    <img src="https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github" 
         alt="Report Issues on GitHub">
  </a>
</div>

 <hr />
  <h3>Document Classification</h3>
  <p>This document is <strong>RESTRICTED</strong> for internal use within the Company’s network.</p>
</div>
