<h1>🔹 Flask-API: Active Directory SSO Integration</h1>

<h2>📌 Overview</h2>
<p>
  The <strong>Flask-API</strong> is a <strong>Python-based REST API</strong> built with 
  <strong>Flask</strong> that enables <strong>LDAP-based Single Sign-On (SSO) authentication</strong> 
  with <strong>Active Directory</strong> using the <code>ldap3</code> library.
</p>

<h2>📁 Folder Structure</h2>
<pre>
ActiveDirectory-SSO-Integrations/
│
├── 📂 Flask-API/                   # Parent folder for Flask API integration
│   ├── 📜 requirements.txt         # Python dependencies
│   ├── 📝 app.py                   # Main application file with LDAP authentication logic
│   ├── 📜 config.py                # LDAP configuration settings
│   ├── 📂 controllers/              # API controllers
│   │   ├── 📜 auth_controller.py   # Handles authentication requests
│   │   ├── 📜 user_controller.py   # Fetches user details from Active Directory
│   ├── 📂 middleware/               # Middleware for LDAP authentication
│   │   ├── 📜 ldap_auth_middleware.py  # Middleware for enforcing authentication
│   ├── 📂 utils/                    # Utility functions
│   │   ├── 📜 logger.py            # Logs authentication events
│   ├── 📖 README.md                 # Documentation for Flask-API
</pre>

<h2>🛠️ Prerequisites</h2>
<ul>
  <li><strong>Python 3.8+</strong></li>
  <li><strong>Active Directory instance</strong></li>
  <li><strong>LDAP access credentials</strong></li>
  <li><strong>Postman or cURL (for testing API requests)</strong></li>
</ul>

<h2>⚙️ Configuration</h2>
<p>Modify <code>config.py</code> with your <strong>LDAP credentials</strong>:</p>

<pre>
LDAP_CONFIG = {
    "LDAP_SERVER": "ldap://ldap.headq.scriptguy:3268",
    "BASE_DN": "dc=headq,dc=scriptguy",
    "BIND_DN": "cn=ad-sso-authentication,ou=ServiceAccounts,dc=headq,dc=scriptguy",
    "BIND_PASSWORD": os.getenv("LDAP_PASSWORD"),
    "USER_FILTER": "(sAMAccountName={0})"
}
</pre>

<h2>🚀 How to Run</h2>
<ol>
  <li><strong>Clone the repository:</strong>
    <pre>git clone https://github.com/brazilianscriptguy/ActiveDirectory-SSO-Integrations.git
cd ActiveDirectory-SSO-Integrations/Flask-API</pre>
  </li>
  <li><strong>Set the LDAP password as an environment variable:</strong>
    <pre>export LDAP_PASSWORD='your-secure-password'</pre>
  </li>
  <li><strong>Install dependencies:</strong>
    <pre>pip install -r requirements.txt</pre>
  </li>
  <li><strong>Run the application:</strong>
    <pre>python app.py</pre>
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
  <a href="LICENSE" target="_blank">
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
