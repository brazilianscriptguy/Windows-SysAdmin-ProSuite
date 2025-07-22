## 🔹 ActiveDirectory-SSO-Integrations

### 📝 Overview

The **ActiveDirectory-SSO-Integrations** folder includes a set of **cross-platform integration models** for implementing Single Sign-On (SSO) via `LDAP` using Active Directory. Each module follows a **standardized configuration structure** to ensure consistency and ease of integration across different development stacks.

#### 🔑 Key Features

- **Cross-Technology Compatibility** — Supports .NET, Flask, Node.js, PHP, and Spring Boot  
- **Secure Bind Credentials** — Uses environment variables or secrets for LDAP authentication  
- **Modular Architecture** — Each module has its own isolated config and logic  
- **Standard LDAP Flow** — Based on the `InetOrgPerson` object for consistent logins

---

### 🛠️ Prerequisites

1. **🔐 LDAP Bind Account (InetOrgPerson)**  
   Create a delegated AD account with minimal read permissions (no admin credentials)

2. **💻 Language-Specific Environments**
   - `.NET SDK` for `DotNet-API`  
   - `Python 3.x` + `ldap3` for `Flask-API`  
   - `Node.js` + `passport-ldapauth` for `NodeJS-API`  
   - `PHP 7+` with LDAP module enabled  
   - `JDK 11+` for Spring Boot with `Spring Security LDAP`

3. **🔑 Secure Credentials**  
   Ensure the environment variable `LDAP_PASSWORD` is set securely

4. **📂 Configuration Files**
   - `appsettings.json` — DotNet  
   - `config.py` — Flask  
   - `ldap.config.json` — Node.js  
   - `.env` — PHP  
   - `application.yml` — Spring Boot

---

### 📄 Module Descriptions (Alphabetical)

| 📁 Folder        | 🔧 Description                                                                 |
|------------------|--------------------------------------------------------------------------------|
| `DotNet-API`     | ASP.NET Core project with custom LDAP middleware and JSON-based configuration |
| `Flask-API`      | Python Flask REST API using `ldap3` with centralized `.env` usage              |
| `NodeJS-API`     | Express.js using `passport-ldapauth` with structured routing                   |
| `PHP-API`        | Native PHP LDAP auth via `ldap_bind` and fallback logic                        |
| `SpringBoot-API` | Java Spring Security LDAP integration with YAML profile support                |

---

### 🚀 Usage Instructions

1. **Set Environment**  
   Define `LDAP_PASSWORD` in terminal or deployment environment

2. **Adjust Configuration**  
   Update LDAP host, port, base DN, bind DN, and filters in the config files

3. **Run the Application**

#### 📦 Run Commands

- **DotNet-API**
  ```bash
  dotnet run
  ```

- **Flask-API**
  ```bash
  pip install -r requirements.txt
  python app.py
  ```

- **NodeJS-API**
  ```bash
  npm install
  npm start
  ```

- **PHP-API**
  ```bash
  composer install
  php -S localhost:8000 -t public
  ```

- **SpringBoot-API**
  ```bash
  ./mvnw spring-boot:run
  ```

---

### 🔐 Best Practices: InetOrgPerson AD SSO Account

Use a dedicated `InetOrgPerson` object with **least-privilege delegation**:

#### 🛡️ Recommended Delegations

- **Read-Only Attributes** — Permit only necessary attributes for binding and filtering  
- **Search Scope** — Allow Base, OneLevel, or Subtree search as needed  
- **Access Controls** — Disable interactive logon, enable password expiration, and restrict delegation

#### 📌 Sample AD Account

- **User**: `HEADQ\ad-sso-authentication`  
- **DN**: `CN=ad-sso-authentication,OU=ServiceAccounts,DC=headq,DC=scriptguy`  
- **Type**: `InetOrgPerson` with *logon as service* enabled

---

### 📄 Complementary Files

- `example.env` — Flask and PHP sample environment file  
- `ldap.config.json` — LDAP config for Node.js  
- `application.yml` — Spring Boot profile for LDAP

---

### 💡 Optimization Tips

- **Least Privilege Principle** — Avoid using domain admins or high-privileged accounts  
- **Automate Environments** — Use Docker Compose with securely injected environment variables  
- **Centralize Secrets** — Use secure vaults (e.g., Azure Key Vault, HashiCorp Vault) for credentials
