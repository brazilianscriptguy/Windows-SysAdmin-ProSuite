# 🔹 PHP-API: Active Directory SSO Integration with LdapRecord

![PHP](https://img.shields.io/badge/PHP-8.1+-777BB4?style=for-the-badge&logo=php&logoColor=white)
![LDAP](https://img.shields.io/badge/LDAP-Active%20Directory-0A66C2?style=for-the-badge&logo=microsoft)
![SSO](https://img.shields.io/badge/SSO-Global%20Catalog-4CAF50?style=for-the-badge)
![LdapRecord](https://img.shields.io/badge/Library-LdapRecord-6DB33F?style=for-the-badge)
![Platform](https://img.shields.io/badge/Platform-Apache%20%7C%20Nginx-D22128?style=for-the-badge)
![Security](https://img.shields.io/badge/Security-Least%20Privilege-2E7D32?style=for-the-badge)

## 📝 Overview

Lightweight, secure and enterprise-grade **LDAP Single Sign-On (SSO)** module for **Active Directory** multi-domain forests using **LdapRecord** and **Global Catalog**.

Supports:
- Transparent SSO via `REMOTE_USER` (Kerberos/NTLM/reverse-proxy)
- Credential-based fallback (login form)

Follows institutional Windows/PHP security & maintainability patterns.

## ✅ Key Features

- Forest-wide authentication via Global Catalog
- Dual mode: SSO + manual login fallback
- Read-only service account (least privilege)
- No credentials stored in source code
- Optional rejection of non-user objects (e.g. `inetOrgPerson`)
- Full LDAPS / TLS migration support
- Centralized connection logic
- PHP 8.1+ compatible (legacy & modern stacks)

## 📁 Folder Structure

```text
ActiveDirectory-SSO-Integrations/
└── php-api/
    ├── public/
    │   ├── index.php       # SSO entry point / router
    │   ├── login.php       # Manual login form + CSRF
    │   ├── dashboard.php   # Protected page example
    │   └── logout.php      # Secure session termination
    │
    ├── src/
    │   └── Auth/
    │       └── LdapService.php     # Connection + auth logic
    │
    ├── .env.example
    ├── .env                    # gitignore
    ├── composer.json
    └── README.md
```

## 🛠️ Prerequisites

- PHP ≥ 8.1
- Apache or Nginx + PHP-FPM
- Active Directory forest with Global Catalog enabled
- Read-only service account
- Composer

## ⚙️ Configuration (.env)

Create `.env` from `.env.example`:

```env
LDAP_HOST=dc-gc01.example.corp
LDAP_PORT=3268                  # → 3269 after LDAPS
LDAP_USE_SSL=false
LDAP_BASE_DN=dc=example,dc=corp
LDAP_USERNAME=svc-sso-readonly@example.corp
LDAP_PASSWORD=change-this-very-secure-password
LDAP_TIMEOUT=5
```

> **Security rule**  
> Never commit `.env`. Use vault / secrets manager in production.

## 🚀 Installation & Quick Start

```bash
cd ActiveDirectory-SSO-Integrations/php-api
cp .env.example .env           # edit with real values
composer install --no-dev
php -S localhost:8000 -t public
```

Open: `http://localhost:8000`

## 🔐 Authentication Flow

1. `index.php` → detects `REMOTE_USER` (SSO) or redirects to `login.php`
2. Form submit → `login.php` attempts LDAP bind
3. Success → session created → `dashboard.php`
4. `logout.php` → secure session destroy

**Central auth logic** (`src/Auth/LdapService.php`):

```php
<?php

declare(strict_types=1);

namespace App\Auth;

use LdapRecord\Connection;
use LdapRecord\Container;

class LdapService
{
    private Connection $connection;

    public function __construct()
    {
        $this->connection = new Connection([
            'hosts'            => [$_ENV['LDAP_HOST']],
            'port'             => (int) ($_ENV['LDAP_PORT'] ?? 389),
            'base_dn'          => $_ENV['LDAP_BASE_DN'],
            'username'         => $_ENV['LDAP_USERNAME'],
            'password'         => $_ENV['LDAP_PASSWORD'],
            'use_ssl'          => filter_var($_ENV['LDAP_USE_SSL'] ?? false, FILTER_VALIDATE_BOOLEAN),
            'use_tls'          => false,
            'version'          => 3,
            'timeout'          => (int) ($_ENV['LDAP_TIMEOUT'] ?? 5),
            'follow_referrals' => false,
        ]);

        Container::addConnection($this->connection);
    }

    public function authenticate(string $username, string $password): ?array
    {
        try {
            $this->connection->auth()->attempt($username, $password);

            $user = $this->connection->query()
                ->where('samaccountname', '=', $username)
                ->orWhere('userprincipalname', '=', $username)
                ->first();

            if (!$user) return null;

            return [
                'username' => $user['samaccountname'][0] ?? $username,
                'name'     => $user['displayname'][0] ?? '',
                'email'    => $user['mail'][0] ?? '',
            ];
        } catch (\Exception $e) {
            error_log("LDAP auth failed: " . $e->getMessage());
            return null;
        }
    }
}
```

## 🔒 Important Security Notes

- Prefer **LDAPS (3269)** over plaintext (3268) – migrate ASAP
- Use **UPN** format for bind credentials
- Enforce **LDAP Signing** + **Channel Binding** on DCs
- Account policies (lockout, expiry) handled by AD – not PHP
- Never log passwords or sensitive bind data
- Rotate service account password regularly
- Consider IP restrictions / mTLS for stronger control

---
© 2026 Luiz Hamilton Silva — @brazilianscriptguy
