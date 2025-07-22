# 🔹 PHP-API: Active Directory SSO Integration

## 📌 Overview

The **PHP-API** module implements **LDAP-based Single Sign-On (SSO)** with **Active Directory**, designed to work across an entire AD forest via **Global Catalog (GC)**.  
It offers a lightweight, secure, and standardized approach to authenticating users via AD in legacy or modern PHP environments.

---

## 📁 Folder Structure

```
ActiveDirectory-SSO-Integrations/
│
├── 📂 PHP-API/                      # Parent folder for PHP API integration
│   ├── 📂 public/                   # Publicly accessible endpoints
│   │   ├── 📜 index.php             # Entry point with SSO detection via $_SERVER['REMOTE_USER']
│   │   ├── 📜 login.php             # Manual login fallback
│   │   ├── 📜 dashboard.php         # Protected user dashboard
│   │   └── 📜 logout.php            # Destroys session and logs out
│
│   ├── 📂 config/                   # Configuration and LDAP logic
│   │   ├── 📜 env.php               # Loads .env credentials into runtime
│   │   └── 📜 ldap.php              # Handles LDAP connection and authentication
│
│   ├── 📜 .env.example              # Example file for LDAP credentials
│   ├── 📜 composer.json             # Project dependencies
│   └── 📜 README.md                 # Documentation for PHP-API integration
```

---

## 🛠️ Prerequisites

- **PHP 8.0+**
- **OpenLDAP or Active Directory** with Global Catalog enabled
- **Apache/Nginx with PHP support**
- **Composer (dependency manager)**

---

## ⚙️ Configuration

Edit `.env` file with your AD service account and forest-wide settings:

```env
LDAP_URL=ldap://ldap.headq.scriptguy:3268
LDAP_BASE_DN=dc=HEADQ,dc=SCRIPTGUY
LDAP_USERNAME=ad-sso-authentication@scriptguy
LDAP_PASSWORD=YourSecurePassword
```

Load it in runtime using `env.php` with `vlucas/phpdotenv` support.

---

## 🚀 How to Run

1. **Clone the repository:**
   ```bash
   git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
   cd Windows-SysAdmin-ProSuite/SysAdmin-Tools/ActiveDirectory-SSO-Integrations/PHP-API
   ```

2. **Create your environment file:**
   ```bash
   cp .env.example .env
   ```

3. **Install dependencies with Composer:**
   ```bash
   composer install
   ```

4. **Run the development server:**
   ```bash
   php -S localhost:8000 -t public
   ```

---

## 🔐 LDAP Authentication Highlights

- Forest-wide querying using **Global Catalog (port 3268)**
- **inetOrgPerson accounts are explicitly blocked** from logging in
- **Account enable/disable status is ignored** (AD handles that)
- Service account does not require elevated privileges (read-only)

---

## 💻 Sample Authentication Flow

1. User accesses `index.php`
2. If `$_SERVER['REMOTE_USER']` is available, SSO proceeds
3. If not, fallback to `login.php` for manual credential input
4. Authenticated users redirected to `dashboard.php`

---

## 📜 License

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/LICENSE)

---

## 🤝 Contributing

[![Contributions Welcome](https://img.shields.io/badge/Contributions-Welcome-brightgreen?style=for-the-badge)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/CONTRIBUTING.md)

---

## 📩 Support

[![Email Badge](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com)  
[![GitHub Issues](https://img.shields.io/badge/GitHub%20Issues-Report%20Here-blue?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/BUG_REPORT.md)

---

<p align="center">🌐 <strong>Bring AD SSO to your PHP apps — Fast and Secure!</strong> 🔒</p>
