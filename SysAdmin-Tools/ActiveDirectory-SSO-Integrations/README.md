<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>ActiveDirectory-SSO-Integrations</title>
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; padding: 20px; }
    pre { background: #f4f4f4; padding: 10px; border: 1px solid #ddd; }
    code { background: #f4f4f4; padding: 2px 4px; }
    h1, h2, h3 { color: #333; }
    a { color: #007acc; text-decoration: none; }
    a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <h1>ActiveDirectory-SSO-Integrations</h1>
  <p>
    Welcome to the <strong>ActiveDirectory-SSO-Integrations</strong> repository. This repository demonstrates multiple integration models for implementing Single Sign-On (SSO) using Active Directory via LDAP. All modules use a generalized configuration approach to ensure consistency and adaptability across various technology stacks.
  </p>
  
  <h2>Folder Structure</h2>
  <pre>
ActiveDirectory-SSO-Integrations
│
├── SpringBoot-API
│   └── (Contains Spring Boot integration code using application.yml)
│
├── NodeJS-API
│   ├── package.json
│   ├── app.js
│   ├── config
│   │   └── ldap.config.json
│   └── README.md
│
├── DotNet-API
│   ├── DotNetSSO.sln
│   ├── DotNetSSO.API
│   │   ├── appsettings.json
│   │   └── Startup.cs
│   └── README.md
│
└── Python-API
    ├── requirements.txt
    ├── app.py
    ├── config.py
    └── README.md
  </pre>
  
  <h2>Overview</h2>
  <p>
    Each module in this repository demonstrates how to integrate LDAP-based SSO authentication using a common, generalized configuration:
  </p>
  <ul>
    <li>
      <strong>SpringBoot-API:</strong> A Spring Boot API using Spring Security and LDAP settings from <code>application.yml</code>.
    </li>
    <li>
      <strong>NodeJS-API:</strong> A Node.js API built with Express and <code>passport-ldapauth</code> for LDAP authentication.
    </li>
    <li>
      <strong>DotNet-API:</strong> An ASP.NET Core API that leverages LDAP for SSO through a custom authentication handler.
    </li>
    <li>
      <strong>Python-API:</strong> A Flask API that uses the <code>ldap3</code> library to perform LDAP authentication.
    </li>
  </ul>
  
  <h2>Generalized LDAP Configuration</h2>
  <p>
    All modules are configured using the following generalized LDAP parameters:
  </p>
  <ul>
    <li><code>base: dc=HEADQ,dc=SCRIPTGUY</code></li>
    <li><code>username: binduser@scriptguy</code></li>
    <li><code>password: ${LDAP_PASSWORD}</code> (Externalized via environment variables)</li>
    <li><code>urls: ldap://ldap.example.com:3268</code> (Port 3268 for Global Catalog or 389 for standard domains)</li>
    <li><code>user-dn-pattern: sAMAccountName={0}</code></li>
    <li><code>user-search-filter: (sAMAccountName={0})</code></li>
    <li><code>group-search-base: dc=example,dc=com</code></li>
    <li><code>group-search-filter: (member={0})</code></li>
  </ul>
  
  <h2>Usage Instructions</h2>
  <h3>General Setup</h3>
  <ul>
    <li>Ensure the <code>LDAP_PASSWORD</code> environment variable is set before running any module.</li>
    <li>Review and adjust configuration files (such as <code>application.yml</code>, <code>ldap.config.json</code>, <code>appsettings.json</code>, and <code>config.py</code>) as necessary to match your environment.</li>
  </ul>
  
  <h3>SpringBoot-API</h3>
  <ul>
    <li>Navigate to the <code>SpringBoot-API</code> folder.</li>
    <li>Build and run the application using your preferred build tool (Maven or Gradle).</li>
  </ul>
  
  <h3>NodeJS-API</h3>
  <ul>
    <li>Navigate to the <code>NodeJS-API</code> folder.</li>
    <li>Run <code>npm install</code> to install the dependencies.</li>
    <li>Start the server with <code>npm start</code>; the API will be available on port 3000.</li>
  </ul>
  
  <h3>DotNet-API</h3>
  <ul>
    <li>Navigate to the <code>DotNet-API</code> folder.</li>
    <li>Open the solution (<code>.sln</code>) in Visual Studio or use the .NET CLI to build and run the application.</li>
  </ul>
  
  <h3>Python-API</h3>
  <ul>
    <li>Navigate to the <code>Python-API</code> folder.</li>
    <li>Install dependencies with <code>pip install -r requirements.txt</code>.</li>
    <li>Run the application with <code>python app.py</code>; the server will be available on port 5000.</li>
  </ul>
  
  <h2>Additional Information</h2>
  <p>
    Each integration module is self-contained and comes with its own README file containing further usage details and configuration instructions. For extending or customizing any module, please refer to the respective module’s documentation.
  </p>
  
  <h2>License</h2>
  <p>
    This project is licensed under the MIT License. See the <a href="LICENSE" target="_blank">LICENSE</a> file for details.
  </p>
  
  <h2>Contributing</h2>
  <p>
    Contributions are welcome! Please review the <a href="CONTRIBUTING.md" target="_blank">CONTRIBUTING.md</a> file for guidelines on how to contribute to this project.
  </p>
</body>
</html>
