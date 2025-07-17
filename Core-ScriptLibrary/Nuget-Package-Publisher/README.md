<div>
  <h1>📂 NuGet Package Publisher Suite</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>NuGet Package Publisher Suite</strong> is a specialized <strong>PowerShell script</strong> (named <code>Generate-NuGet-Package.ps1</code>) designed to automate the creation, validation, and publication of NuGet packages to GitHub Packages. This script provides a GUI-driven interface and reusable components to streamline the packaging process for Windows system administrators and developers.
  </p>

  <ul>
    <li><strong>📦 Package Automation:</strong> Simplifies building and publishing NuGet packages with dynamic versioning.</li>
    <li><strong>🎛️ GUI Interface:</strong> Offers an interactive GUI for configuring package metadata and execution.</li>
    <li><strong>🪵 Detailed Logging:</strong> Generates <code>.log</code> files for tracking the packaging process and errors.</li>
    <li><strong>📊 Artifact Reports:</strong> Produces <code>.txt</code> reports for package details and verification.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>⚙️ PowerShell Version:</strong>
      <p>Requires PowerShell 5.1 or later for GUI and core functionality.</p>
      <pre><code>$PSVersionTable.PSVersion</code></pre>
    </li>
    <li>
      <strong>🔑 Administrator Privileges:</strong>
      <p>Necessary for file operations and publishing to GitHub Packages.</p>
    </li>
    <li>
      <strong>🔧 NuGet CLI:</strong>
      <p>Install <code>nuget.exe</code> and place it in the script directory or add to PATH. Download from <a href="https://www.nuget.org/downloads" target="_blank">nuget.org</a>.</p>
      <pre><code>Test-Path (Join-Path $ScriptDir "nuget.exe")</code></pre>
    </li>
    <li>
      <strong>🔑 GitHub Personal Access Token (PAT):</strong>
      <p>Generate a PAT with <code>package:write</code> scope for publishing to GitHub Packages.</p>
    </li>
    <li>
      <strong>🔧 Execution Policy:</strong>
      <p>Enable script execution with:</p>
      <pre><code>Set-ExecutionPolicy RemoteSigned -Scope Process</code></pre>
    </li>
  </ol>

  <hr />

  <h2>📂 Folder Structure</h2>
  <p>The NuGet Package Publisher Suite requires a specific folder structure to function effectively. Below is the recommended layout within <code>Windows-SysAdmin-ProSuite/Core-ScriptLibrary/Nuget-Package-Publisher/</code>:</p>
  <ul style="font-size: 16px; line-height: 1.8;">
    <li><strong><code>Generate-NuGet-Package.ps1</code>:</strong> The main PowerShell script file, containing the automation logic and GUI interface.</li>
    <li><strong><code>config.json</code> (optional):</strong> A configuration file for storing package metadata (e.g., package ID, version, description) and PAT. Place this in the root folder for easy access.</li>
    <li><strong><code>artifacts/</code>:</strong> A subdirectory to store generated NuGet packages (e.g., `.nupkg` files) and reports (e.g., `NuGetReport_*.txt`). Create this folder manually or let the script generate it.</li>
    <li><strong><code>$env:LOCALAPPDATA\NuGetPublisher\Logs/</code>:</strong> The default log directory for storing execution logs (e.g., `Generate-NuGet-Package-*.log`). Ensure this path is writable.</li>
    <li><strong><code>nuget.exe</code> (optional):</strong> Place the NuGet CLI executable in the root folder for local execution, or rely on system PATH.</li>
  </ul>

  <hr />

  <h2>📄 Script Description</h2>
  <table border="1" style="border-collapse: collapse; width: 100%;">
    <thead>
      <tr>
        <th style="padding: 8px;">Script Name</th>
        <th style="padding: 8px;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>Generate-NuGet-Package.ps1</strong></td>
        <td>
          Automates the creation and publication of NuGet packages. It features a GUI for configuring package settings, validates package integrity, and publishes to GitHub Packages with logging and reporting capabilities.
        </td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Getting Started</h2>
  <ol>
    <li><strong>Clone or download the repository:</strong>
      <pre><code>git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git</code></pre>
    </li>
    <li><strong>Navigate to:</strong> <code>Windows-SysAdmin-ProSuite/Core-ScriptLibrary/Nuget-Package-Publisher/</code></li>
    <li><strong>Install NuGet CLI:</strong> Place <code>nuget.exe</code> in the folder or add to PATH.</li>
    <li><strong>Set up folder structure:</strong> Ensure the <code>artifacts</code> folder exists and the log directory (<code>$env:LOCALAPPDATA\NuGetPublisher\Logs</code>) is accessible.</li>
    <li><strong>Run the script via PowerShell:</strong>
      <pre><code>.\Generate-NuGet-Package.ps1</code></pre>
    </li>
    <li><strong>Review logs and artifacts:</strong> Check <code>$env:LOCALAPPDATA\NuGetPublisher\Logs</code> and the <code>artifacts</code> folder in your root directory.</li>
  </ol>

  <hr />

  <h2>📝 Logging and Output</h2>
  <ul>
    <li><strong>📄 Logs:</strong> Detailed execution logs are saved to <code>$env:LOCALAPPDATA\NuGetPublisher\Logs</code> within the folder structure.</li>
    <li><strong>📊 Reports:</strong> Generates <code>NuGetReport_*.txt</code> files in the <code>artifacts</code> directory.</li>
  </ul>

  <hr />

  <h2>💡 Optimization Tips</h2>
  <ul>
    <li><strong>Automate Publishing:</strong> Schedule the script with Task Scheduler for regular package updates, using the folder structure for consistency.</li>
    <li><strong>Customize Metadata:</strong> Adjust package ID, tags, and description in the GUI or <code>config.json</code> within the root folder.</li>
    <li><strong>Centralize Artifacts:</strong> Store the <code>artifacts</code> folder in a shared network location for team access.</li>
  </ul>

  <hr />

  <h2>❓ Additional Assistance</h2>
  <p style="text-align: justify; font-size: 16px; line-height: 1.6;">
    The <code>Generate-NuGet-Package.ps1</code> script is designed to be flexible for various repository structures. Customize the GUI settings or configuration file as needed. Refer to the script's inline comments or contact the author for specific guidance.
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
