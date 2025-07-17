<div>
  <h1>🔧 Core Script Library</h1>
  <p style="text-align: justify; font-size: 16px; line-height: 1.8;">
    Welcome to the <strong>Core Script Library</strong> — a robust collection of <strong>PowerShell automation scripts</strong> designed to enhance system administration and development workflows within the Windows-SysAdmin-ProSuite. This library includes modular scripts and NuGet package publishing tools to streamline administrative tasks, improve code reusability, and facilitate package distribution.
  </p>

  <hr />

  <h2>🌟 Key Features</h2>
  <ul style="font-size: 16px; line-height: 1.8;">
    <li><strong>User-Friendly Interfaces:</strong> Scripts offer intuitive GUIs for ease of use and configuration.</li>
    <li><strong>Detailed Logging:</strong> Execution details are captured in <code>.log</code> files for auditing and troubleshooting.</li>
    <li><strong>Exportable Outputs:</strong> Generates <code>.csv</code> or <code>.txt</code> reports for analysis and integration.</li>
  </ul>

  <hr />

  <h2>📁 Folder Structure and Categories</h2>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left; font-size: 15px;">
    <thead>
      <tr>
        <th style="padding: 8px;">Folder</th>
        <th style="padding: 8px;">Description</th>
        <th style="padding: 8px;">Documentation</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>Modular-PS1-Scripts</strong></td>
        <td>Contains foundational PowerShell scripts for building reusable modules, GUI-driven tools, and standardized administrative templates.</td>
        <td>
          <a href="Modular-PS1-Scripts/README.md" target="_blank">
            <img src="https://img.shields.io/badge/Modular%20Scripts-README-blue?style=for-the-badge&logo=github" alt="Modular Scripts">
          </a>
        </td>
      </tr>
      <tr>
        <td><strong>Nuget-Package-Publisher</strong></td>
        <td>Hosts the <code>Generate-NuGet-Package.ps1</code> script, which automates the creation, validation, and publication of NuGet packages to GitHub Packages with a GUI interface.</td>
        <td>
          <a href="Nuget-Package-Publisher/README.md" target="_blank">
            <img src="https://img.shields.io/badge/NuGet%20Publisher-README-blue?style=for-the-badge&logo=github" alt="NuGet Publisher">
          </a>
        </td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol style="font-size: 16px; line-height: 1.8;">
    <li>
      <strong>🖥️ PowerShell Version:</strong><br>
      Requires PowerShell 5.1 or later for full functionality.
      <pre><code>$PSVersionTable.PSVersion</code></pre>
    </li>
    <li><strong>🔑 Administrator Privileges:</strong> Necessary for file operations and package publishing.</li>
    <li>
      <strong>🔧 NuGet CLI (for Nuget-Package-Publisher):</strong><br>
      Install <code>nuget.exe</code> and place it in the script directory or add to PATH. Download from <a href="https://www.nuget.org/downloads" target="_blank">nuget.org</a>.
      <pre><code>Test-Path (Join-Path $ScriptDir "nuget.exe")</code></pre>
    </li>
    <li>
      <strong>🔧 Execution Policy:</strong><br>
      Enable script execution with:
      <pre><code>Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process</code></pre>
    </li>
  </ol>

  <hr />

  <h2>🚀 Getting Started</h2>
  <ol style="font-size: 16px; line-height: 1.8;">
    <li><strong>Clone the Repository:</strong>
      <pre><code>git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git</code></pre>
    </li>
    <li><strong>Navigate to Core Script Library:</strong>
      <p>Go to <code>Windows-SysAdmin-ProSuite/Core-ScriptLibrary/</code> to access the subfolders.</p>
    </li>
    <li><strong>Review Documentation:</strong>
      <p>Explore each subfolder’s <code>README.md</code> for detailed usage instructions.</p>
    </li>
    <li><strong>Run the Scripts:</strong>
      <pre><code>.\ScriptName.ps1</code></pre>
    </li>
    <li><strong>Review Logs and Artifacts:</strong>
      <p>
        Logs for <code>Modular-PS1-Scripts</code> are in <code>$env:LOCALAPPDATA\NuGetPublisher\Logs</code>.<br>
        Artifacts for <code>Nuget-Package-Publisher</code> are in the <code>artifacts</code> folder of your root directory.
      </p>
    </li>
  </ol>

  <hr />

  <h2>📝 Logging and Reporting</h2>
  <ul style="font-size: 16px; line-height: 1.8;">
    <li><strong>Logs:</strong> Detailed execution logs are saved for both subfolders, typically in <code>$env:LOCALAPPDATA\NuGetPublisher\Logs</code>.</li>
    <li><strong>Reports:</strong> <code>Nuget-Package-Publisher</code> generates <code>NuGetReport_*.txt</code> files; <code>Modular-PS1-Scripts</code> may produce <code>.csv</code> outputs where applicable.</li>
  </ul>

  <hr />

  <h2>❓ Support & Customization</h2>
  <p style="text-align: justify; font-size: 16px; line-height: 1.8;">
    The scripts in this library are designed for adaptability to various IT environments. Customize configurations and GUIs as needed. For support or troubleshooting, refer to each subfolder’s <code>README.md</code> or use the channels below.
  </p>

  <div align="center" style="margin-top: 15px; display: flex; flex-wrap: wrap; justify-content: center; gap: 12px;">
    <a href="mailto:luizhamilton.lhr@gmail.com" target="_blank">
      <img src="https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail" alt="Email">
    </a>
    <a href="https://www.patreon.com/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge&logo=patreon" alt="Patreon">
    </a>
    <a href="https://buymeacoffee.com/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge&logo=buymeacoffee" alt="BuyMeCoffee">
    </a>
    <a href="https://ko-fi.com/brazilianscriptguy" target="_blank">
      <img src="https://img.shields.io/badge/Ko--fi-Support%20Me-blue?style=for-the-badge&logo=kofi" alt="Ko-fi">
    </a>
    <a href="https://gofund.me/4599d3e6" target="_blank">
      <img src="https://img.shields.io/badge/GoFundMe-Donate-green?style=for-the-badge&logo=gofundme" alt="GoFundMe">
    </a>
    <a href="https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c" target="_blank">
      <img src="https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp" alt="WhatsApp">
    </a>
    <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/ISSUE_TEMPLATE/CUSTOM_ISSUE_TEMPLATE.md" target="_blank">
      <img src="https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github" alt="GitHub Issues">
    </a>
  </div>

  <p style="text-align: center; font-size: 16px; margin-top: 20px;">
    © 2025 Luiz Hamilton. All rights reserved.
  </p>
</div>
