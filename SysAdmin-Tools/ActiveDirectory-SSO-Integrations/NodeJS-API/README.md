# 🔹 NodeJS-API — Active Directory SSO Integration

![SSO](https://img.shields.io/badge/SSO-LDAP%20%7C%20Active%20Directory-blue?style=for-the-badge&logo=microsoft)
![NodeJS](https://img.shields.io/badge/Node.js-Express-339933?style=for-the-badge&logo=node.js&logoColor=white)
![API](https://img.shields.io/badge/Type-REST%20API-0A66C2?style=for-the-badge)
![Security](https://img.shields.io/badge/Security-Enterprise%20SSO-critical?style=for-the-badge)

## 📝 Overview

The **NodeJS-API** module provides a **Node.js + Express–based REST API** that implements **LDAP-based Single Sign-On (SSO)** authentication against **Microsoft Active Directory** using the `passport-ldapauth` strategy.

This module follows the same **security, configuration, and architectural standards** defined across the **ActiveDirectory-SSO-Integrations** suite, enabling **consistent, auditable, and reusable SSO integrations** across heterogeneous application stacks.

Primary objectives:

- Centralized authentication via Active Directory  
- Secure LDAP bind using **least-privilege service accounts (InetOrgPerson)**  
- Middleware-enforced authentication flow  
- Token-ready API design for enterprise applications  

---

## 📁 Folder Structure

```
ActiveDirectory-SSO-Integrations/
└── NodeJS-API/
    ├── package.json
    ├── app.js
    ├── config/
    │   └── ldap.config.json
    ├── controllers/
    │   ├── authController.js
    │   └── userController.js
    ├── middleware/
    │   └── ldapAuthMiddleware.js
    ├── routes/
    │   ├── authRoutes.js
    │   └── userRoutes.js
    ├── utils/
    │   └── logger.js
    └── README.md
```

---

## 🛠️ Prerequisites

- Node.js **16+** and npm  
- Active Directory domain with LDAP enabled  
- Dedicated LDAP bind account (InetOrgPerson, least privilege)  
- Postman or curl for API testing  

---

## ⚙️ LDAP Configuration

Edit `config/ldap.config.json` and configure LDAP parameters:

```json
{
  "server": {
    "url": "ldap://ldap.headq.scriptguy:3268",
    "bindDn": "cn=ad-sso-authentication,ou=ServiceAccounts,dc=headq,dc=scriptguy",
    "bindCredentials": "${LDAP_PASSWORD}",
    "searchBase": "dc=headq,dc=scriptguy",
    "searchFilter": "(sAMAccountName={{username}})"
  }
}
```

> 🔐 **Security note:** never store credentials in source code. Inject `LDAP_PASSWORD` via environment variables or a secure secrets manager.

---

## 🚀 Running the API

```bash
git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
cd Windows-SysAdmin-ProSuite/SysAdmin-Tools/ActiveDirectory-SSO-Integrations/NodeJS-API
```

```bash
export LDAP_PASSWORD="your-secure-password"
npm install
npm start
```

The API will be available at `http://localhost:3000`.

---

## 🔄 API Endpoints

### Authenticate User
`POST /api/auth/login`

### Retrieve User Details
`GET /api/user/:username`

Example:
```bash
curl -X GET http://localhost:3000/api/user/john.doe
```

---

## 🔐 Security Notes

- LDAP bind uses **least-privilege service account**
- Interactive logon disabled for bind account
- Authentication enforced via middleware
- Designed for on‑premises, hybrid, or containerized deployments

---

© 2026 Luiz Hamilton Silva. All rights reserved.
