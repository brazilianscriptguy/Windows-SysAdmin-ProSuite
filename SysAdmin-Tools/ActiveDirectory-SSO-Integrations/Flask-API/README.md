<h1>🔹 Flask-API: Active Directory SSO Integration</h1>

<h2>📌 Overview</h2>
<p>
  The <strong>Flask-API</strong> is a <strong>Flask-based REST API</strong> that enables 
  <strong>LDAP-based Single Sign-On (SSO) authentication</strong> with <strong>Active Directory</strong>.
</p>

<h2>📁 Folder Structure</h2>
<pre>
ActiveDirectory-SSO-Integrations/
│
├── 📂 Flask-API/                  # Parent folder for Python API integration
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
  <li><strong>Flask</strong></li>
  <li><strong>ldap3 library</strong></li>
  <li><strong>Active Directory instance</strong></li>
  <li><strong>LDAP credentials with read permissions</strong></li>
</ul>

<h2>🚀 How to Run</h2>
<ol>
  <li>Clone the repository:
    <pre>git clone https://github.com/brazilianscriptguy/ActiveDirectory-SSO-Integrations.git
cd ActiveDirectory-SSO-Integrations/Flask-API</pre>
  </li>
  <li>Set the LDAP password as an environment variable:
    <pre>export LDAP_PASSWORD='your-secure-password'</pre>
  </li>
  <li>Install dependencies:
    <pre>pip install -r requirements.txt</pre>
  </li>
  <li>Run the Flask application:
    <pre>python app.py</pre>
  </li>
</ol>

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
</p>

<hr>

<p align="center">🚀 <strong>Enjoy Seamless SSO Integration!</strong> 🎯</p>
