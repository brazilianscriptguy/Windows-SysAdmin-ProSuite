## 🔐 ActiveDirectory-SSO-Integrations  
### LDAP Authentication · Cross-Platform SSO · Identity Federation

![Suite](https://img.shields.io/badge/Suite-AD%20SSO%20Integrations-0A66C2?style=for-the-badge&logo=windows&logoColor=white) ![Protocol](https://img.shields.io/badge/Protocol-LDAP-informational?style=for-the-badge) ![Scope](https://img.shields.io/badge/Scope-Cross--Platform%20SSO-blueviolet?style=for-the-badge) ![Security](https://img.shields.io/badge/Focus-Identity%20Security-critical?style=for-the-badge)

---

## 🧭 Overview

The **ActiveDirectory-SSO-Integrations** suite provides **cross-platform reference implementations** for enabling **Single Sign-On (SSO)** against **Microsoft Active Directory** using the **LDAP protocol**.

Each module follows a **standardized configuration model** to ensure:

- Predictable authentication flows  
- Secure credential handling  
- Consistent behavior across technology stacks  
- Easy portability between environments  

All integrations are based on the **`InetOrgPerson`** object class to maintain a **uniform and auditable identity model**.

---

## 🌟 Key Features

- 🔗 **Cross-Technology Compatibility** — .NET, Flask, Node.js, PHP, and Spring Boot  
- 🔐 **Secure Bind Credentials** — Environment variables or secret stores (no hard-coded passwords)  
- 🧩 **Modular Architecture** — Isolated configs and logic per stack  
- 📐 **Standard LDAP Flow** — Unified filters and attribute usage via `InetOrgPerson`  

---

## 🛠️ Prerequisites

- **🔐 LDAP Bind Account (`InetOrgPerson`)**  
  Delegated service account with **read-only permissions** (never use domain admins)

- **💻 Language Runtimes**
  - **.NET SDK** — `DotNet-API`  
  - **Python 3.x + ldap3** — `Flask-API`  
  - **Node.js + passport-ldapauth** — `NodeJS-API`  
  - **PHP 7+** with LDAP extension — `PHP-API`  
  - **JDK 11+** — Spring Boot + Spring Security LDAP  

- **🔑 Secure Credentials**  
  Environment variable `LDAP_PASSWORD` must be securely defined

- **📂 Configuration Files**
  - `appsettings.json` — .NET  
  - `config.py` — Flask  
  - `ldap.config.json` — Node.js  
  - `.env` — PHP  
  - `application.yml` — Spring Boot  

---

## 📁 Module Catalog

| Folder | Description |
|------|-------------|
| `DotNet-API` | ASP.NET Core API with custom LDAP middleware and JSON-based configuration |
| `Flask-API` | Python Flask REST API using `ldap3` and centralized environment variables |
| `NodeJS-API` | Express.js integration using `passport-ldapauth` |
| `PHP-API` | Native PHP LDAP authentication with fallback logic |
| `SpringBoot-API` | Spring Security LDAP integration with YAML profiles |

---

## 🚀 Usage Instructions

1. **Set Environment Variables**  
   Define `LDAP_PASSWORD` securely in the OS or deployment platform

2. **Adjust Configuration Files**  
   Update LDAP host, port, base DN, bind DN, and filters

3. **Run the Application** (per module)

### ▶️ Execution Commands

**DotNet-API**
```bash
dotnet run
```

**Flask-API**
```bash
pip install -r requirements.txt
python app.py
```

**NodeJS-API**
```bash
npm install
npm start
```

**PHP-API**
```bash
composer install
php -S localhost:8000 -t public
```

**SpringBoot-API**
```bash
./mvnw spring-boot:run
```

---

## 🔐 Best Practices — InetOrgPerson SSO Account

Use a **dedicated service account** based on `InetOrgPerson` with **least-privilege delegation**.

### 🛡️ Recommended Controls

- Read-only access to required attributes only  
- Restricted search scopes (Base / OneLevel / Subtree)  
- Disable interactive logon  
- Enable password expiration and rotation  
- Prevent delegation and lateral movement  

### 📌 Example Service Account

- **Account**: `HEADQ\ad-sso-authentication`  
- **DN**: `CN=ad-sso-authentication,OU=ServiceAccounts,DC=headq,DC=scriptguy`  
- **Type**: `InetOrgPerson` (service account)

---

## 📄 Complementary Files

- `example.env` — Sample environment file for Flask and PHP  
- `ldap.config.json` — Node.js LDAP configuration  
- `application.yml` — Spring Boot LDAP profile  

---

## 💡 Optimization Tips

- Apply **least-privilege** consistently  
- Use **Docker / CI pipelines** with injected secrets  
- Centralize credentials using **Azure Key Vault**, **HashiCorp Vault**, or equivalent  

---

© 2026 Luiz Hamilton Silva. All rights reserved.
