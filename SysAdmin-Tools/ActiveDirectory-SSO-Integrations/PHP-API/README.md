<h1>🔹 PHP-API: Active Directory SSO Integration</h1>

<h2>📌 Overview</h2>
<p>
  The <strong>PHP-API</strong> module implements <strong>LDAP-based Single Sign-On (SSO)</strong> with 
  <strong>Active Directory</strong>, designed to work across an entire AD forest via <strong>Global Catalog (GC)</strong>. 
  It offers a lightweight, secure, and standardized approach to authenticating users via AD in legacy or modern PHP environments.
</p>

<h2>📁 Folder Structure</h2>
<pre>
ActiveDirectory-SSO-Integrations/
│
├── 📂 PHP-API/                      # Parent folder for PHP API integration
│   ├── 📂 public/                   # Publicly accessible endpoints
│   │   ├── 📜 index.php            # Entry point with SSO detection via $_SERVER['REMOTE_USER']
│   │   ├── 📜 login.php            # Manual login fallback
│   │   ├── 📜 dashboard.php        # Protected user dashboard
│   │   └── 📜 logout.php           # Destroys session and logs out
│
│   ├── 📂 config/                  # Configuration and LDAP logic
│   │   ├── 📜 env.php             # Loads .env credentials into runtime
│   │   └── 📜 ldap.php            # Handles LDAP connection and authentication
│
│   ├── 📜 .env.example             # Example file for LDAP credentials
│   ├── 📜 composer.json            # Project dependencies
│   └── 📜 README.md                # Documentation for PHP-API integration
</pre>

<h2>🛠️ Prerequisites</h2>
<ul>
  <li><strong>PHP 8.0+</strong></li>
  <li><strong>OpenLDAP or Active Directory</strong> with Global Catalog enabled</li>
  <li><strong>Apache/Nginx with PHP support</strong></li>
  <li><strong>Composer (dependency manager)</strong></li>
</ul>

<h2>⚙️ Configuration</h2>
<p>Edit <code>.env</code> file with your AD service account and forest-wide settings:</p>

<pre>
LDAP_URL=ldap://ldap.headq.scriptguy:3268
LDAP_BASE_DN=dc=HEADQ,dc=SCRIPTGUY
LDAP_USERNAME=ad-sso-authentication@scriptguy
LDAP_PASSWORD=YourSecurePassword
</pre>

<p>Load it in runtime using <code>env.php</code> with <code>vlucas/phpdotenv</code> support.</p>

<h2>🚀 How to Run</h2>
<ol>
  <li><strong>Clone the repository:</strong>
    <pre>git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
cd Windows-SysAdmin-ProSuite/SysAdmin-Tools/ActiveDirectory-SSO-Integrations/PHP-API</pre>
  </li>
  <li><strong>Create your environment file:</strong>
    <pre>cp .env.example .env</pre>
  </li>
  <li><strong>Install dependencies with Composer:</strong>
    <pre>composer install</pre>
  </li>
  <li><strong>Run the development server:</strong>
    <pre>php -S localhost:8000 -t public</pre>
  </li>
</ol>

<h2>🔐 LDAP Authentication Highlights</h2>
<ul>
  <li>Forest-wide querying using <strong>Global Catalog (port 3268)</strong></li>
  <li><strong>inetOrgPerson accounts are explicitly blocked</strong> from logging in</li>
  <li><strong>Account enable/disable status is ignored</strong> (AD handles that)</li>
  <li>Service account does not require elevated privileges (read-only)</li>
</ul>

<h2>💻 Sample Authentication Flow</h2>
<ol>
  <li>User accesses <code>index.php</code></li>
  <li>If <code>$_SERVER['REMOTE_USER']</code> is available, SSO proceeds</li>
  <li>If not, fallback to <code>login.php</code> for manual credential input</li>
  <li>Authenticated users redirected to <code>dashboard.php</code></li>
</ol>

<h2>📜 License</h2>
<p>
  <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/LICENSE" target="_blank">
    <img src="https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge" alt="MIT License">
  </a>
</p>

<h2>🤝 Contributing</h2>
<p>
  <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/CONTRIBUTING.md" target="_blank">
    <img src="https://img.shields.io/badge/Contributions-Welcome-brightgreen?style=for-the-badge" alt="Contributions Welcome">
  </a>
</p>

<h2>📩 Support</h2>
<p>
  <a href="mailto:luizhamilton.lhr@gmail.com" target="_blank">
    <img src="https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail" alt="Email Badge">
  </a>
  <a href="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/BUG_REPORT.md" target="_blank">
    <img src="https://img.shields.io/badge/GitHub%20Issues-Report%20Here-blue?style=for-the-badge&logo=github" alt="GitHub Issues Badge">
  </a>
</p>

<hr>

<p align="center">🌐 <strong>Bring AD SSO to your PHP apps — Fast and Secure!</strong> 🔒</p>
