<h1>🔹 SpringBoot-API: Active Directory SSO Integration</h1>

<h2>📌 Overview</h2>
<p>
  The <strong>SpringBoot-API</strong> module provides a <strong>Java-based REST API</strong> 
  that enables <strong>LDAP-based Single Sign-On (SSO) authentication</strong> with <strong>Active Directory</strong>.
  It is built using <strong>Spring Boot</strong> and integrates seamlessly with LDAP.
</p>

<h2>📁 Folder Structure</h2>
<pre>
ActiveDirectory-SSO-Integrations/
│
├── 📂 SpringBoot-API/                     # Parent folder for Spring Boot API integration
│   ├── 📜 pom.xml                          # Maven dependencies and build configuration
│   ├── 📂 src/
│   │   ├── 📂 main/
│   │   │   ├── 📂 java/com/example/springbootsso/
│   │   │   │   ├── 📜 SpringBootSsoApplication.java   # Main application entry point
│   │   │   │   ├── 📂 config/              # Configuration package
│   │   │   │   │   ├── 📜 SecurityConfig.java        # Spring Security LDAP config
│   │   │   │   │   ├── 📜 LdapConfig.java            # LDAP Connection settings
│   │   │   │   ├── 📂 controllers/         # API controllers
│   │   │   │   │   ├── 📜 AuthController.java        # Handles authentication requests
│   │   │   │   │   ├── 📜 UserController.java        # Fetches user details
│   │   │   │   ├── 📂 services/            # Service layer
│   │   │   │   │   ├── 📜 LdapService.java         # Handles LDAP authentication logic
│   │   │   │   ├── 📂 models/              # Data models
│   │   │   │   │   ├── 📜 UserModel.java          # Represents user schema
│   │   │   │   ├── 📂 middleware/          # Middleware logic
│   │   │   │   │   ├── 📜 LdapAuthMiddleware.java   # Custom authentication enforcement
│   │   │   ├── 📂 resources/
│   │   │   │   ├── 📜 application.yml        # Main configuration file
│   │   │   │   ├── 📜 application-dev.yml    # Development-specific configuration
│   │   │   │   ├── 📜 application-prod.yml   # Production-specific configuration
│   │   ├── 📂 test/java/com/example/springbootsso/
│   │   │   ├── 📜 SpringBootSsoApplicationTests.java  # Unit tests for API
│   ├── 📖 README.md                        # Documentation for SpringBoot-API
</pre>

<h2>🛠️ Prerequisites</h2>
<ul>
  <li><strong>JDK 17 or later</strong></li>
  <li><strong>Apache Maven</strong> (to build the project)</li>
  <li><strong>Active Directory instance</strong></li>
  <li><strong>LDAP access credentials</strong></li>
  <li><strong>Postman (for testing API requests)</strong></li>
</ul>

<h2>⚙️ Configuration</h2>
<p>Modify <code>application.yml</code> with your <strong>LDAP credentials</strong>:</p>

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
    <pre>git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/tree/main/SysAdmin-Tools/ActiveDirectory-SSO-Integrations/
cd ActiveDirectory-SSO-Integrations/SpringBoot-API</pre>
  </li>
  <li><strong>Set the LDAP password as an environment variable:</strong>
    <pre>export LDAP_PASSWORD='your-secure-password'</pre>
  </li>
  <li><strong>Build and run the application:</strong>
    <pre>mvn clean package
java -jar target/SpringBootSSO-1.0.0.jar</pre>
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
    <pre>curl -X GET http://localhost:8080/api/user/john.doe</pre>
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
