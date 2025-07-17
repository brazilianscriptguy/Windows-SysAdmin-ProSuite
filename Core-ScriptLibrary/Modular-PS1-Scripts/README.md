<div>
  <h1>📂 Core-ScriptLibrary Suite</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>Core-ScriptLibrary Folder</strong> contains foundational <strong>PowerShell scripts</strong> designed for 
    building robust, reusable script modules and GUI-driven tools. These scripts serve as templates and scaffolds 
    for automating administrative tasks, improving code consistency, and streamlining the development of operational toolkits.
  </p>

  <ul>
    <li><strong>📦 Reusable Components:</strong> Ideal for crafting modular scripts with standardized structure.</li>
    <li><strong>🎛️ Dynamic Menus:</strong> GUI-based launchers help centralize script execution.</li>
    <li><strong>🪵 Unified Logging:</strong> Scripts generate <code>.log</code> files for traceability and error tracking.</li>
    <li><strong>📊 Export Reports:</strong> Where applicable, outputs in <code>.csv</code> for reporting and automation pipelines.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell Version:</strong>
      <p>Ensure you're using PowerShell 5.1 or later.</p>
      <pre><code>$PSVersionTable.PSVersion</code></pre>
    </li>
    <li>
      <strong>🔑 Administrator Privileges:</strong>
      <p>Required to run scripts that modify system configurations or access protected paths.</p>
    </li>
    <li>
      <strong>🖥️ Remote Server Administration Tools (RSAT):</strong>
      <p>Install RSAT to support Active Directory, DNS, and DHCP modules if used by other templates.</p>
      <pre><code>Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online</code></pre>
    </li>
    <li>
      <strong>🔧 Execution Policy:</strong>
      <p>Enable script execution with:</p>
      <pre><code>Set-ExecutionPolicy RemoteSigned -Scope Process</code></pre>
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
        <td><strong>Create-Script-DefaultHeader.ps1</strong></td>
        <td>Generates a standardized PowerShell script header block with version, author, and metadata fields.</td>
      </tr>
      <tr>
        <td><strong>Create-Script-LoggingMethod.ps1</strong></td>
        <td>Implements a universal logging method for consistency across scripts and enhanced debugging.</td>
      </tr>
      <tr>
        <td><strong>Create-Script-MainStructure-Core.ps1</strong></td>
        <td>Creates a structured script scaffold including header, logging, parameters, and function placeholders.</td>
      </tr>
      <tr>
        <td><strong>Extract-PowerSehllScripts-Headers.ps1</strong></td>
        <td>Extracts script header blocks from all <code>.ps1</code> files in a folder and documents them in <code>.txt</code> format.</td>
      </tr>
      <tr>
        <td><strong>Launch-Script-AutomaticMenu.ps1</strong></td>
        <td>Displays an interactive GUI with tabbed folders and launch buttons for categorized PowerShell scripts.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Getting Started</h2>
  <ol>
    <li><strong>Clone or download the repository:</strong>
      <pre><code>git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git</code></pre>
    </li>
    <li><strong>Navigate to:</strong> <code>Windows-SysAdmin-ProSuite/Core-ScriptLibrary/</code></li>
    <li><strong>Read the <code>README.md</code>:</strong> Each subfolder includes documentation on how to use the tool.</li>
    <li><strong>Run scripts via PowerShell:</strong>
      <pre><code>.\ScriptName.ps1</code></pre>
    </li>
    <li><strong>Review logs and output:</strong> Check generated <code>.log</code> and <code>.csv</code> files for script results.</li>
  </ol>

  <hr />

  <h2>📝 Logging and Output</h2>
  <ul>
    <li><strong>📄 Logs:</strong> Execution details and errors are captured in <code>.log</code> files for troubleshooting.</li>
    <li><strong>📊 Reports:</strong> Some templates produce structured data in <code>.csv</code> format.</li>
  </ul>

  <hr />

  <h2>💡 Optimization Tips</h2>
  <ul>
    <li><strong>Automate Deployment:</strong> Use task scheduler or remote execution tools for centralized script rollout.</li>
    <li><strong>Customize Templates:</strong> Modify the default headers and structure to align with your IT standards.</li>
    <li><strong>Centralize Output:</strong> Store log and report files in a network-shared directory.</li>
  </ul>

  <hr />

  <h2>❓ Additional Assistance</h2>
  <p style="text-align: justify; font-size: 16px; line-height: 1.6;">
    These scripting templates are designed to be adapted to your environment. Customize the headers, log formatting, and 
    UI structure as needed. Refer to the <code>README.md</code> files inside each script directory for specific usage examples.
  </p>

  <div align="center" style="margin-top: 20px;">
    <a href="mailto:luizhamilton.lhr@gmail.com" target="_blank">
      <img src="https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail" alt="Email Badge">
    </a>
    <a href="https://patreon.com/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/Patreon-Support-red?style=for-the-badge&logo=patreon" alt="Patreon Badge">
    </a>
    <a href="https://buymeacoffee.com/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge&logo=buymeacoffee" alt="Buy Me Coffee">
    </a>
    <a href="https://ko-fi.com/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/Ko--fi-Support-blue?style=for-the-badge&logo=kofi" alt="Ko-fi Badge">
    </a>
    <a href="https://gofund.me/4599d3e6" target="_blank">
      <img src="https://img.shields.io/badge/GoFundMe-Donate-green?style=for-the-badge&logo=gofundme" alt="GoFundMe Badge">
    </a>
    <a href="https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c" target="_blank">
      <img src="https://img.shields.io/badge/WhatsApp-Join%20Us-25D366?style=for-the-badge&logo=whatsapp" alt="WhatsApp Badge">
    </a>
    <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/issues" target="_blank">
      <img src="https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github" alt="Issues Badge">
    </a>
  </div>
</div>
