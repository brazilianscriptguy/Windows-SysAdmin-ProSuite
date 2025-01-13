    <title>🛡️ Security Policy</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/5.15.4/css/all.min.css">
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 0;
        }
        h1, h2, h3 {
            text-align: center;
            margin-top: 20px;
        }
        ul {
            list-style: none;
            padding: 0;
        }
        ul li {
            margin-bottom: 10px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px auto;
        }
        table th, table td {
            border: 1px solid #ccc;
            padding: 10px;
            text-align: center;
        }
        table th {
            background-color: #f4f4f4;
        }
        a {
            text-decoration: none;
            color: #007bff;
        }
        a:hover {
            text-decoration: underline;
        }
        .badge {
            display: inline-block;
            padding: 5px 10px;
            border-radius: 4px;
            font-size: 0.9rem;
            color: white;
            text-align: center;
        }
        .badge.orange {
            background-color: orange;
        }
        .badge.red {
            background-color: red;
        }
        .badge.purple {
            background-color: purple;
        }
        .badge.green {
            background-color: green;
        }
        .badge.blue {
            background-color: blue;
        }
    </style>
</head>
<body>
    <div align="center">
        <h1>🛡️ Security Policy</h1>
    </div>

    <h2>📌 Supported Versions</h2>
    <p>
        The following versions of the <strong>PowerShell ToolSet</strong> (BlueTeam-Tools, Core-ScriptLibrary, ITSM-Templates-SVR, ITSM-Templates-WKS, SysAdmin-Tools) for Windows Server Administration and the <strong>VBScript Repository</strong> (ITSM-Templates-WKS) for Windows Workstations 10/11 are supported with security updates. These scripts are designed to work with specific versions of Windows Workstations and Windows Server.
    </p>

    <h3>💻 PowerShell ToolSet Versions</h3>
    <ul>
        <li>
            <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/BlueTeam-Tools" target="_blank" rel="noopener noreferrer">
                <span class="badge orange">BlueTeam Tools</span>
            </a>
            Security measures, monitoring, and incident response for Windows Server.
        </li>
        <li>
            <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/Core-ScriptLibrary" target="_blank" rel="noopener noreferrer">
                <span class="badge red">Core ScriptLibrary</span>
            </a>
            Essential scripts for dynamic UIs, automation, and complex solutions.
        </li>
        <li>
            <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-SVR" target="_blank" rel="noopener noreferrer">
                <span class="badge purple">ITSM Templates-SVR</span>
            </a>
            ITSM-focused scripts for managing Windows Server environments.
        </li>
        <li>
            <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/ITSM-Templates-WKS" target="_blank" rel="noopener noreferrer">
                <span class="badge green">ITSM Templates-WKS</span>
            </a>
            Scripts for managing Windows 10/11 workstations in ITSM frameworks.
        </li>
        <li>
            <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools" target="_blank" rel="noopener noreferrer">
                <span class="badge blue">SysAdmin Tools</span>
            </a>
            Tools for Active Directory, user management, and security configurations.
        </li>
    </ul>

    <table>
        <thead>
            <tr>
                <th>Version</th>
                <th>Status</th>
                <th>Release Date</th>
                <th>End of Support</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td>22.x.x</td>
                <td>✅ Supported</td>
                <td>January 2024</td>
                <td>December 2024</td>
            </tr>
            <tr>
                <td>21.x.x</td>
                <td>✅ Supported</td>
                <td>January 2023</td>
                <td>December 2023</td>
            </tr>
            <tr>
                <td>20.x.x</td>
                <td>✅ Supported</td>
                <td>January 2022</td>
                <td>December 2022</td>
            </tr>
            <tr>
                <td>19.x.x</td>
                <td>❌ Unsupported</td>
                <td>January 2021</td>
                <td>December 2021</td>
            </tr>
        </tbody>
    </table>

    <h3>🖥️ Windows Workstations Versions</h3>
    <table>
        <thead>
            <tr>
                <th>Version</th>
                <th>Status</th>
                <th>Release Date</th>
                <th>End of Support</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td>Windows 11</td>
                <td>✅ Supported</td>
                <td>October 2021</td>
                <td>October 2026</td>
            </tr>
            <tr>
                <td>Windows 10</td>
                <td>✅ Supported</td>
                <td>July 2015</td>
                <td>October 2025</td>
            </tr>
            <tr>
                <td>Windows 8.x</td>
                <td>❌ Unsupported</td>
                <td>October 2012</td>
                <td>January 2016</td>
            </tr>
            <tr>
                <td>Windows 7</td>
                <td>❌ Unsupported</td>
                <td>October 2009</td>
                <td>January 2020</td>
            </tr>
        </tbody>
    </table>

    <h3>🖥️ Windows Server Versions</h3>
    <table>
        <thead>
            <tr>
                <th>Version</th>
                <th>Status</th>
                <th>Release Date</th>
                <th>End of Support</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td>Windows Server 2022</td>
                <td>✅ Supported</td>
                <td>August 2021</td>
                <td>October 2026</td>
            </tr>
            <tr>
                <td>Windows Server 2019</td>
                <td>✅ Supported</td>
                <td>October 2018</td>
                <td>January 2029</td>
            </tr>
            <tr>
                <td>Windows Server 2016</td>
                <td>✅ Supported</td>
                <td>October 2016</td>
                <td>January 2027</td>
            </tr>
            <tr>
                <td>Windows Server 2012</td>
                <td>❌ Unsupported</td>
                <td>September 2012</td>
                <td>October 2018</td>
            </tr>
        </tbody>
    </table>

    <h2>🕵️‍♂️ Reporting a Vulnerability</h2>
    <ol>
        <li><strong>📧 Report Directly:</strong> Send details to <a href="mailto:luizhamilton.lhr@gmail.com">luizhamilton.lhr@gmail.com</a>.</li>
        <li><strong>⏱️ Response Time:</strong> Expect a reply within 3 business days.</li>
        <li><strong>🔧 Resolution:</strong> We will promptly address and release a fix.</li>
    </ol>
    <p><strong>⚠️ Note:</strong> Please avoid public disclosure until resolved.</p>

    <h2>🔒 Security Measures</h2>
    <ul>
        <li>🔄 <strong>Regular Updates:</strong> Frequent updates to address vulnerabilities.</li>
        <li>🔍 <strong>Code Reviews:</strong> Thorough review of scripts for risks.</li>
        <li>🔐 <strong>Access Controls:</strong> Strict limits on modifications and distribution.</li>
        <li>🔑 <strong>Encryption:</strong> Sensitive data is securely encrypted.</li>
    </ul>

    <h2>📚 Additional Resources</h2>
