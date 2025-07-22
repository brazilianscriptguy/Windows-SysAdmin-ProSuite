# 🔹 DotNet-API: Active Directory SSO Integration

## 📌 Overview

The **DotNet-API** is an **ASP.NET Core-based REST API** that enables **LDAP-based Single Sign-On (SSO) authentication** with **Active Directory**.

---

## 📁 Folder Structure

```
ActiveDirectory-SSO-Integrations/
│
├── 📂 DotNet-API/                     # Parent folder for .NET API integration
│   ├── 📄 DotNetSSO.sln               # Solution file for the .NET project
│   ├── 📖 README.md                   # Documentation for DotNet-API integration
│   ├── 📂 DotNetSSO.API/              # Main API implementation
│   │   ├── 📄 Program.cs              # Entry point for the API
│   │   ├── 🛇 Startup.cs              # Application startup configuration
│   │   ├── 📜 appsettings.json        # General application settings
│   │   ├── 📜 appsettings.Development.json  # Environment-specific settings
│   │   ├── 📜 ldapsettings.json       # LDAP authentication settings
│   │   ├── 📂 Controllers/            # API controllers
│   │   │   ├── 📜 AuthController.cs   # Handles authentication requests
│   │   │   ├── 📜 UserController.cs   # Manages user-related requests
│   │   ├── 📂 Services/               # Business logic for LDAP authentication
│   │   │   ├── 📜 LdapService.cs      # Handles LDAP authentication logic
│   │   ├── 📂 Middleware/             # Custom authentication enforcement
│   │   │   ├── 📜 AuthenticationMiddleware.cs  # Middleware for enforcing authentication
│   │   ├── 📂 Models/                 # Defines data models
│   │   │   ├── 📜 UserModel.cs        # Represents user object schema
```

---

## 🛠️ Prerequisites

- **.NET 6.0 or later**  
- **Active Directory instance**  
- **LDAP access credentials**  
- **Visual Studio / VS Code**  
- **Postman** (for testing API requests)

---

## ⚙️ Configuration

Modify `appsettings.json` with your **LDAP credentials**:

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

---

## 🚀 How to Run

1. **Clone the repository**:
   ```bash
   git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
   cd Windows-SysAdmin-ProSuite/SysAdmin-Tools/ActiveDirectory-SSO-Integrations/DotNet-API
   ```

2. **Set the LDAP password as an environment variable**:
   ```bash
   export LDAP_PASSWORD='your-secure-password'
   ```

3. **Run the application**:
   ```bash
   dotnet run
   ```

---

## 🔄 API Endpoints

### 1️⃣ Authenticate User

- **Endpoint**: `POST /api/auth/login`
- **Request Body**:
  ```json
  {
    "username": "john.doe",
    "password": "SuperSecretPassword"
  }
  ```
- **Response**:
  ```json
  {
    "message": "Authentication successful"
  }
  ```

---

### 2️⃣ Get User Details

- **Endpoint**: `GET /api/user/{username}`
- **Example**:
  ```bash
  curl -X GET http://localhost:5000/api/user/john.doe
  ```
- **Response**:
  ```json
  {
    "username": "john.doe",
    "displayName": "John Doe",
    "email": "john.doe@example.com",
    "department": "IT",
    "role": "User"
  }
  ```

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

<p align="center">🚀 <strong>Enjoy Seamless SSO Integration!</strong> 🎯</p>
