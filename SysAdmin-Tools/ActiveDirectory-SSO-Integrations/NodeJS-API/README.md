<h1>🔹 NodeJS-API</h1>
<p>
  This module demonstrates a <strong>Node.js API</strong> integrating with an <strong>LDAP server</strong> for Single Sign-On (SSO) authentication.
  The authentication is handled using <code>passport-ldapauth</code> strategy.
</p>

<h2>📁 Folder Structure</h2>
<pre>
NodeJS-API/
│
├── 📜 package.json              # Project dependencies and startup script
├── 📜 app.js                    # Main application file with Express & LDAP configuration
├── 📂 config/                    # Configuration folder
│   ├── 📜 ldap.config.json      # LDAP authentication settings
├── 📂 controllers/               # API controllers
│   ├── 📜 authController.js     # Handles authentication requests
│   ├── 📜 userController.js     # Fetches user details from Active Directory
├── 📂 middleware/                # Middleware folder
│   ├── 📜 ldapAuthMiddleware.js # Handles LDAP authentication middleware
├── 📂 routes/                    # Express routes
│   ├── 📜 authRoutes.js         # Routes for authentication endpoints
│   ├── 📜 userRoutes.js         # Routes for fetching user data
├── 📂 utils/                     # Utility functions
│   ├── 📜 logger.js             # Logs authentication events
├── 📖 README.md                 # Documentation for NodeJS-API
</pre>

<h2>🛠️ Setup Instructions</h2>
<ol>
  <li>Set the <code>LDAP_PASSWORD</code> environment variable.</li>
  <li>Navigate to the <code>NodeJS-API</code> folder and install dependencies:</li>
  <pre><code>npm install</code></pre>
  <li>Start the server:</li>
  <pre><code>npm start</code></pre>
  <li>The API will be available on <code>http://localhost:3000</code>.</li>
</ol>

<h2>📌 API Endpoints</h2>
<table border="1" width="100%">
  <thead>
    <tr>
      <th>Endpoint</th>
      <th>Method</th>
      <th>Description</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>/api/auth/login</code></td>
      <td>POST</td>
      <td>Authenticates a user and returns authentication response.</td>
    </tr>
    <tr>
      <td><code>/api/users/:username</code></td>
      <td>GET</td>
      <td>Fetches user details from Active Directory.</td>
    </tr>
  </tbody>
</table>

<h2>📩 Support</h2>
<p>
  <a href="mailto:luizhamilton.lhr@gmail.com">
    <img src="https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail" alt="Email">
  </a>
</p>
