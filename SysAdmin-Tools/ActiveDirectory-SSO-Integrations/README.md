<div>
  <h1>🔹 ActiveDirectory-SSO-Integrations</h1>

  <h2>📝 Overview</h2>
  <p>
    The <strong>ActiveDirectory-SSO-Integrations</strong> folder includes a set of 
    <strong>cross-platform integration models</strong> for implementing Single Sign-On (SSO) 
    via <code>LDAP</code> using Active Directory. Each module follows a 
    <strong>standardized configuration structure</strong> to ensure consistency and ease of integration 
    across different development stacks.
  </p>

  <h3>Key Features:</h3>
  <ul>
    <li><strong>Cross-Technology Compatibility:</strong> Supports .NET, Flask, Node.js, PHP, and Spring Boot.</li>
    <li><strong>Secure Bind Credentials:</strong> Uses environment variables or external secrets for LDAP authentication.</li>
    <li><strong>Modular Architecture:</strong> Each implementation is self-contained with isolated configuration layers.</li>
    <li><strong>Standard LDAP Flow:</strong> Unified login logic across different stacks using <code>InetOrgPerson</code> model.</li>
  </ul>

  <hr />

  <h2>🛠️ Prerequisites</h2>
  <ol>
    <li>
      <strong>🔐 LDAP Bind Account (InetOrgPerson)</strong>
      <p>Create a delegated AD account with minimal read permissions. Avoid using privileged credentials.</p>
    </li>
    <li>
      <strong>💻 Language-Specific Runtime Environments</strong>
      <ul>
        <li><strong>.NET SDK</strong> for DotNet-API</li>
        <li><strong>Python 3.x</strong> with <code>ldap3</code> for Flask-API</li>
        <li><strong>Node.js</strong> with <code>passport-ldapauth</code> for NodeJS-API</li>
        <li><strong>PHP 7+</strong> with LDAP module enabled</li>
        <li><strong>JDK 11+</strong> with Spring Boot for Java-based implementation</li>
      </ul>
    </li>
    <li>
      <strong>🔑 Secure Credentials</strong>
      <p>Ensure the <code>LDAP_PASSWORD</code> environment variable is securely defined before runtime.</p>
    </li>
    <li>
      <strong>📂 Configuration Files</strong>
      <ul>
        <li><code>appsettings.json</code> – DotNet-API</li>
        <li><code>config.py</code> – Flask-API</li>
        <li><code>ldap.config.json</code> – NodeJS-API</li>
        <li><code>.env</code> – PHP-API</li>
        <li><code>application.yml</code> – SpringBoot-API</li>
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
        <td>Implements LDAP authentication using ASP.NET Core and custom middleware with JSON configuration.</td>
      </tr>
      <tr>
        <td><code>Flask-API</code></td>
        <td>RESTful API built in Python using <code>ldap3</code>, with centralized environment configuration.</td>
      </tr>
      <tr>
        <td><code>NodeJS-API</code></td>
        <td>Express.js application utilizing <code>passport-ldapauth</code> and layered route/middleware logic.</td>
      </tr>
      <tr>
        <td><code>PHP-API</code></td>
        <td>Native PHP solution leveraging <code>ldap_bind</code>, environment-based auth, and fallback logic.</td>
      </tr>
      <tr>
        <td><code>SpringBoot-API</code></td>
        <td>Java-based implementation using Spring Security LDAP and profile-based YAML configuration.</td>
      </tr>
    </tbody>
  </table>

  <hr />

  <h2>🚀 Usage Instructions</h2>
  <ol>
    <li><strong>Set Environment:</strong> Define <code>LDAP_PASSWORD</code> in your terminal or container environment.</li>
    <li><strong>Adjust Configuration:</strong> Review and update LDAP host, port, base DN, and filters.</li>
    <li><strong>Run the Application:</strong> Use the standard startup command below per module.</li>
  </ol>

  <h3>Run Commands</h3>
  <ul>
    <li><strong>DotNet-API:</strong>
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

  <h2>🔐 Best Practices: InetOrgPerson AD SSO Account</h2>
  <p>
    For LDAP SSO integrations, use a <strong>dedicated <code>InetOrgPerson</code> account</strong> with 
    restricted permissions to minimize risk and follow secure binding principles.
  </p>

  <h3>🛡️ Recommended Delegations</h3>
  <ul>
    <li><strong>Read-Only Attributes:</strong> Only allow lookup for attributes required in your bind and filter logic.</li>
    <li><strong>List/Search Scope:</strong> Permit enumeration of users and groups (Base/OneLevel/Subtree as applicable).</li>
    <li><strong>Access Controls:</strong> Disable interactive logon; enforce password expiration; restrict delegation rights.</li>
  </ul>

  <h3>📌 Sample AD Account</h3>
  <ul>
    <li><strong>User:</strong> <code>HEADQ\ad-sso-authentication</code></li>
    <li><strong>DN:</strong> <code>CN=ad-sso-authentication,OU=ServiceAccounts,DC=headq,DC=scriptguy</code></li>
    <li><strong>Type:</strong> <code>InetOrgPerson</code> with <em>logon as service</em> enabled</li>
  </ul>

  <hr />

  <h2>📄 Complementary Files</h2>
  <ul>
    <li><strong>example.env</strong> – Sample environment setup for PHP and Flask APIs.</li>
    <li><strong>ldap.config.json</strong> – Config schema for NodeJS-based integration.</li>
    <li><strong>application.yml</strong> – Spring Boot LDAP profile configuration.</li>
  </ul>

  <hr />

  <h2>💡 Optimization Tips</h2>
  <ul>
    <li><strong>Least Privilege Principle:</strong> Never bind using high-privilege domain accounts.</li>
    <li><strong>Automate Environments:</strong> Use Docker Compose to containerize APIs with environment variables securely injected.</li>
    <li><strong>Centralize Secrets:</strong> Adopt secret managers (e.g., Azure Key Vault, HashiCorp Vault) to manage bind credentials.</li>
  </ul>

  <hr />
</div>
