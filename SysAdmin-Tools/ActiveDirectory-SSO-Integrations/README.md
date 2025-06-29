<div>
  <h1>🔹 ActiveDirectory-SSO-Integrations</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>ActiveDirectory-SSO-Integrations</strong> folder contains a curated set of 
    <strong>cross-platform examples</strong> for implementing Single Sign-On (SSO) 
    using Active Directory via <code>LDAP</code>. Each module demonstrates secure integration 
    patterns with a <strong>standardized configuration model</strong> to ensure consistency 
    across varying development stacks and environments.
  </p>

  <h3>Key Features:</h3>
  <ul>
    <li><strong>Cross-Technology Support:</strong> Examples provided in .NET, Flask, NodeJS, PHP, and Spring Boot.</li>
    <li><strong>Secure Bind Credentials:</strong> Uses environment-based secrets or configuration vaults for SSO authentication.</li>
    <li><strong>Modular Integration:</strong> Each project uses self-contained logic and clean LDAP configuration interfaces.</li>
    <li><strong>Standardized SSO Design:</strong> Consistent pattern for implementing and testing AD-integrated SSO APIs.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>🔐 LDAP Access Account</strong>
      <p>
        Create a delegated <code>InetOrgPerson</code> account in Active Directory with appropriate read/search privileges.
        See "<strong>Recommended Delegations</strong>" section below for secure setup tips.
      </p>
    </li>
    <li>
      <strong>💻 Platform Dependencies</strong>
      <ul>
        <li><strong>.NET Core SDK</strong> for DotNet-API</li>
        <li><strong>Python 3.x</strong> and <code>ldap3</code> for Flask-API</li>
        <li><strong>Node.js</strong> with <code>passport-ldapauth</code> for NodeJS-API</li>
        <li><strong>PHP 7+</strong> and LDAP module for PHP-API</li>
        <li><strong>Java JDK 11+</strong> and Spring Boot for SpringBoot-API</li>
      </ul>
    </li>
    <li>
      <strong>🔑 Secure Credentials</strong>
      <p>Set the <code>LDAP_PASSWORD</code> environment variable before running any project to protect bind credentials.</p>
    </li>
    <li>
      <strong>📂 Configuration Files</strong>
      <p>Modify the appropriate config file per API implementation:</p>
      <ul>
        <li><code>appsettings.json</code> — DotNet-API</li>
        <li><code>config.py</code> — Flask-API</li>
        <li><code>ldap.config.json</code> — NodeJS-API</li>
        <li><code>.env</code> — PHP-API</li>
        <li><code>application.yml</code> — SpringBoot-API</li>
      </ul>
    </li>
  </ol>

  <hr />

  <h2>📄 Module Descriptions (Alphabetical Order)</h2>
  <table border="1" style="border-collapse: collapse; width: 100%;">
    <thead>
      <tr>
        <th style="padding: 8px;">📁 Folder</th>
        <th style="padding: 8px;">🔧 Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><code>DotNet-API</code></td>
        <td>ASP.NET Core with custom middleware for LDAP binding. Supports JSON-based config via <code>appsettings.json</code>.</td>
      </tr>
      <tr>
        <td><code>Flask-API</code></td>
        <td>REST API in Python using <code>ldap3</code>, configured via <code>config.py</code> and .env variables.</td>
      </tr>
      <tr>
        <td><code>NodeJS-API</code></td>
        <td>Express-based app using <code>passport-ldapauth</code> for authentication and route-level control.</td>
      </tr>
      <tr>
        <td><code>PHP-API</code></td>
        <td>Pure PHP example with native LDAP functions and fallback mechanisms. Uses <code>.env</code> for bind configuration.</td>
      </tr>
      <tr>
        <td><code>SpringBoot-API</code></td>
        <td>Java Spring Boot app leveraging <code>Spring Security LDAP</code> with YAML-based profile setup.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Set LDAP Credentials:</strong> Configure your AD bind user and set <code>LDAP_PASSWORD</code> as a system environment variable.</li>
    <li><strong>Update Configuration Files:</strong> Adjust host, bindDN, port, and filter logic per platform.</li>
    <li><strong>Run the Application:</strong> Use the standard run command per folder below:</li>
  </ol>

  <h3>Platform Run Commands</h3>
  <ul>
    <li><strong>DotNet-API:</strong> Open solution in Visual Studio or run:
      <pre><code>dotnet run</code></pre>
    </li>
    <li><strong>Flask-API:</strong>
      <pre><code>pip install -r requirements.txt
python app.py</code></pre>
    </li>
    <li><strong>NodeJS-API:</strong>
      <pre><code>npm install
npm start</code></pre>
    </li>
    <li><strong>PHP-API:</strong>
      <pre><code>composer install
php -S localhost:8000 -t public</code></pre>
    </li>
    <li><strong>SpringBoot-API:</strong>
      <pre><code>./mvnw spring-boot:run</code></pre>
    </li>
  </ul>

  <hr />

  <h2>🔐 Best Practices: Using an InetOrgPerson AD Account</h2>
  <p>
    For security, always bind your LDAP-based SSO tools using a <strong>dedicated AD service account</strong> of type 
    <code>InetOrgPerson</code>. This minimizes exposure of administrative credentials and enables granular control.
  </p>

  <h3>🛡️ Recommended AD Delegations</h3>
  <ul>
    <li><strong>Read-Only Attributes:</strong> Basic LDAP bind and read permissions.</li>
    <li><strong>List/Search Controls:</strong> Allow enumeration of users and groups.</li>
    <li><strong>Account Restrictions:</strong> Disable interactive login, prevent delegation, enforce strong password policy.</li>
  </ul>

  <h3>📌 Example AD Configuration</h3>
  <ul>
    <li><strong>User:</strong> <code>HEADQ\ad-sso-authentication</code></li>
    <li><strong>DN:</strong> <code>CN=ad-sso-authentication,OU=ServiceAccounts,DC=headq,DC=scriptguy</code></li>
    <li><strong>Type:</strong> <code>inetOrgPerson</code> with <code>Service Logon</code> rights only</li>
  </ul>

  <hr />

  <h2>📄 Complementary Files Overview</h2>
  <ul>
    <li><strong>example.env:</strong> Sample environment variables file for testing PHP and Flask APIs.</li>
    <li><strong>ldap.config.json:</strong> Config schema for NodeJS API.</li>
    <li><strong>application.yml:</strong> Spring Boot profile with LDAP settings.</li>
  </ul>

  <hr />

  <h2>💡 Tips for Optimization</h2>
  <ul>
    <li><strong>Use Secure Bind Accounts:</strong> Never use full domain admin accounts for LDAP auth.</li>
    <li><strong>Automate Deployment:</strong> Containerize each API with Docker for easier testing and CI pipelines.</li>
    <li><strong>Centralize Secrets:</strong> Integrate with secret vaults like HashiCorp Vault or Azure Key Vault.</li>
  </ul>

  <hr />

