<div align="center">
  <h1>🛡️ Security Policy</h1>
  <p>
    This repository contains enterprise automation toolsets for Windows environments, including PowerShell and VBScript assets.
    Security updates and support are defined below.
  </p>
</div>

<section>
  <h2>📌 Supported Versions</h2>
  <p>
    The following versions of the <strong>Windows-SysAdmin-ProSuite</strong> project — including <strong>BlueTeam-Tools</strong>,
    <strong>Core-ScriptLibrary</strong>, <strong>ITSM-Templates-SVR</strong>, <strong>ITSM-Templates-WKS</strong>, and
    <strong>SysAdmin-Tools</strong> — are actively maintained and receive security updates.
  </p>

  <h3>💻 Repository Modules</h3>
  <ul>
    <li>
      <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/BlueTeam-Tools" target="_blank" rel="noopener noreferrer">
        <img src="https://img.shields.io/badge/BlueTeam%20Tools-Forensics-orange?style=flat-square&logo=security" alt="BlueTeam-Tools Badge">
      </a>
      <span> Security, monitoring, and incident response scripts for Windows Server and enterprise environments.</span>
    </li>
    <li>
      <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/Core-ScriptLibrary" target="_blank" rel="noopener noreferrer">
        <img src="https://img.shields.io/badge/Core%20ScriptLibrary-Framework-red?style=flat-square&logo=visualstudiocode" alt="Core-ScriptLibrary Badge">
      </a>
      <span> Shared PowerShell foundations for automation, reusable functions, GUIs, and backend logic.</span>
    </li>
    <li>
      <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-SVR" target="_blank" rel="noopener noreferrer">
        <img src="https://img.shields.io/badge/ITSM%20Templates-SVR-purple?style=flat-square&logo=server" alt="ITSM-Templates-SVR Badge">
      </a>
      <span> Server templates for standardization, ITSM compliance, and operational automation.</span>
    </li>
    <li>
      <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-WKS" target="_blank" rel="noopener noreferrer">
        <img src="https://img.shields.io/badge/ITSM%20Templates-WKS-green?style=flat-square&logo=windows" alt="ITSM-Templates-WKS Badge">
      </a>
      <span> Workstation templates and procedures for Windows 10/11 endpoint configuration and compliance.</span>
    </li>
    <li>
      <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools" target="_blank" rel="noopener noreferrer">
        <img src="https://img.shields.io/badge/SysAdmin%20Tools-Management-blue?style=flat-square&logo=powershell" alt="SysAdmin-Tools Badge">
      </a>
      <span> Tools for Active Directory, GPO operations, workstation provisioning, and infrastructure management.</span>
    </li>
  </ul>

  <h3>🔧 Release Support Policy</h3>
  <p>
    This repository uses <strong>tag/release versioning</strong>. Only the most recent <strong>2 minor lines</strong> are supported
    (e.g., <code>v1.2.x</code> and <code>v1.3.x</code>). Older lines are considered unsupported unless explicitly stated in a release note.
  </p>

  <table border="1" style="border-collapse: collapse; width: 100%; text-align: center;">
    <caption><strong>Supported Release Lines (Policy)</strong></caption>
    <thead>
      <tr>
        <th>Line</th>
        <th>Status</th>
        <th>Notes</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td>Latest minor line</td>
        <td>✅ Supported</td>
        <td>Receives security fixes, improvements, and CI updates.</td>
      </tr>
      <tr>
        <td>Previous minor line</td>
        <td>✅ Supported</td>
        <td>Receives security fixes only (best-effort).</td>
      </tr>
      <tr>
        <td>Older lines</td>
        <td>❌ Unsupported</td>
        <td>No guaranteed fixes; upgrade recommended.</td>
      </tr>
    </tbody>
  </table>

  <h3>🖥️ Windows Workstation Compatibility</h3>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: center;">
    <caption><strong>Supported Windows Workstation Versions</strong></caption>
    <thead>
      <tr><th>Version</th><th>Status</th><th>Notes</th></tr>
    </thead>
    <tbody>
      <tr><td>Windows 11</td><td>✅ Supported</td><td>Supported for workstation scripts and templates.</td></tr>
      <tr><td>Windows 10</td><td>✅ Supported</td><td>Supported for workstation scripts and templates.</td></tr>
      <tr><td>Windows 8.x</td><td>❌ Unsupported</td><td>Not supported; upgrade required.</td></tr>
      <tr><td>Windows 7</td><td>❌ Unsupported</td><td>Not supported; upgrade required.</td></tr>
    </tbody>
  </table>

  <h3>🖥️ Windows Server Compatibility</h3>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: center;">
    <caption><strong>Supported Windows Server Versions</strong></caption>
    <thead>
      <tr><th>Version</th><th>Status</th><th>Notes</th></tr>
    </thead>
    <tbody>
      <tr><td>Windows Server 2022</td><td>✅ Supported</td><td>Supported for SysAdmin and BlueTeam toolsets.</td></tr>
      <tr><td>Windows Server 2019</td><td>✅ Supported</td><td>Supported for SysAdmin and BlueTeam toolsets.</td></tr>
      <tr><td>Windows Server 2016</td><td>✅ Supported</td><td>Supported on best-effort basis (older baseline).</td></tr>
      <tr><td>Windows Server 2012</td><td>❌ Unsupported</td><td>Not supported; upgrade required.</td></tr>
    </tbody>
  </table>
