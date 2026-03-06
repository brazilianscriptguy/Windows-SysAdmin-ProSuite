# 🔹 PHP-API: Active Directory SSO Integration with LdapRecord

![PHP](https://img.shields.io/badge/PHP-8.0+-777BB4?style=for-the-badge&logo=php&logoColor=white)
![LDAP](https://img.shields.io/badge/LDAP-Active%20Directory-0A66C2?style=for-the-badge&logo=microsoft)
![SSO](https://img.shields.io/badge/SSO-Global%20Catalog-4CAF50?style=for-the-badge)
![LdapRecord](https://img.shields.io/badge/Library-LdapRecord-6DB33F?style=for-the-badge)
![Platform](https://img.shields.io/badge/Platform-Apache%20%7C%20Nginx-D22128?style=for-the-badge)
![Security](https://img.shields.io/badge/Security-Least%20Privilege-2E7D32?style=for-the-badge)

## 📝 Overview
The **PHP-API** module provides a lightweight, secure and enterprise-grade **LDAP Single Sign-On (SSO)** integration for **Active Directory** multi-domain forests using the modern **LdapRecord** library and **Global Catalog**.

It follows security, auditability and maintainability patterns consistent with institutional Windows and PHP standards, supporting both:

- Transparent SSO (via `REMOTE_USER` when provided by the web server / reverse proxy / authentication gateway)
- Credential-based fallback authentication (manual login form)

## ✅ Key Features
- Forest-wide authentication via **Global Catalog**
- Dual authentication model (SSO + form fallback)
- Read-only service account with least privilege
- No credential persistence in source code
- Rejection of non-user objects
- Full support for secure LDAPS / TLS migration
- Centralized connection and query logic
- Compatible with legacy and modern PHP 8+ applications

## 📁 Folder Structure
```text
ActiveDirectory-SSO-Integrations/
└── PHP-API/
    ├── public/
    │   ├── index.php       # SSO detection & entry point
    │   ├── login.php       # Manual authentication fallback
    │   ├── dashboard.php   # Protected application area
    │   └── logout.php      # Secure session termination
    │
    ├── config/
    │   ├── env.php         # Loads environment variables
    │   └── ldap.php        # LdapRecord connection & auth logic
    │
    ├── .env.example        # Template – do NOT commit real values
    ├── composer.json
    └── README.md
```

## 🛠️ Prerequisites
- PHP ≥ 8.0 (recommended: 8.1–8.3)
- Apache or Nginx + PHP-FPM
- Active Directory forest with **Global Catalog** enabled
- Dedicated read-only service account
- Composer

## ⚙️ Configuration (.env)

Create `.env` from `.env.example`:

```env
# ────────────────────────────────────────────────
# Active Directory – Global Catalog Settings
# ────────────────────────────────────────────────
LDAP_HOST=dc-gc01.example.corp
LDAP_PORT=3268                  # Use 3269 after enabling LDAPS
LDAP_BASE_DN=dc=example,dc=corp
LDAP_USERNAME=svc-php-sso@example.corp
LDAP_PASSWORD=change-me-very-secure-password
LDAP_USE_SSL=false              # Set to true + port 3269 for LDAPS
LDAP_TIMEOUT=5
```

> **Security rule**  
> Never commit `.env` or real credentials.  
> Use environment variables, container secrets, or a secrets manager.

## 🚀 Installation & Quick Start

```bash
# 1. Navigate to module directory
cd ActiveDirectory-SSO-Integrations/PHP-API

# 2. Copy template and fill in values
cp .env.example .env

# 3. Install dependencies
composer install --no-dev

# 4. Start PHP built-in server (development only)
php -S localhost:8000 -t public
```

Open: `http://localhost:8000`

## 🔐 Authentication Flow

1. User requests `index.php`
2. If `REMOTE_USER` is present → attempt SSO validation
3. Otherwise → redirect to `login.php`
4. On form submit → LDAP bind attempt
5. On success → create PHP session → redirect to protected area
6. `logout.php` destroys session cleanly

**Central connection & auth logic** (`config/ldap.php` example):

```php
<?php

require_once __DIR__ . '/../vendor/autoload.php';

use LdapRecord\Container;
use LdapRecord\Configuration\ConfigurationException;
use Dotenv\Dotenv;

$dotenv = Dotenv::createImmutable(__DIR__ . '/..');
$dotenv->load();

$ldapConfig = [
    'hosts'            => [$_ENV['LDAP_HOST']],
    'port'             => (int) $_ENV['LDAP_PORT'],
    'base_dn'          => $_ENV['LDAP_BASE_DN'],
    'username'         => $_ENV['LDAP_USERNAME'],
    'password'         => $_ENV['LDAP_PASSWORD'],
    'use_ssl'          => filter_var($_ENV['LDAP_USE_SSL'], FILTER_VALIDATE_BOOLEAN),
    'use_tls'          => false, // change to true if using STARTTLS
    'version'          => 3,
    'timeout'          => (int) $_ENV['LDAP_TIMEOUT'],
    // optional: 'follow_referrals' => false,
];

try {
    $conn = new \LdapRecord\Connection($ldapConfig);
    Container::addConnection($conn, 'default');
} catch (Exception $e) {
    error_log("LDAP connection setup failed: " . $e->getMessage());
    http_response_code(503);
    die("Authentication service unavailable.");
}

// Reusable authentication function
function ldap_authenticate(string $username, string $password): ?array
{
    try {
        $conn = Container::get('default');
        
        // Attempt bind with user credentials
        $conn->auth()->attempt($username, $password);

        // Fetch basic user attributes
        $user = $conn->query()
                     ->where('samaccountname', '=', $username)
                     ->orWhere('userprincipalname', '=', $username)
                     ->select('displayname', 'samaccountname', 'userprincipalname', 'distinguishedname', 'memberof')
                     ->first();

        return $user ? $user->toArray() : null;
    } catch (\Exception $e) {
        error_log("Authentication failed: " . $e->getMessage());
        return null;
    }
}
```

## 🔒 Important Security Notes

- Always prefer **LDAPS (port 3269)** over plaintext LDAP (3268)
- Use **UPN format** (`user@domain.corp`) for bind credentials
- Enforce **LDAP Signing** and **Channel Binding** on domain controllers (Windows Server 2019+)
- Implement account lockout / password policy enforcement via AD (not in PHP)
- Log bind failures but **never** log passwords
- Regularly rotate the service account password
- Consider adding IP allow-listing or certificate-based mutual auth for stronger control

---

© 2026 Luiz Hamilton Silva — @brazilianscriptguy
