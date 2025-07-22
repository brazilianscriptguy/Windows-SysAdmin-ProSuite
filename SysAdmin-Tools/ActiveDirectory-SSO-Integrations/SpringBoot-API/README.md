# 🔹 SpringBoot-API: Active Directory SSO Integration

## 📌 Overview

The **SpringBoot-API** module provides a **Java-based REST API** that enables **LDAP-based Single Sign-On (SSO) authentication** with **Active Directory**.  
It is built using **Spring Boot** and integrates seamlessly with LDAP for secure and scalable enterprise authentication.

---

## 📁 Folder Structure

```
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
│   ├── 📂 test/java/com/example/springbootsso/
│   │   ├── 📜 SpringBootSsoApplicationTests.java        # Unit tests
│   ├── 📖 README.md                        # Documentation
```

---

## 🛠️ Prerequisites

- **JDK 17+**
- **Apache Maven**
- **Active Directory (GC enabled)**
- **LDAP service credentials**
- **Postman or cURL** (for API testing)

---

## ⚙️ Configuration

Edit `application.yml` with your domain-wide LDAP parameters:

```yaml
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
```

---

## 🚀 How to Run

1. **Clone the repository:**
   ```bash
   git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
   cd Windows-SysAdmin-ProSuite/SysAdmin-Tools/ActiveDirectory-SSO-Integrations/SpringBoot-API
   ```

2. **Set LDAP credentials as environment variable:**
   ```bash
   export LDAP_PASSWORD='your-secure-password'
   ```

3. **Build and launch:**
   ```bash
   mvn clean package
   java -jar target/SpringBootSSO-1.0.0.jar
   ```

---

## 🔄 API Endpoints

### 1️⃣ Authenticate User

- **POST:** `/api/auth/login`
- **Payload:**
  ```json
  {
    "username": "john.doe",
    "password": "SuperSecretPassword"
  }
  ```
- **Response:**
  ```json
  {
    "message": "Authentication successful"
  }
  ```

### 2️⃣ Get User Details

- **GET:** `/api/user/{username}`
- **Example:**
  ```bash
  curl -X GET http://localhost:8080/api/user/john.doe
  ```
- **Sample Output:**
  ```json
  {
    "username": "john.doe",
    "displayName": "John Doe",
    "email": "john.doe@example.com",
    "department": "IT",
    "role": "User"
  }
  ```

---

## 📜 License

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/LICENSE.txt)

---

## 🤝 Contributing

[![Contributions Welcome](https://img.shields.io/badge/Contributions-Welcome-brightgreen?style=for-the-badge)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/CONTRIBUTING.md)

---

## 📩 Support

[![Email Badge](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com)  
[![GitHub Issues](https://img.shields.io/badge/GitHub%20Issues-Report%20Here-blue?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/BUG_REPORT.md)

---

<p align="center">💼 <strong>Powerful AD SSO in Enterprise Java Applications</strong> 🔐</p>
