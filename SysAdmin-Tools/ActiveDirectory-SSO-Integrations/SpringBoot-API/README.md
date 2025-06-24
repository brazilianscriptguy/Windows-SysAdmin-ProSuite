<h1>🔹 SpringBoot-API: Active Directory SSO Integration</h1>

<h2>📌 Overview</h2>
<p>
  The <strong>SpringBoot-API</strong> module provides a <strong>Java-based REST API</strong> 
  that enables <strong>LDAP-based Single Sign-On (SSO) authentication</strong> with <strong>Active Directory</strong>.
  It is built using <strong>Spring Boot</strong> and integrates seamlessly with LDAP for secure and scalable enterprise authentication.
</p>

<h2>📁 Folder Structure</h2>
<pre>
ActiveDirectory-SSO-Integrations/
│
├── 📂 SpringBoot-API/                     
│   ├── 📜 pom.xml                           # Maven build and dependency config
│   ├── 📂 src/
│   │   ├── 📂 main/
│   │   │   ├── 📂 java/com/example/springbootsso/
│   │   │   │   ├── 📜 SpringBootSsoApplication.java     # Main application launcher
│   │   │   │   ├── 📂 config/
│   │   │   │   │   ├── 📜 SecurityConfig.java           # Spring Security config
│   │   │   │   │   ├── 📜 LdapConfig.java               # LDAP setup
│   │   │   │   ├── 📂 controllers/
│   │   │   │   │   ├── 📜 AuthController.java           # Login/auth endpoints
│   │   │   │   │   ├── 📜 UserController.java           # User info endpoints
│   │   │   │   ├── 📂 services/
│   │   │   │   │   ├── 📜 LdapService.java              # LDAP auth logic
│   │   │   │   ├── 📂 models/
│   │   │   │   │   ├── 📜 UserModel.java                # User schema model
│   │   │   │   ├── 📂 middleware/
│   │   │   │   │   ├── 📜 LdapAuthMiddleware.java       # Custom LDAP enforcement
│   │   │   ├── 📂 resources/
│   │   │   │   ├── 📜 application.yml                   # Base config
│   │   │   │   ├── 📜 application-dev.yml               # Dev-specific settings
│   │   │   │   ├── 📜 application-prod.yml              # Prod-specific settings
│   │   ├── 📂 test/java/com/example/springbootsso/
│   │   │   ├── 📜 SpringBootSsoApplicationTests.java    # Unit tests
│   ├── 📖 README.md                        # Documentation
</pre>

<h2>🛠️ Prerequisites</h2>
<ul>
  <li><strong>JDK 17+</strong></li>
  <li><strong>Apache Maven</strong></li>
  <li><strong>Active Directory (GC enabled)</strong></li>
  <li><strong>LDAP service credentials</strong></li>
  <li><strong>Postman or cURL</strong> (for API testing)</li>
</ul>

<h2>⚙️ Configuration</h2>
<p>Edit <code>application.yml</code> with your domain-wide LDAP parameters:</p>

<pre>
spring:
  ldap:
    urls: ldap://ldap.headq.scriptguy:3268
    base: dc=headq,dc=scriptguy
    username: ad-sso-authentication@headq
    password: ${LDAP_PASSWORD}
    user-search-filter: (sAMAccountName={0})
    group-search-base: dc=headq,dc=scriptguy
    group-search-filter: (member={0})

server:
  port: 8080
</pre>

<h2>🚀 How to Run</h2>
<ol>
  <li><strong>Clone the repository:</strong>
    <pre>git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
cd Windows-SysAdmin-ProSuite/SysAdmin-Tools/ActiveDirectory-SSO-Integrations/SpringBoot-API</pre>
  </li>
  <li><strong>Set LDAP credentials as environment variable:</strong>
    <pre>export LDAP_PASSWORD='your-secure-password'</pre>
  </li>
  <li><strong>Build and launch:</strong>
    <pre>mvn clean package
java -jar target/SpringBootSSO-1.0.0.jar</pre>
  </li>
</ol>

<h2>🔄 API Endpoints</h2>

<h3>1️⃣ Authenticate User</h3>
<ul>
  <li><strong>POST:</strong> <code>/api/auth/login</code></li>
  <li><strong>Payload:</strong>
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
  <li><strong>GET:</strong> <code>/api/user/{username}</code></li>
  <li><strong>Example:</strong>
    <pre>curl -X GET http://localhost:8080/api/user/john.doe</pre>
  </li>
  <li><strong>Sample Output:</strong>
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

<p align="center">💼 <strong>Powerful AD SSO in Enterprise Java Applications</strong> 🔐</p>
