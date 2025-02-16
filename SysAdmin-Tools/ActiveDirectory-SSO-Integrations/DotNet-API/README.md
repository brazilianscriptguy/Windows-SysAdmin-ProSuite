<h1>🔹 DotNet-API: Active Directory SSO Integration</h1>

<h2>📌 Overview</h2>
<p>
  The <strong>DotNet-API</strong> is an <strong>ASP.NET Core-based REST API</strong> that enables 
  <strong>LDAP-based Single Sign-On (SSO) authentication</strong> with <strong>Active Directory</strong>.
</p>

<h2>📁 Folder Structure</h2>
<pre>
DotNetSSO.API/
│
├── 📄 Program.cs                  # Entry point for the API
├── 🏗️ Startup.cs                   # Application startup configuration
├── 📜 appsettings.json            # General application settings
├── 📜 ldapsettings.json           # LDAP authentication settings
├── 📂 Controllers/                # API controllers
│   ├── 📜 AuthController.cs       # Handles authentication requests
│   ├── 📜 UserController.cs       # Manages user-related requests
├── 📂 Services/                   # Business logic for LDAP authentication
│   ├── 📜 LdapService.cs          # Handles LDAP authentication logic
├── 📂 Middleware/                 # Custom authentication enforcement
│   ├── 📜 AuthenticationMiddleware.cs  # Middleware for enforcing authentication
├── 📂 Models/                     # Defines data models
│   ├── 📜 UserModel.cs            # Represents user object schema
</pre>

<h2>🛠️ Prerequisites</h2>
<ul>
  <li><strong>.NET 6.0 or later</strong></li>
  <li><strong>Active Directory instance</strong></li>
  <li><strong>LDAP access credentials</strong></li>
  <li><strong>Visual Studio / VS Code</strong></li>
  <li><strong>Postman (for testing API requests)</strong></li>
</ul>

<h2>⚙️ Configuration</h2>
<p>Modify <code>appsettings.json</code> with your <strong>LDAP credentials</strong>:</p>

<pre>
{
  "LdapSettings": {
    "LdapServer": "ldap://ldap.headq.scriptguy:3268",
    "BaseDn": "dc=headq,dc=scriptguy",
    "BindDn": "cn=ad-sso-authentication,ou=ServiceAccounts,dc=headq,dc=scriptguy",
    "BindPassword": "${LDAP_PASSWORD}",
    "UserFilter": "(sAMAccountName={0})"
  }
}
</pre>

<h2>🚀 How to Run</h2>
<ol>
  <li><strong>Clone the repository:</strong>
    <pre>git clone https://github.com/brazilianscriptguy/ActiveDirectory-SSO-Integrations.git
cd ActiveDirectory-SSO-Integrations/DotNet-API</pre>
  </li>
  <li><strong>Set the LDAP password as an environment variable:</strong>
    <pre>export LDAP_PASSWORD='your-secure-password'</pre>
  </li>
  <li><strong>Run the application:</strong>
    <pre>dotnet run</pre>
  </li>
</ol>

<h2>🔄 API Endpoints</h2>

<h3>1️⃣ Authenticate User</h3>
<ul>
  <li><strong>Endpoint:</strong> <code>POST /api/auth/login</code></li>
  <li><strong>Request Body:</strong>
    <pre>
{
  "username": "john.doe",
  "password": "SuperSecretPassword"
}
    </pre>
  </li>
  <li><strong>Response:</strong>
    <pre>
{
  "message": "Authentication successful"
}
    </pre>
  </li>
</ul>

<h3>2️⃣ Get User Details</h3>
<ul>
  <li><strong>Endpoint:</strong> <code>GET /api/user/{username}</code></li>
  <li><strong>Example Request:</strong>
    <pre>curl -X GET http://localhost:5000/api/user/john.doe</pre>
  </li>
  <li><strong>Response:</strong>
    <pre>
{
  "username": "john.doe",
  "displayName": "John Doe",
  "email": "john.doe@example.com",
  "department": "IT",
  "role": "User"
}
    </pre>
  </li>
</ul>

<h2>📜 License</h2>
<p>
  This project is licensed under the <strong>MIT License</strong>.
</p>

<h2>🤝 Contributing</h2>
<p>
  Contributions are welcome! Please follow the guidelines in 
  <a href="../CONTRIBUTING.md" target="_blank">CONTRIBUTING.md</a>.
</p>

<h2>📩 Support</h2>
<p>
  For issues or questions, reach out to:  
  📧 <strong>Email:</strong> <a href="mailto:luizhamilton.lhr@gmail.com">luizhamilton.lhr@gmail.com</a>  
  🔗 <strong>GitHub Issues:</strong> 
  <a href="https://github.com/brazilianscriptguy/ActiveDirectory-SSO-Integrations/issues" target="_blank">Report Here</a>
</p>

<hr>

<p align="center">🚀 <strong>Enjoy Seamless SSO Integration!</strong> 🎯</p>