<ul>
  <li>
    <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/BlueTeam-Tools/README.md" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/BlueTeam%20Tools-Documentation-orange?style=flat-square&logo=readthedocs" alt="BlueTeam-Tools Documentation Badge">
    </a>
    <span>Toolkit for forensic analysis, incident response, and log parsing.</span>
  </li>
  <li>
    <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/Core-ScriptLibrary/README.md" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/Core%20ScriptLibrary-Documentation-red?style=flat-square&logo=readthedocs" alt="Core-ScriptLibrary Documentation Badge">
    </a>
    <span>Foundational scripts for automation and advanced PowerShell solutions.</span>
  </li>
  <li>
    <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/ITSM-Templates-SVR/README.md" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/ITSM%20Templates-SVR%20Documentation-purple?style=flat-square&logo=readthedocs" alt="ITSM-Templates-SVR Documentation Badge">
    </a>
    <span>Server-side templates for ITSM compliance, hardening, and automation.</span>
  </li>
  <li>
    <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/ITSM-Templates-WKS/README.md" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/ITSM%20Templates-WKS%20Documentation-green?style=flat-square&logo=readthedocs" alt="ITSM-Templates-WKS Documentation Badge">
    </a>
    <span>Workstation-side templates for ITSM compliance on Windows 10/11.</span>
  </li>
  <li>
    <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/SysAdmin-Tools/README.md" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/badge/SysAdmin%20Tools-Documentation-blue?style=flat-square&logo=readthedocs" alt="SysAdmin-Tools Documentation Badge">
    </a>
    <span>Active Directory and infrastructure management, GPO tools, and security optimizations.</span>
  </li>
</ul>

<h2>🗂️ Version History</h2>
<table border="1" style="border-collapse: collapse; width: 100%; text-align: center;">
  <thead>
    <tr>
      <th>Version</th>
      <th>Date</th>
      <th>Changes Made</th>
      <th>Author</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>1.0</td>
      <td>2023-01-01</td>
      <td>Initial creation</td>
      <td>Luiz Hamilton Silva</td>
    </tr>
    <tr>
      <td>1.1</td>
      <td>2023-06-15</td>
      <td>Added Core-ScriptLibrary and ITSM-Templates</td>
      <td>Luiz Hamilton Silva</td>
    </tr>
    <tr>
      <td>1.2</td>
      <td>2024-04-27</td>
      <td>Updated Supported Versions tables and links</td>
      <td>Luiz Hamilton Silva</td>
    </tr>
  </tbody>
</table>
