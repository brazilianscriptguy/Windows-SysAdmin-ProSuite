  <h1>🔹 ActiveDirectory-SSO-Integrations</h1>
  <p>
    Welcome to the <strong>ActiveDirectory-SSO-Integrations</strong> repository. This repository demonstrates multiple integration models for implementing Single Sign-On (SSO) using Active Directory via LDAP. All modules use a standardized configuration approach for consistency across different technology stacks.
  </p>

  <h2>📁 Folder Structure</h2>
  <pre>
ActiveDirectory-SSO-Integrations/
│
├── 📂 DotNet-API/                # ASP.NET Core API with LDAP authentication
│   ├── 📄 DotNetSSO.sln          # Solution file for the .NET project
│   ├── 📂 DotNetSSO.API/         # API implementation
│   │   ├── 🛠️ appsettings.json  # Configuration file for app settings
│   │   └── 🏗️ Startup.cs         # Application startup configuration
│   └── 📖 README.md              # Documentation for DotNet-API
│
├── 📂 NodeJS-API/                # Node.js API using Express & passport-ldapauth
│   ├── 📜 package.json           # Node.js dependencies & scripts
│   ├── 📝 app.js                 # Main application logic
│   ├── 📂 config/                # Configuration folder
│   │   └── ⚙️ ldap.config.json  # LDAP settings for authentication
│   └── 📖 README.md              # Documentation for NodeJS-API
│
├── 📂 Python-API/                # Flask API using ldap3 for LDAP authentication
│   ├── 📄 requirements.txt       # Python dependencies
│   ├── 📝 app.py                 # Main API implementation
│   ├── ⚙️ config.py              # Configuration settings
│   └── 📖 README.md              # Documentation for Python-API
│
└── 📂 SpringBoot-API/            # Java Spring Boot API with LDAP authentication
    └── ⚙️ application.yml        # Configuration file for LDAP settings
  </pre>

  <h2>📝 Overview</h2>
  <p>
    Each module integrates LDAP-based SSO authentication using a common configuration model:
  </p>
  <ul>
    <li><strong>SpringBoot-API:</strong> Uses Spring Security with LDAP settings in <code>application.yml</code>.</li>
    <li><strong>NodeJS-API:</strong> Built with Express and <code>passport-ldapauth</code> for authentication.</li>
    <li><strong>DotNet-API:</strong> Uses ASP.NET Core with a custom LDAP authentication handler.</li>
    <li><strong>Python-API:</strong> Implements LDAP authentication using the <code>ldap3</code> library.</li>
  </ul>

  <h2>⚙️ Generalized LDAP Configuration</h2>
  <p>All modules follow this LDAP configuration structure:</p>
  <ul>
    <li><code>base: dc=HEADQ,dc=SCRIPTGUY</code></li>
    <li><code>username: binduser@scriptguy</code></li>
    <li><code>password: ${LDAP_PASSWORD}</code> (Externalized via environment variables)</li>
    <li><code>urls: ldap://ldap.example.com:3268</code> (Global Catalog on port 3268 or 389 for standard domains)</li>
    <li><code>user-dn-pattern: sAMAccountName={0}</code></li>
    <li><code>user-search-filter: (sAMAccountName={0})</code></li>
    <li><code>group-search-base: dc=example,dc=com</code></li>
    <li><code>group-search-filter: (member={0})</code></li>
  </ul>

  <h2>🚀 Usage Instructions</h2>

  <h3>General Setup</h3>
  <ul>
    <li>Set the <code>LDAP_PASSWORD</code> environment variable before running any module.</li>
    <li>Modify configuration files as needed:
      <ul>
        <li><code>appsettings.json</code> (DotNet-API)</li>
        <li><code>ldap.config.json</code> (NodeJS-API)</li>
        <li><code>config.py</code> (Python-API)</li>
        <li><code>application.yml</code> (SpringBoot-API)</li>
      </ul>
    </li>
  </ul>

  <h3>DotNet-API</h3>
  <ul>
    <li>Navigate to the <code>DotNet-API</code> folder.</li>
    <li>Open the <code>.sln</code> file in Visual Studio or use the .NET CLI to build and run.</li>
  </ul>

  <h3>NodeJS-API</h3>
  <ul>
    <li>Navigate to the <code>NodeJS-API</code> folder.</li>
    <li>Run <code>npm install</code> to install dependencies.</li>
    <li>Start the server with <code>npm start</code> (default port: 3000).</li>
  </ul>

  <h3>Python-API</h3>
  <ul>
    <li>Navigate to the <code>Python-API</code> folder.</li>
    <li>Install dependencies: <code>pip install -r requirements.txt</code>.</li>
    <li>Run the app: <code>python app.py</code> (default port: 5000).</li>
  </ul>

  <h3>SpringBoot-API</h3>
  <ul>
    <li>Navigate to the <code>SpringBoot-API</code> folder.</li>
    <li>Use Maven or Gradle to build and run the application.</li>
  </ul>

  <h2>📌 Additional Information</h2>
  <p>
    Each module contains a dedicated README with setup instructions. Refer to the documentation for further configuration details.
  </p>

  <h2>📜 License</h2>
  <p>
    This project is licensed under the MIT License. See the <a href="LICENSE" target="_blank">LICENSE</a> file for details.
  </p>

  <h2>🤝 Contributing</h2>
  <p>
    Contributions are welcome! Follow the guidelines in the <a href="CONTRIBUTING.md" target="_blank">CONTRIBUTING.md</a> file.
  </p>

</body>
</html>
