<div>
  <h1>📂 Core-ScriptLibrary Folder</h1>
  <p>
    Welcome to the <strong>Core-ScriptLibrary</strong>! This collection includes essential 
    <strong>PowerShell scripts</strong> designed to simplify the creation, execution, and management of custom script libraries. 
    By focusing on dynamic user interfaces, automation, and robust functionality, these tools provide a solid foundation for building efficient and maintainable PowerShell-based solutions.
  </p>

  <hr />

  <h2>🌟 Key Features</h2>
  <ul>
    <li><strong>User-Friendly GUIs:</strong> Enhance user interaction with intuitive graphical interfaces.</li>
    <li><strong>Standardized Logging:</strong> Maintain consistent, traceable logs for improved debugging and auditing.</li>
    <li><strong>Exportable Results:</strong> Generate actionable <code>.CSV</code> outputs for streamlined analysis and reporting.</li>
    <li><strong>Efficient Automation:</strong> Quickly build and deploy PowerShell libraries with reusable templates.</li>
  </ul>

  <hr />

  <h2>📄 Script Descriptions</h2>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;">Script Name</th>
        <th style="padding: 8px;">Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>Create-Script-DefaultHeader.ps1</strong></td>
        <td>Generates standardized headers for PowerShell scripts, ensuring uniformity and best practices.</td>
      </tr>
      <tr>
        <td><strong>Create-Script-LoggingMethod.ps1</strong></td>
        <td>Implements a standardized logging mechanism to enhance traceability and debugging.</td>
      </tr>
      <tr>
        <td><strong>Create-Script-MainStructure-Core.ps1</strong></td>
        <td>Provides a reusable template for creating structured PowerShell scripts with headers, logging, and modular functionality.</td>
      </tr>
      <tr>
        <td><strong>Extract-Script-Headers.ps1</strong></td>
        <td>Extracts headers from <code>.ps1</code> files and organizes them into folder-specific <code>.txt</code> files for easy documentation.</td>
      </tr>
      <tr>
        <td><strong>Launch-Script-AutomaticMenu.ps1</strong></td>
        <td>Serves as a dynamic GUI launcher for browsing and executing PowerShell scripts organized in folder tabs.</td>
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
      <p>Navigate to the <code>Windows-SysAdmin-ProSuite/Core-ScriptLibrary/</code> directory that contains the desired scripts.</p>
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
    <li><strong>Logs:</strong> Scripts generate <code>.log</code> files that document executed actions and errors encountered.</li>
    <li><strong>Reports:</strong> Some scripts produce <code>.csv</code> files for detailed analysis and auditing.</li>
  </ul>

  <hr />

  <h2>💡 Tips for Optimization</h2>
  <ul>
    <li><strong>Automate Execution:</strong> Schedule your scripts to run periodically for consistent results.</li>
    <li><strong>Centralize Logs and Reports:</strong> Save <code>.log</code> and <code>.csv</code> files in shared directories for collaborative analysis.</li>
    <li><strong>Customize Templates:</strong> Tailor script templates to align with your specific workflows and organizational needs.</li>
  </ul>

  <hr />

  <p>Explore the <strong>Core-ScriptLibrary</strong> and streamline your PowerShell scripting experience. These tools are crafted to make creating, managing, and automating workflows a breeze. Enjoy! 🎉</p>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>🖥️ Remote Server Administration Tools (RSAT):</strong>
      <p>Install RSAT components for managing AD, DNS, DHCP, and other server roles.</p>
      <pre><code>Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online</code></pre>
    </li>
    <li>
      <strong>⚙️ PowerShell Version:</strong>
      <p>Use PowerShell 5.1 or later. Verify your version:</p>
      <pre><code>$PSVersionTable.PSVersion</code></pre>
    </li>
    <li><strong>🔑 Administrator Privileges:</strong> Scripts require elevated permissions to perform administrative tasks.</li>
    <li>
      <strong>🔧 Execution Policy:</strong>
      <p>Temporarily allow script execution with:</p>
      <pre><code>Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process</code></pre>
    </li>
    <li>
      <strong>📦 Dependencies:</strong>
      <p>Ensure all required software components and modules (e.g., <code>ActiveDirectory</code>, <code>DHCPServer</code>) are installed.</p>
    </li>
  </ol>

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
