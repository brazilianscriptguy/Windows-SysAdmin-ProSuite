# 🔹 DotNet-API — Active Directory SSO Integration

![SSO](https://img.shields.io/badge/SSO-LDAP%20%7C%20Active%20Directory-blue?style=for-the-badge&logo=microsoft) ![DotNet](https://img.shields.io/badge/.NET-ASP.NET%20Core-512BD4?style=for-the-badge&logo=dotnet&logoColor=white) ![API](https://img.shields.io/badge/Type-REST%20API-0A66C2?style=for-the-badge) ![Security](https://img.shields.io/badge/Security-Enterprise%20SSO-critical?style=for-the-badge)

## 📝 Overview

The **DotNet-API** module is an **ASP.NET Core–based REST API** that implements **LDAP-based Single Sign-On (SSO)** authentication against **Microsoft Active Directory**.

This integration follows the same **security, configuration, and architectural standards** defined in the **ActiveDirectory-SSO-Integrations** suite, enabling **consistent, auditable, and reusable SSO patterns** across enterprise environments.

Key objectives:

- Centralized authentication via Active Directory  
- Secure LDAP bind using **service accounts (InetOrgPerson)**  
- Clean separation between authentication logic, middleware, and API endpoints  
- Ready for enterprise deployment and extension  

## 📁 Folder Structure

```
ActiveDirectory-SSO-Integrations/
└── DotNet-API/
    ├── DotNetSSO.sln
    ├── README.md
    └── DotNetSSO.API/
        ├── Program.cs
        ├── Startup.cs
        ├── appsettings.json
        ├── appsettings.Development.json
        ├── ldapsettings.json
        ├── Controllers/
        │   ├── AuthController.cs
        │   └── UserController.cs
        ├── Services/
        │   └── LdapService.cs
        ├── Middleware/
        │   └── AuthenticationMiddleware.cs
        └── Models/
            └── UserModel.cs
```

## 🛠️ Prerequisites

- .NET 6.0 or later  
- Active Directory domain with LDAP enabled  
- Dedicated LDAP bind account (InetOrgPerson, least privilege)  
- Visual Studio or VS Code  
- Postman or curl for API testing  

## ⚙️ LDAP Configuration

```json
{
  "LdapSettings": {
    "LdapServer": "ldap://ldap.headq.scriptguy:3268",
    "BaseDn": "dc=headq,dc=scriptguy",
    "BindDn": "cn=ad-sso-authentication,ou=ServiceAccounts,dc=headq,dc=scriptguy",
    "BindPassword": "${LDAP_PASSWORD}",
    "UserFilter": "(sAMAccountName={0})"
  }
}
```

## 🚀 Running the API

```bash
git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
cd Windows-SysAdmin-ProSuite/SysAdmin-Tools/ActiveDirectory-SSO-Integrations/DotNet-API
```

```powershell
$env:LDAP_PASSWORD="your-secure-password"
dotnet run
```

## 🔄 API Endpoints

### Authenticate User
`POST /api/auth/login`

### Retrieve User Details
`GET /api/user/{username}`

## 🔐 Security Notes

- LDAP bind with least privilege  
- No interactive logon  
- Middleware-enforced authentication  

© 2026 Luiz Hamilton Silva. All rights reserved.
