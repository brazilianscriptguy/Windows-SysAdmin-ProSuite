# 🔹 SpringBoot-API: Active Directory SSO Integration

![Java](https://img.shields.io/badge/Java-17+-ED8B00?style=for-the-badge&logo=java&logoColor=white)
![Spring](https://img.shields.io/badge/Spring%20Boot-3.x-6DB33F?style=for-the-badge&logo=springboot&logoColor=white)
![LDAP](https://img.shields.io/badge/Auth-LDAP%20SSO-4CAF50?style=for-the-badge)
![ActiveDirectory](https://img.shields.io/badge/Directory-Active%20Directory-0078D4?style=for-the-badge)
![Enterprise](https://img.shields.io/badge/Grade-Enterprise-blueviolet?style=for-the-badge)

## 📝 Overview

The **SpringBoot-API** module delivers an **enterprise-ready Java REST API** that implements **LDAP-based Single Sign-On (SSO)** authentication against **Microsoft Active Directory**.

It follows the same **architecture, security posture, configuration model, and documentation standards** used across the **ActiveDirectory-SSO-Integrations** suite, ensuring predictable behavior, auditability, and ease of integration in corporate environments.

This implementation is suitable for:
- Enterprise backends
- Microservices
- Internal portals
- Cross-domain / forest-wide authentication via **Global Catalog (GC)**

---

## ✅ Key Features

- 🔐 **LDAP / AD Authentication**
  - Native Spring Security + LDAP integration
  - Forest-wide authentication via **Global Catalog (3268)**

- 🧩 **Modular & Profile-Based Configuration**
  - `application.yml`, `application-dev.yml`, `application-prod.yml`
  - Environment-variable driven secrets

- 🏢 **Enterprise Security Design**
  - Least-privilege service account
  - No hardcoded credentials
  - Separation of config, auth, and controllers

- 🔄 **RESTful Endpoints**
  - Authentication
  - User identity lookup
  - Ready for JWT or downstream SSO chaining

---

## 🛠️ Prerequisites

### 1️⃣ Java Platform
- **JDK 17+**
- Recommended distributions: Temurin, Oracle JDK, OpenJDK

### 2️⃣ Build Tool
- **Apache Maven 3.9+**

### 3️⃣ Directory Services
- Microsoft **Active Directory**
- **Global Catalog enabled**
- LDAP service account with **read-only permissions**

### 4️⃣ Testing Tools
- Postman or cURL

---

## 📁 Project Structure

```
SpringBoot-API/
├── pom.xml
├── src/
│   ├── main/
│   │   ├── java/com/example/springbootsso/
│   │   │   ├── SpringBootSsoApplication.java
│   │   │   ├── config/
│   │   │   │   ├── SecurityConfig.java
│   │   │   │   └── LdapConfig.java
│   │   │   ├── controllers/
│   │   │   │   ├── AuthController.java
│   │   │   │   └── UserController.java
│   │   │   ├── services/
│   │   │   │   └── LdapService.java
│   │   │   └── models/
│   │   │       └── UserModel.java
│   │   └── resources/
│   │       ├── application.yml
│   │       ├── application-dev.yml
│   │       └── application-prod.yml
│   └── test/
│       └── SpringBootSsoApplicationTests.java
└── README.md
```

---

## ⚙️ Configuration

Configure LDAP and AD parameters in `application.yml`:

```yaml
spring:
  ldap:
    urls: ldap://ldap.headq.scriptguy:3268
    base: dc=headq,dc=scriptguy
    username: ad-sso-authentication@headq
    password: ${LDAP_PASSWORD}
    user-search-filter: (sAMAccountName={0})
    group-search-base: dc=headq,dc=scriptguy

server:
  port: 8080
```

> 🔐 **Security note:**  
> Always inject `LDAP_PASSWORD` via environment variables or secret managers.

---

## 🚀 Running the Application

### 1️⃣ Set Environment Variable

```bash
export LDAP_PASSWORD='your-secure-password'
```

### 2️⃣ Build the Project

```bash
mvn clean package
```

### 3️⃣ Start the API

```bash
java -jar target/SpringBootSSO-1.0.0.jar
```

The API will be available at:  
`http://localhost:8080`

---

## 🔄 API Endpoints

### 🔑 Authenticate User

**POST** `/api/auth/login`

```json
{
  "username": "john.doe",
  "password": "SuperSecretPassword"
}
```

### 👤 Retrieve User Details

**GET** `/api/user/{username}`

```bash
curl http://localhost:8080/api/user/john.doe
```

---

## 🔒 Security & Best Practices

- Use **dedicated LDAP service accounts**
- Never grant Domain Admin privileges
- Prefer **Global Catalog** for multi-domain forests
- Externalize secrets (Vault, Azure Key Vault, Kubernetes Secrets)
- Add TLS (`ldaps://`) in production environments

---

## 📜 License

[![MIT License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/LICENSE.txt)

---

## 📩 Support

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com)
[![GitHub Issues](https://img.shields.io/badge/GitHub-Issues-blue?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/BUG_REPORT.md)

---


