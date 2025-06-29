<div>
  <h1>📂 Core-ScriptLibrary: Reusable PowerShell Frameworks</h1>

  <h2>🧰 Overview</h2>
  <p>
    The <strong>Core-ScriptLibrary</strong> is a foundational suite of <strong>PowerShell scripting templates</strong> and 
    <strong>automation tools</strong> crafted for rapid deployment, modularity, and GUI integration. Designed to enhance script 
    reusability, logging consistency, and operational standardization across your administrative toolsets.
  </p>

  <ul>
    <li>🎛️ <strong>GUI Support:</strong> Dynamic forms and menu-based GUIs simplify interaction and reduce script errors.</li>
    <li>🪵 <strong>Logging Framework:</strong> Standardized <code>.log</code> generation for troubleshooting and diagnostics.</li>
    <li>📊 <strong>Export Templates:</strong> Built-in support for <code>.csv</code> outputs for structured reporting.</li>
    <li>🧱 <strong>Script Scaffolding:</strong> Template generators to unify your PowerShell codebase.</li>
  </ul>

  <hr />

  <h2>📄 Script Descriptions</h2>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;">Script</th>
        <th style="padding: 8px;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>Create-Script-DefaultHeader.ps1</strong></td>
        <td>Generates pre-filled headers for PowerShell scripts including versioning, authorship, and license metadata.</td>
      </tr>
      <tr>
        <td><strong>Create-Script-LoggingMethod.ps1</strong></td>
        <td>Implements standardized logging blocks and helper functions for consistent diagnostics across scripts.</td>
      </tr>
      <tr>
        <td><strong>Create-Script-MainStructure-Core.ps1</strong></td>
        <td>Provides a complete PowerShell template: includes banner, logging, parameters, and modular sections.</td>
      </tr>
      <tr>
        <td><strong>Extract-Script-Headers.ps1</strong></td>
        <td>Scans script folders and extracts script headers to <code>.txt</code> for documentation or inventory purposes.</td>
      </tr>
      <tr>
        <td><strong>Launch-Script-AutomaticMenu.ps1</strong></td>
        <td>Displays an interactive GUI to browse and launch categorized scripts — ideal for technician toolkits.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 How to Use</h2>
  <ol>
    <li><strong>Clone the Repository:</strong>
      <pre><code>git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git</code></pre>
    </li>
    <li><strong>Navigate to the Tools:</strong> Go to <code>/Core-ScriptLibrary/</code>.</li>
    <li><strong>Review Documentation:</strong> Each folder includes a <code>README.md</code> for context and examples.</li>
    <li><strong>Run Scripts:</strong> Execute via:
      <pre><code>.\ScriptName.ps1</code></pre>
    </li>
    <li><strong>Inspect Output:</strong> Check <code>.log</code> and <code>.csv</code> files in the script's folder.</li>
  </ol>

  <hr />

  <h2>📝 Logging and Reporting</h2>
  <ul>
    <li><strong>📄 Logs:</strong> All execution steps and errors are written to <code>.log</code> files.</li>
    <li><strong>📊 CSV Reports:</strong> Where applicable, data is exported in <code>.csv</code> for reporting or audits.</li>
  </ul>

  <hr />

  <h2>💡 Optimization Tips</h2>
  <ul>
    <li><strong>Automate Menu Launchers:</strong> Pin GUI launchers for technician accessibility.</li>
    <li><strong>Customize Template Headers:</strong> Add fields for ticket IDs, asset tags, etc.</li>
    <li><strong>Centralize Output:</strong> Use UNC paths or a shared folder to store logs globally.</li>
  </ul>

  <hr />

  <h2>🛠️ Requirements</h2>
  <ol>
    <li><strong>PowerShell 5.1+</strong> (or Core where supported)</li>
    <li><strong>Admin Privileges</strong> recommended for most system-level operations</li>
    <li><strong>Execution Policy:</strong>
      <pre><code>Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process</code></pre>
    </li>
    <li><strong>RSAT (If Working with AD Scripts)</strong>:
      <pre><code>Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online</code></pre>
    </li>
  </ol>

  <hr />

  <h2>❓ Support & Contributions</h2>
  <p style="text-align: justify; font-size: 16px; line-height: 1.6;">
    These scripts are built for flexibility. Feel free to modify them to fit your workflow or organizational standard. Contributions are welcome via pull requests, or report any bugs in the <code>Issues</code> section.
  </p>

  <div align="center">
    <a href="mailto:luizhamilton.lhr@gmail.com" target="_blank">
      <img src="https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail">
    </a>
    <a href="https://patreon.com/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/Patreon-Support-red?style=for-the-badge&logo=patreon">
    </a>
    <a href="https://buymeacoffee.com/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/Buy%20Me%20Coffee-yellow?style=for-the-badge&logo=buymeacoffee">
    </a>
    <a href="https://ko-fi.com/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/Ko--fi-Support-blue?style=for-the-badge&logo=kofi">
    </a>
    <a href="https://gofund.me/4599d3e6" target="_blank">
      <img src="https://img.shields.io/badge/GoFundMe-Donate-green?style=for-the-badge&logo=gofundme">
    </a>
    <a href="https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c" target="_blank">
      <img src="https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp">
    </a>
    <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/issues" target="_blank">
      <img src="https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github">
    </a>
  </div>
</div>
