<div>
  <h1>🔧 Core Script Library</h1>
  <p style="text-align: justify; font-size: 16px; line-height: 1.8;">
    Welcome to the <strong>Core Script Library</strong>, a cornerstone of the <strong>Windows-SysAdmin-ProSuite</strong> repository located at <code>Windows-SysAdmin-ProSuite/Core-ScriptLibrary/</code>. This library introduces two essential subfolders: <strong>Modular-PS1-Scripts</strong> and <strong>Nuget-Package-Publisher</strong>. These subfolders provide a powerful set of <strong>PowerShell automation scripts</strong> designed to enhance system administration, streamline development workflows, and facilitate NuGet package distribution.
  </p>

  <hr />

  <h2>🌟 Key Features</h2>
  <ul style="font-size: 16px; line-height: 1.8;">
    <li><strong>User-Friendly Interfaces:</strong> Both subfolders offer intuitive GUIs for ease of use and configuration.</li>
    <li><strong>Detailed Logging:</strong> Execution details are captured in <code>.log</code> files for auditing and troubleshooting.</li>
    <li><strong>Exportable Outputs:</strong> Generates <code>.csv</code> or <code>.txt</code> reports for analysis and integration.</li>
  </ul>

  <hr />

  <h2>📁 Introducing the Subfolders</h2>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left; font-size: 15px;">
    <thead>
      <tr>
        <th style="padding: 8px;">Subfolder</th>
        <th style="padding: 8px;">Purpose</th>
        <th style="padding: 8px;">Documentation</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>Modular-PS1-Scripts</strong></td>
        <td>Offers foundational PowerShell scripts as templates and scaffolds for automating administrative tasks, featuring reusable components, dynamic GUI menus, and unified logging for operational efficiency.</td>
        <td>
          <a href="Modular-PS1-Scripts/README.md" target="_blank">
            <img src="https://img.shields.io/badge/Modular%20Scripts-README-blue?style=for-the-badge&logo=github" alt="Modular Scripts">
          </a>
        </td>
      </tr>
      <tr>
        <td><strong>Nuget-Package-Publisher</strong></td>
        <td>Introduces the <code>Generate-NuGet-Package.ps1</code> script, automating the creation, validation, and publication of NuGet packages to GitHub Packages with a comprehensive GUI interface.</td>
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
    <li><strong>🔑 Administrator Privileges:</strong> Necessary for file operations, system modifications, and package publishing.</li>
    <li>
      <strong>🖥️ Remote Server Administration Tools (RSAT) (for Modular-PS1-Scripts):</strong><br>
      Install RSAT to support Active Directory, DNS, and DHCP modules if used by templates.
      <pre><code>Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online</code></pre>
    </li>
    <li>
      <strong>🔧 NuGet CLI (for Nuget-Package-Publisher):</strong><br>
      Install <code>nuget.exe</code> and place it in the script directory or add to PATH. Download from <a href="https://www.nuget.org/downloads" target="_blank">nuget.org</a>.
      <pre><code>Test-Path (Join-Path $ScriptDir "nuget.exe")</code></pre>
    </li>
    <li>
      <strong>🔑 GitHub Personal Access Token (PAT) (for Nuget-Package-Publisher):</strong><br>
      Generate a PAT with <code>package:write</code> scope for publishing to GitHub Packages.
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
      <p>Go to <code>Windows-SysAdmin-ProSuite/Core-ScriptLibrary/</code> to explore the subfolders.</p>
    </li>
    <li><strong>Review Documentation:</strong>
      <p>Check each subfolder’s <code>README.md</code> for detailed instructions on usage.</p>
    </li>
    <li><strong>Run the Scripts:</strong>
      <pre><code>.\ScriptName.ps1</code></pre>
    </li>
    <li><strong>Review Logs and Artifacts:</strong>
      <p>
        Logs for <code>Modular-PS1-Scripts</code> are in the script's working directory.<br>
        Artifacts for <code>Nuget-Package-Publisher</code> are in the <code>artifacts</code> folder and logs in <code>$env:LOCALAPPDATA\NuGetPublisher\Logs</code>.
      </p>
    </li>
  </ol>

  <hr />

  <h2>📝 Logging and Reporting</h2>
  <ul style="font-size: 16px; line-height: 1.8;">
    <li><strong>Logs:</strong> <code>Modular-PS1-Scripts</code> saves execution details in <code>.log</code> files; <code>Nuget-Package-Publisher</code> logs to <code>$env:LOCALAPPDATA\NuGetPublisher\Logs</code>.</li>
    <li><strong>Reports:</strong> <code>Modular-PS1-Scripts</code> may produce <code>.csv</code> files; <code>Nuget-Package-Publisher</code> generates <code>NuGetReport_*.txt</code> files.</li>
  </ul>

  <hr />

  <h2>💡 Optimization Tips</h2>
  <ul style="font-size: 16px; line-height: 1.8;">
    <li><strong>Automate Deployment (Modular-PS1-Scripts):</strong> Use Task Scheduler or remote execution for centralized rollout.</li>
    <li><strong>Customize Templates (Modular-PS1-Scripts):</strong> Adapt headers and structures to your IT standards.</li>
    <li><strong>Centralize Output (Modular-PS1-Scripts):</strong> Store logs and reports in a network-shared directory.</li>
    <li><strong>Automate Publishing (Nuget-Package-Publisher):</strong> Schedule <code>Generate-NuGet-Package.ps1</code> with Task Scheduler.</li>
    <li><strong>Customize Metadata (Nuget-Package-Publisher):</strong> Adjust package settings via GUI or <code>config.json</code>.</li>
    <li><strong>Centralize Artifacts (Nuget-Package-Publisher):</strong> Store artifacts in a shared network location.</li>
  </ul>

  <hr />

  <h2>❓ Support & Customization</h2>
  <p style="text-align: justify; font-size: 16px; line-height: 1.8;">
    The scripts in this library are designed for adaptability across IT environments. For guidance or troubleshooting, refer to each subfolder’s <code>README.md</code> or contact us below.
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
