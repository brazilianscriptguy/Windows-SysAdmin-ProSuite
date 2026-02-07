# 🔹 PHP-API: Active Directory SSO Integration

![PHP](https://img.shields.io/badge/PHP-8.0+-777BB4?style=for-the-badge&logo=php&logoColor=white)
![LDAP](https://img.shields.io/badge/LDAP-Active%20Directory-0A66C2?style=for-the-badge&logo=microsoft)
![SSO](https://img.shields.io/badge/SSO-Global%20Catalog-4CAF50?style=for-the-badge)
![Platform](https://img.shields.io/badge/Platform-Apache%20%7C%20Nginx-D22128?style=for-the-badge)
![Security](https://img.shields.io/badge/Security-Least%20Privilege-2E7D32?style=for-the-badge)

## 📝 Overview

The **PHP-API** module provides a **lightweight, secure, and enterprise-aligned LDAP Single Sign-On (SSO)** implementation for **Active Directory** environments, designed to operate **forest-wide** using the **Global Catalog (GC)**.

This integration follows the same **design principles, security posture, and documentation standards** adopted across the **Windows‑SysAdmin‑ProSuite**, ensuring predictable behavior, auditable authentication flows, and compatibility with legacy or modern PHP deployments.

The solution supports both:
- **Transparent SSO** (via `REMOTE_USER`, when available), and
- **Credential-based fallback authentication**, maintaining usability without weakening security controls.

---

## ✅ Key Features

- 🔐 **Forest‑Wide Authentication**
  - Uses **Global Catalog (port 3268)** for multi-domain AD forests
  - No hard dependency on a single domain controller

- 🧩 **Dual Authentication Model**
  - Automatic SSO via web server integration (`REMOTE_USER`)
  - Secure manual login fallback (`login.php`)

- 🛡️ **Security‑First Design**
  - Service account with **read-only permissions**
  - Explicit blocking of **inetOrgPerson** objects
  - No credential persistence in source code

- 📜 **Auditable and Deterministic Flow**
  - Centralized LDAP logic
  - Clear authentication boundaries
  - Predictable session lifecycle

- 🧱 **Enterprise Compatibility**
  - Works with Apache or Nginx
  - Compatible with legacy PHP apps and modern PHP 8+ stacks

---

## 📁 Folder Structure

```text
ActiveDirectory-SSO-Integrations/
└── PHP-API/
    ├── public/
    │   ├── index.php        # Entry point with SSO detection
    │   ├── login.php        # Manual authentication fallback
    │   ├── dashboard.php    # Protected application area
    │   └── logout.php       # Session termination
    │
    ├── config/
    │   ├── env.php          # Loads environment variables
    │   └── ldap.php         # Central LDAP authentication logic
    │
    ├── .env.example         # LDAP credential template
    ├── composer.json        # Dependency definitions
    └── README.md            # Module documentation
```

---

## 🛠️ Prerequisites

### 1) ⚙️ Platform Requirements
- **PHP 8.0+**
- **Apache or Nginx** with PHP enabled
- **OpenLDAP / Active Directory** with Global Catalog enabled

### 2) 📦 Dependencies
- **Composer**
- `vlucas/phpdotenv` (for secure environment variable handling)

### 3) 🔑 Directory Access
- Dedicated **AD service account**
- Read-only LDAP permissions (bind + search)

---

## ⚙️ Configuration

Create a `.env` file based on `.env.example`:

```env
LDAP_URL=ldap://ldap.headq.scriptguy:3268
LDAP_BASE_DN=dc=HEADQ,dc=SCRIPTGUY
LDAP_USERNAME=ad-sso-authentication@scriptguy
LDAP_PASSWORD=YourSecurePassword
```

The file is loaded at runtime by `config/env.php` using `phpdotenv`.

> 🔒 **Best Practice**  
> Never commit `.env` files. Store secrets in environment variables or a secure vault.

---

## 🚀 How to Run

1. **Clone the repository**
   ```bash
   git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
   cd Windows-SysAdmin-ProSuite/SysAdmin-Tools/ActiveDirectory-SSO-Integrations/PHP-API
   ```

2. **Prepare environment configuration**
   ```bash
   cp .env.example .env
   ```

3. **Install dependencies**
   ```bash
   composer install
   ```

4. **Start development server**
   ```bash
   php -S localhost:8000 -t public
   ```

5. Access:
   ```
   http://localhost:8000
   ```

---

## 🔐 Authentication Flow

1. Client accesses `index.php`
2. If `$_SERVER['REMOTE_USER']` exists:
   - User is trusted and validated against AD
3. If not:
   - User is redirected to `login.php`
4. Credentials are validated via **LDAP bind**
5. Session is created and user is redirected to `dashboard.php`
6. `logout.php` destroys session securely

---

## 🔒 Security Notes

- ✔ Uses **Global Catalog** for consistent forest visibility
- ✔ No password storage in source code
- ✔ inetOrgPerson objects are rejected
- ✔ Account enable/disable logic delegated to AD
- ✔ Compatible with reverse proxies and SSO frontends

---

## 📜 License

![MIT License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)

---

## 🤝 Contributing

![Contributions Welcome](https://img.shields.io/badge/Contributions-Welcome-brightgreen?style=for-the-badge)

---

## 📩 Support

![Email](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail)
![GitHub Issues](https://img.shields.io/badge/GitHub%20Issues-Report%20Here-blue?style=for-the-badge&logo=github)

---

© 2026 Luiz Hamilton Silva — @brazilianscriptguy
