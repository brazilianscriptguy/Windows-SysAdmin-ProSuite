<div>
  <h1>🔧 SysAdmin-Tools Suite</h1>
  <p>
    Welcome to the <strong>SysAdmin-Tools</strong> suite — a powerful collection of 
    <strong>PowerShell automation scripts</strong> crafted to streamline and centralize the management of Active Directory (AD), 
    Windows Server roles, network infrastructure, and workstation configurations. These tools simplify complex administrative tasks, 
    improve operational efficiency, and enforce compliance and security across enterprise IT environments.
  </p>

  <hr />

  <h2>🌟 Key Features</h2>
  <ul>
    <li><strong>User-Friendly Interfaces:</strong> All scripts feature an intuitive GUI for ease of use.</li>
    <li><strong>Detailed Logging:</strong> Every execution generates structured <code>.log</code> files for auditing and troubleshooting.</li>
    <li><strong>Exportable Reports:</strong> Many scripts output results in <code>.csv</code> format for easy analysis and integration with analytics tools.</li>
  </ul>

  <hr />

  <h2>📁 Folder Structure and Categories</h2>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: left;">
    <thead>
      <tr>
        <th style="padding: 8px;">Folder</th>
        <th style="padding: 8px;">Description</th>
        <th style="padding: 8px;">Documentation</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>ActiveDirectory-Management</strong></td>
        <td>Tools to manage users, computers, GPOs, and directory synchronization in Active Directory environments.</td>
        <td>
          <a href="ActiveDirectory-Management/README.md" target="_blank">
            <img src="https://img.shields.io/badge/AD%20Management-README-blue?style=for-the-badge&logo=github" alt="AD Management">
          </a>
        </td>
      </tr>
      <tr>
        <td><strong>ActiveDirectory-SSO-Integrations</strong></td>
        <td>Demonstrates multiple integration models for implementing Single Sign-On (SSO) using Active Directory via LDAP protocols.</td>
        <td>
          <a href="ActiveDirectory-SSO-Integrations/README.md" target="_blank">
            <img src="https://img.shields.io/badge/SSO%20Integrations-README-blue?style=for-the-badge&logo=github" alt="SSO Integrations">
          </a>
        </td>
      </tr>
      <tr>
        <td><strong>GroupPolicyObjects-Templates</strong></td>
        <td>Ready-to-import GPO templates for greenfield or migration-ready domain structures.</td>
        <td>
          <a href="GroupPolicyObjects-Templates/README.md" target="_blank">
            <img src="https://img.shields.io/badge/GPO%20Templates-README-blue?style=for-the-badge&logo=github" alt="GPO Templates">
          </a>
        </td>
      </tr>
      <tr>
        <td><strong>Network-and-Infrastructure-Management</strong></td>
        <td>Scripts for managing network services such as DNS, DHCP, and WSUS, ensuring reliable infrastructure health.</td>
        <td>
          <a href="Network-and-Infrastructure-Management/README.md" target="_blank">
            <img src="https://img.shields.io/badge/Network%20Management-README-blue?style=for-the-badge&logo=github" alt="Network Management">
          </a>
        </td>
      </tr>
      <tr>
        <td><strong>Security-and-Process-Optimization</strong></td>
        <td>Security hardening and compliance enforcement tools for Windows environments.</td>
        <td>
          <a href="Security-and-Process-Optimization/README.md" target="_blank">
            <img src="https://img.shields.io/badge/Security%20Optimization-README-blue?style=for-the-badge&logo=github" alt="Security Optimization">
          </a>
        </td>
      </tr>
      <tr>
        <td><strong>SystemConfiguration-and-Deployment</strong></td>
        <td>Deployment and configuration scripts to ensure consistency across Windows systems.</td>
        <td>
          <a href="SystemConfiguration-and-Deployment/README.md" target="_blank">
            <img src="https://img.shields.io/badge/System%20Deployment-README-blue?style=for-the-badge&logo=github" alt="System Deployment">
          </a>
        </td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>🖥️ Remote Server Administration Tools (RSAT):</strong><br>
      Install RSAT components to manage AD, DNS, DHCP, etc.
      <pre><code>Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online</code></pre>
    </li>
    <li>
      <strong>⚙️ PowerShell Version:</strong><br>
      Requires PowerShell 5.1 or later.
      <pre><code>$PSVersionTable.PSVersion</code></pre>
    </li>
    <li><strong>🔑 Administrator Privileges:</strong> Most scripts require elevation to run.</li>
    <li>
      <strong>🔧 Execution Policy:</strong><br>
      Temporarily allow local script execution:
      <pre><code>Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process</code></pre>
    </li>
    <li>
      <strong>📦 Dependencies:</strong><br>
      Ensure required modules like <code>ActiveDirectory</code> and <code>DHCPServer</code> are present.
    </li>
  </ol>

  <hr />

  <h2>🚀 Getting Started</h2>
  <ol>
    <li><strong>Clone the Repository:</strong>
      <pre><code>git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git</code></pre>
    </li>
    <li><strong>Navigate to SysAdmin Tools:</strong>
      <p>Go to <code>Windows-SysAdmin-ProSuite/SysAdmin-Tools/</code> to find categorized scripts.</p>
    </li>
    <li><strong>Review Documentation:</strong>
      <p>Open each folder’s <code>README.md</code> for specific usage instructions.</p>
    </li>
    <li><strong>Run the Scripts:</strong>
      <p>Execute PowerShell scripts with:</p>
      <pre><code>.\ScriptName.ps1</code></pre>
    </li>
    <li>
      <strong>Review Logs and Reports:</strong><br>
      <p>
        Logs for general administrative scripts are saved in <code>C:\Logs-TEMP\</code> or the current script directory. 
        ITSM tools store logs in <code>C:\ITSM-Logs-WKS\</code> (for workstations) or <code>C:\ITSM-Logs-SVR\</code> (for servers). 
        Review <code>.log</code> files for diagnostic output and <code>.csv</code> files for reporting.
      </p>
    </li>
  </ol>

  <hr />

  <h2>📝 Logging and Reporting</h2>
  <ul>
    <li><strong>Logs:</strong> Every script outputs <code>.log</code> files with detailed execution information.</li>
    <li><strong>Reports:</strong> Many tools generate <code>.csv</code> files for data analysis and compliance audits.</li>
  </ul>

  <hr />

  <h2>❓ Support & Customization</h2>
  <p style="text-align: justify; font-size: 16px; line-height: 1.6;">
    All scripts are modular and customizable to fit your unique enterprise needs. For implementation guidance or troubleshooting, 
    refer to each folder’s <code>README.md</code> or reach out via the support channels below.
  </p>

  <div align="center">
    <a href="mailto:luizhamilton.lhr@gmail.com" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail" alt="Email Badge">
    </a>
    <a href="https://www.patreon.com/brazilianscriptguy" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Support%20Me-Patreon-red?style=for-the-badge&logo=patreon" alt="Patreon Badge">
    </a>
    <a href="https://buymeacoffee.com/brazilianscriptguy" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-yellow?style=for-the-badge&logo=buymeacoffee" alt="BuyMeACoffee Badge">
    </a>
    <a href="https://ko-fi.com/brazilianscriptguy" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Ko--fi-Support%20Me-blue?style=for-the-badge&logo=kofi" alt="Ko-fi Badge">
    </a>
    <a href="https://gofund.me/4599d3e6" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/GoFundMe-Donate-green?style=for-the-badge&logo=gofundme" alt="GoFundMe Badge">
    </a>
    <a href="https://whatsapp.com/channel/0029VaEgqC50G0XZV1k4Mb1c" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Join%20Us-WhatsApp-25D366?style=for-the-badge&logo=whatsapp" alt="WhatsApp Badge">
    </a>
    <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/ISSUE_TEMPLATE/CUSTOM_ISSUE_TEMPLATE.md" 
       target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Report%20Issues-GitHub-blue?style=for-the-badge&logo=github" alt="Report Issues Badge">
    </a>
  </div>

  <p style="text-align: center; font-size: 16px; margin-top: 20px;">
    © 2025 Luiz Hamilton. All rights reserved.
  </p>
</div>
