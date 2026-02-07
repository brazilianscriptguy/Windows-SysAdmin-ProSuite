# 🔹 PHP-API: Active Directory SSO Integration

![PHP](https://img.shields.io/badge/PHP-8.0+-777BB4?style=for-the-badge&logo=php&logoColor=white)
![LDAP](https://img.shields.io/badge/Auth-LDAP%20%7C%20AD-0A66C2?style=for-the-badge)
![SSO](https://img.shields.io/badge/SSO-Active%20Directory-2E7D32?style=for-the-badge)
![Security](https://img.shields.io/badge/Security-Enterprise--Grade-4CAF50?style=for-the-badge)

## 📌 Overview

The **PHP-API** module implements **LDAP-based Single Sign-On (SSO)** with **Active Directory**, designed to operate across an **entire AD forest** using the **Global Catalog (GC)**.

It provides a **lightweight, auditable, and secure authentication layer** for both **legacy and modern PHP applications**, following the same security and design principles used across the **Windows-SysAdmin-ProSuite**.

This integration is ideal for environments where:
- IIS/Apache-based applications still rely on PHP
- Forest-wide authentication is required
- Minimal privileges and predictable behavior are mandatory

---

## 📁 Folder Structure

```text
ActiveDirectory-SSO-Integrations/
│
├── PHP-API/
│   ├── public/
│   │   ├── index.php        # Entry point with SSO auto-detection
│   │   ├── login.php        # Manual login fallback
│   │   ├── dashboard.php   # Protected resource
│   │   └── logout.php      # Session termination
│   │
│   ├── config/
│   │   ├── env.php         # Loads environment variables
│   │   └── ldap.php        # LDAP bind and authentication logic
│   │
│   ├── .env.example        # Environment template
│   ├── composer.json      # Dependency definitions
│   └── README.md           # Module documentation
```

---

## 🛠️ Prerequisites

- **PHP 8.0 or later**
- **Active Directory** with **Global Catalog enabled**
- **Apache or Nginx** with PHP support
- **Composer** (dependency manager)
- PHP extensions:
  - `ldap`
  - `mbstring`
  - `openssl`

---

## ⚙️ Configuration

Create a `.env` file based on `.env.example`:

```env
LDAP_URL=ldap://ldap.headq.scriptguy:3268
LDAP_BASE_DN=dc=HEADQ,dc=SCRIPTGUY
LDAP_USERNAME=ad-sso-authentication@scriptguy
LDAP_PASSWORD=YourSecurePassword
```

The configuration is loaded at runtime via `vlucas/phpdotenv`.

> 🔐 **Best Practice**:  
> The LDAP bind account must be **read-only**, non-interactive, and excluded from application logon.

---

## 🚀 How to Run

1. **Clone the repository**
```bash
git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
cd Windows-SysAdmin-ProSuite/SysAdmin-Tools/ActiveDirectory-SSO-Integrations/PHP-API
```

2. **Create environment file**
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

Access the application at:  
`http://localhost:8000`

---

## 🔐 LDAP Authentication Design

- Forest-wide authentication via **Global Catalog (TCP 3268)**
- Explicit block of **service / inetOrgPerson accounts**
- No password caching
- No elevated directory permissions required
- All validation handled server-side

---

## 🔄 Authentication Flow

1. User accesses `index.php`
2. If `$_SERVER['REMOTE_USER']` exists → automatic SSO
3. Otherwise → fallback to `login.php`
4. Credentials validated against AD
5. Authorized users redirected to `dashboard.php`
6. Sessions destroyed via `logout.php`

---

## 🔒 Security Notes

- No credentials stored in code or logs
- Environment-based secret management
- Compatible with reverse proxies and IIS rewrite rules
- Safe for intranet and DMZ deployments

---

## 📜 License

[![MIT License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/LICENSE.txt)

---

## 🤝 Contributing

[![Contributions Welcome](https://img.shields.io/badge/Contributions-Welcome-brightgreen?style=for-the-badge)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/CONTRIBUTING.md)

---

## 📩 Support

[![Email](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com)
[![GitHub Issues](https://img.shields.io/badge/GitHub%20Issues-Report%20Here-blue?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/BUG_REPORT.md)

---

<p align="center">🌐 <strong>Enterprise‑grade AD SSO for PHP applications</strong> 🔒</p>

© 2026 Luiz Hamilton Silva. All rights reserved.
