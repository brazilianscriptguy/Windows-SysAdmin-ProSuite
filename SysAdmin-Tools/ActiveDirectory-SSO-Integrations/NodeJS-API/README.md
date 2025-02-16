<h1>🔹 NodeJS-API: Active Directory SSO Integration</h1>

<h2>📌 Overview</h2>
<p>
  The <strong>NodeJS-API</strong> module enables <strong>LDAP-based Single Sign-On (SSO)</strong> authentication with
  <strong>Active Directory</strong> using the <code>passport-ldapauth</code> strategy and Express.
  It allows **secure authentication and user query operations** directly from an LDAP directory.
</p>

<h2>📁 Folder Structure</h2>
<pre>
ActiveDirectory-SSO-Integrations/
│
├── 📂 NodeJS-API/                  # Parent folder for Node.js API integration
│   ├── 📜 package.json             # Project dependencies and startup script
│   ├── 📜 app.js                   # Main application file with Express & LDAP configuration
│   ├── 📂 config/                   # Configuration folder
│   │   ├── 📜 ldap.config.json     # LDAP authentication settings
│   ├── 📂 controllers/              # API controllers
│   │   ├── 📜 authController.js    # Handles authentication requests
│   │   ├── 📜 userController.js    # Fetches user details from Active Directory
│   ├── 📂 middleware/               # Middleware folder
│   │   ├── 📜 ldapAuthMiddleware.js # Handles LDAP authentication middleware
│   ├── 📂 routes/                   # Express routes
│   │   ├── 📜 authRoutes.js        # Routes for authentication endpoints
│   │   ├── 📜 userRoutes.js        # Routes for fetching user data
│   ├── 📂 utils/                    # Utility functions
│   │   ├── 📜 logger.js            # Logs authentication events
│   ├── 📖 README.md                 # Documentation for NodeJS-API
</pre>

<h2>🛠️ Prerequisites</h2>
<ul>
  <li><strong>Node.js 16+ and npm</strong></li>
  <li><strong>Active Directory instance</strong> accessible via LDAP</li>
  <li><strong>LDAP credentials with read permissions</strong></li>
  <li><strong>Postman or cURL</strong> (for testing API requests)</li>
</ul>

<h2>⚙️ Configuration</h2>
<p>Modify <code>config/ldap.config.json</code> with your <strong>LDAP credentials</strong>:</p>

<pre>
{
  "server": {
    "url": "ldap://ldap.headq.scriptguy:3268",
    "bindDn": "cn=ad-sso-authentication,ou=ServiceAccounts,dc=headq,dc=scriptguy",
    "bindCredentials": "${LDAP_PASSWORD}",
    "searchBase": "dc=headq,dc=scriptguy",
    "searchFilter": "(sAMAccountName={{username}})"
  }
}
</pre>

<h2>🚀 How to Run</h2>
<ol>
  <li><strong>Clone the repository:</strong>
    <pre>git clone https://github.com/brazilianscriptguy/ActiveDirectory-SSO-Integrations.git
cd ActiveDirectory-SSO-Integrations/NodeJS-API</pre>
  </li>
  <li><strong>Set the LDAP password as an environment variable:</strong>
    <pre>export LDAP_PASSWORD='your-secure-password'</pre>
  </li>
  <li><strong>Install dependencies:</strong>
    <pre>npm install</pre>
  </li>
  <li><strong>Start the application:</strong>
    <pre>npm start</pre>
  </li>
  <li>The API will be available at <code>http://localhost:3000</code>.</li>
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
  "message": "Authentication successful",
  "token": "eyJhbGciOiJIUzI1..."
}
    </pre>
  </li>
</ul>

<h3>2️⃣ Get User Details</h3>
<ul>
  <li><strong>Endpoint:</strong> <code>GET /api/user/:username</code></li>
  <li><strong>Example Request:</strong>
    <pre>curl -X GET http://localhost:3000/api/user/john.doe</pre>
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
  <a href="../LICENSE" target="_blank">
    <img src="https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge" alt="MIT License">
  </a>
</p>

<h2>🤝 Contributing</h2>
<p>
  <a href="../CONTRIBUTING.md" target="_blank">
    <img src="https://img.shields.io/badge/Contributions-Welcome-brightgreen?style=for-the-badge" alt="Contributions Welcome">
  </a>
</p>

<h2>📩 Support</h2>
<p>
  <a href="mailto:luizhamilton.lhr@gmail.com" target="_blank">
    <img src="https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail" alt="Email Badge">
  </a>
  <a href="https://github.com/brazilianscriptguy/ActiveDirectory-SSO-Integrations/issues" target="_blank">
    <img src="https://img.shields.io/badge/GitHub%20Issues-Report%20Here-blue?style=for-the-badge&logo=github" alt="GitHub Issues Badge">
  </a>
</p>

<hr>

<p align="center">🚀 <strong>Enjoy Seamless SSO Integration!</strong> 🎯</p>