</section>

<section>
  <h2>🕵️ Reporting a Vulnerability</h2>
  <ol>
    <li><strong>Contact:</strong> Send details to <a href="mailto:luizhamilton.lhr@gmail.com">luizhamilton.lhr@gmail.com</a></li>
    <li><strong>Scope:</strong> Include affected module/folder, reproduction steps, logs, and expected impact.</li>
    <li><strong>Response Time:</strong> Initial reply within <strong>3 business days</strong>.</li>
    <li><strong>Fixes:</strong> Confirmed issues will be patched and released with notes and updated artifacts.</li>
  </ol>
  <p><strong>⚠️ Note:</strong> Please do not disclose vulnerabilities publicly until a patch or mitigation is published.</p>
</section>

<section>
  <h2>🔒 Security Measures</h2>
  <ul>
    <li><strong>Secure CI:</strong> EditorConfig, Prettier, VBScript SARIF, and PowerShell SARIF pipelines enforce quality signals.</li>
    <li><strong>Code Reviews:</strong> Changes are reviewed before merge when possible; CI gates reduce regressions.</li>
    <li><strong>Least Privilege:</strong> GitHub Actions permissions are minimized and scoped per job.</li>
    <li><strong>Traceability:</strong> Builds produce artifacts and summaries for auditing and reproducibility.</li>
  </ul>
</section>

<section>
  <h2>📚 Additional Resources</h2>
  <ul>
    <li>
      <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/BlueTeam-Tools/README.md" target="_blank" rel="noopener noreferrer">
        <img src="https://img.shields.io/badge/BlueTeam%20Tools-Docs-orange?style=flat-square&logo=readthedocs" alt="BlueTeam Docs">
      </a>
      BlueTeam forensic and threat monitoring documentation
    </li>
    <li>
      <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/Core-ScriptLibrary/README.md" target="_blank" rel="noopener noreferrer">
        <img src="https://img.shields.io/badge/Core%20ScriptLibrary-Docs-red?style=flat-square&logo=readthedocs" alt="Core Script Docs">
      </a>
      Core scripts and UI frameworks documentation
    </li>
    <li>
      <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/ITSM-Templates-SVR/README.md" target="_blank" rel="noopener noreferrer">
        <img src="https://img.shields.io/badge/ITSM%20Templates-SVR%20Docs-purple?style=flat-square&logo=readthedocs" alt="ITSM SVR Docs">
      </a>
      ITSM templates for server automation
    </li>
    <li>
      <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/ITSM-Templates-WKS/README.md" target="_blank" rel="noopener noreferrer">
        <img src="https://img.shields.io/badge/ITSM%20Templates-WKS%20Docs-green?style=flat-square&logo=readthedocs" alt="ITSM WKS Docs">
      </a>
      Templates for endpoint configuration and security
    </li>
    <li>
      <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/SysAdmin-Tools/README.md" target="_blank" rel="noopener noreferrer">
        <img src="https://img.shields.io/badge/SysAdmin%20Tools-Docs-blue?style=flat-square&logo=readthedocs" alt="SysAdmin Docs">
      </a>
      Admin scripts for directory, servers, and workstation management
    </li>
  </ul>
</section>

<section>
  <h2>🗂️ Version History</h2>
  <table border="1" style="border-collapse: collapse; width: 100%; text-align: center;">
    <caption><strong>Security Policy Versioning</strong></caption>
    <thead>
      <tr>
        <th>Version</th>
        <th>Date</th>
        <th>Changes Made</th>
        <th>Author</th>
      </tr>
    </thead>
    <tbody>
      <tr><td>3.0</td><td>2026-02-03</td><td>Policy refresh: tag/release support lines, updated module wording, CI/security measures section refined</td><td>Luiz Hamilton Silva</td></tr>
      <tr><td>2.8</td><td>2025-07-21</td><td>Added tools for total Active Directory Services integration</td><td>Luiz Hamilton Silva</td></tr>
      <tr><td>1.2</td><td>2024-04-27</td><td>Updated support tables and links</td><td>Luiz Hamilton Silva</td></tr>
      <tr><td>1.1</td><td>2023-06-15</td><td>Added templates and Core library</td><td>Luiz Hamilton Silva</td></tr>
      <tr><td>1.0</td><td>2023-01-01</td><td>Initial release</td><td>Luiz Hamilton Silva</td></tr>
    </tbody>
  </table>
</section>

<p align="center" style="color: #777;">&copy; 2026 Luiz Hamilton. All rights reserved.</p>
