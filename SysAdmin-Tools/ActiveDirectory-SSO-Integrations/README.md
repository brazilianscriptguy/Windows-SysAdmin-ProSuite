<h1>🔹 ActiveDirectory-SSO-Integrations</h1>
<p>
  Welcome to the <strong>ActiveDirectory-SSO-Integrations</strong> repository. 
  This repository demonstrates multiple integration models for implementing 
  Single Sign-On (SSO) using Active Directory via LDAP. All modules use a 
  standardized configuration approach for consistency across different technology stacks.
</p>

<h2>📝 Overview</h2>
<p>
  Each module integrates LDAP-based SSO authentication using a common configuration model.<br>
  See below for the list of available modules:
</p>

<table>
  <thead>
    <tr>
      <th style="min-width: 180px; white-space: nowrap;">📁 Folder</th>
      <th>🔧 Description</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>DotNet-API</code></td>
      <td>Uses ASP.NET Core with a custom LDAP authentication handler.</td>
    </tr>
    <tr>
      <td><code>Flask-API</code></td>
      <td>Implements LDAP authentication using the <code>ldap3</code> library.</td>
    </tr>
    <tr>
      <td><code>NodeJS-API</code></td>
      <td>Built with Express and <code>passport-ldapauth</code> for authentication.</td>
    </tr>
    <tr>
      <td><code>PHP-API</code></td>
      <td>Implements LDAP-based SSO using PHP and the <code>ldap</code> extension, with environment-based configuration and SSO fallback support.</td>
    </tr>
    <tr>
      <td><code>SpringBoot-API</code></td>
      <td>Uses Spring Security with LDAP settings in <code>application.yml</code>.</td>
    </tr>
  </tbody>
</table>

<h2>🚀 Usage Instructions</h2>

<h3>General Setup</h3>
<ul>
  <li>Set the <code>LDAP_PASSWORD</code> environment variable before running any module.</li>
  <li>Modify configuration files as needed:
    <ul>
      <li><code>appsettings.json</code> (DotNet-API)</li>
      <li><code>config.py</code> (Flask-API)</li>
      <li><code>ldap.config.json</code> (NodeJS-API)</li>
      <li><code>application.yml</code> (SpringBoot-API)</li>
    </ul>
  </li>
</ul>

<hr />

<h2>🔐 Security Best Practices: Using an InetOrgPerson AD Account for SSO</h2>

<p>
  To enhance security and reliability in your <strong>SSO API structure</strong>, it is highly recommended to use an 
  <strong>InetOrgPerson</strong> AD account with <strong>properly delegated permissions</strong> instead of a standard 
  user account. This ensures controlled access and limits security risks while maintaining compliance with best practices.
</p>

<h3>🛡️ Recommended Delegations for the InetOrgPerson AD SSO Account</h3>

<ul>
  <li><strong>Read Permissions:</strong> Read all user attributes needed for authentication.</li>
  <li><strong>List and Search Permissions:</strong> List user groups and search for user objects.</li>
  <li><strong>Authentication Rights:</strong> Logon as a service and prevent delegation attacks.</li>
  <li><strong>Security Measures:</strong> Restrict access, disable interactive logon, and enforce password policies.</li>
</ul>

<h3>📌 Example SSO Account Configuration</h3>
<ul>
  <li><strong>User:</strong> <code>HEADQ\ad-sso-authentication</code></li>
  <li><strong>Password:</strong> <code>(Securely Stored & Managed)</code></li>
  <li><strong>Distinguished Name:</strong> <code>CN=ad-sso-authentication,OU=ServiceAccounts,DC=headq,DC=scriptguy</code></li>
</ul>

<h2>🛠️ API-Specific Instructions</h2>

<h3>DotNet-API</h3>
<ul>
  <li>Navigate to the <code>DotNet-API</code> folder.</li>
  <li>Open the <code>.sln</code> file in Visual Studio or use the .NET CLI to build and run.</li>
</ul>

<h3>Flask-API</h3>
<ul>
  <li>Navigate to the <code>Flask-API</code> folder.</li>
  <li>Install dependencies: <code>pip install -r requirements.txt</code>.</li>
  <li>Run the app: <code>python app.py</code> (default port: 5000).</li>
</ul>

<h3>NodeJS-API</h3>
<ul>
  <li>Navigate to the <code>NodeJS-API</code> folder.</li>
  <li>Run <code>npm install</code> to install dependencies.</li>
  <li>Start the server with <code>npm start</code> (default port: 3000).</li>
</ul>

<h3>SpringBoot-API</h3>
<ul>
  <li>Navigate to the <code>SpringBoot-API</code> folder.</li>
  <li>Use Maven or Gradle to build and run the application.</li>
</ul>

<h2>📌 Additional Information</h2>
<p>Each module contains a dedicated README.md with setup instructions. Refer to the documentation for further configuration details.</p>

<h2>📜 License</h2>
<p>
  <a href="LICENSE" target="_blank">
    <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="MIT License">
  </a>
</p>

<h2>🤝 Contributing</h2>
<p>
  <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/CONTRIBUTING.md" target="_blank">
    <img src="https://img.shields.io/badge/Contributions-Welcome-brightgreen.svg" alt="Contributions Welcome">
  </a>
</p>

<hr />
