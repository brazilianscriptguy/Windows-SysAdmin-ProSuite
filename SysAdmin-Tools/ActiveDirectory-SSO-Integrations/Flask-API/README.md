# 🔹 Flask-API — Active Directory SSO Integration

![SSO](https://img.shields.io/badge/SSO-LDAP%20%7C%20Active%20Directory-blue?style=for-the-badge&logo=microsoft) ![Python](https://img.shields.io/badge/Python-Flask-3776AB?style=for-the-badge&logo=python&logoColor=white) ![API](https://img.shields.io/badge/Type-REST%20API-0A66C2?style=for-the-badge) ![Security](https://img.shields.io/badge/Security-Enterprise%20SSO-critical?style=for-the-badge)

## 📝 Overview

The **Flask-API** module is a **Python-based REST API** built with **Flask** that provides **LDAP-based Single Sign-On (SSO)** authentication against **Microsoft Active Directory**, using the `ldap3` library.

This integration follows the same **security, configuration, and architectural standards** defined across the **ActiveDirectory-SSO-Integrations** suite, ensuring **consistent, auditable, and reusable SSO patterns** for enterprise environments.

Primary goals:

- Centralized authentication via Active Directory  
- Secure LDAP bind using **service accounts (InetOrgPerson)**  
- Middleware-enforced authentication flow  
- Lightweight, extensible REST interface  

---

## 📁 Folder Structure

```
ActiveDirectory-SSO-Integrations/
└── Flask-API/
    ├── requirements.txt
    ├── app.py
    ├── config.py
    ├── controllers/
    │   ├── auth_controller.py
    │   └── user_controller.py
    ├── middleware/
    │   └── ldap_auth_middleware.py
    ├── utils/
    │   └── logger.py
    └── README.md
```

---

## 🛠️ Prerequisites

- Python **3.8+**  
- Active Directory domain with LDAP enabled  
- Dedicated LDAP bind account (InetOrgPerson, least privilege)  
- pip / virtualenv  
- Postman or curl for API testing  

---

## ⚙️ LDAP Configuration

Edit `config.py` and configure LDAP parameters:

```python
LDAP_CONFIG = {
    "LDAP_SERVER": "ldap://ldap.headq.scriptguy:3268",
    "BASE_DN": "dc=headq,dc=scriptguy",
    "BIND_DN": "cn=ad-sso-authentication,ou=ServiceAccounts,dc=headq,dc=scriptguy",
    "BIND_PASSWORD": os.getenv("LDAP_PASSWORD"),
    "USER_FILTER": "(sAMAccountName={0})"
}
```

> 🔐 **Security note:** never hardcode credentials. Always inject `LDAP_PASSWORD` via environment variables or a secure secret store.

---

## 🚀 Running the API

```bash
git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
cd Windows-SysAdmin-ProSuite/SysAdmin-Tools/ActiveDirectory-SSO-Integrations/Flask-API
```

```bash
export LDAP_PASSWORD="your-secure-password"
pip install -r requirements.txt
python app.py
```

---

## 🔄 API Endpoints

### Authenticate User
`POST /api/auth/login`

### Retrieve User Details
`GET /api/user/{username}`

Example:
```bash
curl -X GET http://localhost:5000/api/user/john.doe
```

---

## 🔐 Security Notes

- LDAP bind uses **least-privilege service account**
- Interactive logon disabled for bind account
- Authentication enforced via middleware
- Suitable for containerized and on-prem deployments

---

© 2026 Luiz Hamilton Silva. All rights reserved.
