<h1>🔹 SpringBoot-API: Active Directory SSO Integration</h1>

<h2>📌 Overview</h2>
<p>
  The <strong>SpringBoot-API</strong> is a <strong>Java-based REST API</strong> built with 
  <strong>Spring Boot</strong> that enables <strong>LDAP-based Single Sign-On (SSO) authentication</strong> 
  with <strong>Active Directory</strong>. The configuration is externalized via <code>application.yml</code> 
  allowing easy adaptation across different environments.
</p>

<h2>📁 Folder Structure</h2>
<pre>
ActiveDirectory-SSO-Integrations/
│
├── 📂 SpringBoot-API/                # Parent folder for Spring Boot API integration
│   ├── 📜 pom.xml                    # Maven project dependencies
│   ├── 📜 application.yml             # LDAP configuration settings
│   ├── 📜 README.md                   # Documentation for SpringBoot-API
│   ├── 📂 src/
│   │   ├── 📂 main/
│   │   │   ├── 📂 java/com/example/sso/
│   │   │   │   ├── 📜 SpringBootSsoApplication.java  # Main application entry point
│   │   │   │   ├── 📂 config/
│   │   │   │   │   ├── 📜 LdapSecurityConfig.java  # LDAP Authentication config
│   │   │   │   ├── 📂 controllers/
│   │   │   │   │   ├── 📜 AuthController.java  # Handles authentication requests
│   │   │   │   │   ├── 📜 UserController.java  # Fetches user details from LDAP
│   │   │   │   ├── 📂 services/
│   │   │   │   │   ├── 📜 LdapService.java  # Business logic for LDAP authentication
│   │   │   │   ├── 📂 middleware/
│   │   │   │   │   ├── 📜 LdapAuthFilter.java  # Middleware for enforcing authentication
│   │   │   │   ├── 📂 models/
│   │   │   │   │   ├── 📜 UserModel.java   # Represents user object schema
│   │   │   ├── 📂 resources/
│   │   │   │   ├── 📜 application.yml      # Spring Boot and LDAP configuration
│   │   │   │   ├── 📜 log4j2.xml           # Logging configuration
│   │   ├── 📂 test/
│   │   │   ├── 📜 LdapAuthTests.java       # Test cases for authentication
</pre>

<h2>🛠️ Prerequisites</h2>
<ul>
  <li><strong>Java 11+ installed</strong></li>
  <li><strong>Maven (for dependency management)</strong></li>
  <li><strong>Active Directory instance</strong></li>
  <li><strong>LDAP access credentials</strong></li>
  <li><strong>Postman or cURL (for testing API requests)</strong></li>
</ul>

<h2>⚙️ Configuration</h2>
<p>Modify <code>application.yml</code> with your <strong>LDAP credentials</strong>:</p>

<pre>
spring:
  ldap:
    urls: ldap://ldap.headq.scriptguy:3268
    base: dc=headq,dc=scriptguy
    username: cn=ad-sso-authentication,ou=ServiceAccounts,dc=headq,dc=scriptguy
    password: ${LDAP_PASSWORD}
    user-search-filter: (sAMAccountName={0})
    group-search-base: dc=headq,dc=scriptguy
    group-search-filter: (member={0})
</pre>

<h2>🚀 How to Run</h2>
<ol>
  <li><strong>Clone the repository:</strong>
    <pre>git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
cd Windows-SysAdmin-ProSuite/SysAdmin-Tools/ActiveDirectory-SSO-Integrations/SpringBoot-API</pre>
  </li>
  <li><strong>Set the LDAP password as an environment variable:</strong>
    <pre>export LDAP_PASSWORD='your-secure-password'</pre>
  </li>
  <li><strong>Build the project using Maven:</strong>
    <pre>mvn clean package</pre>
  </li>
  <li><strong>Run the application:</strong>
    <pre>java -jar target/springboot-sso.jar</pre>
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
  <a href="LICENSE" target="_blank">
    <img src="https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge" alt="MIT License">
  </a>
</p>

<hr>

<p align="center">🚀 <strong>Enjoy Seamless SSO Integration!</strong> 🎯</p>
