# 🔹 NodeJS-API: Active Directory SSO Integration

## 📌 Overview

The **NodeJS-API** module enables **LDAP-based Single Sign-On (SSO)** authentication with **Active Directory** using the `passport-ldapauth` strategy and Express.  
It allows **secure authentication and user query operations** directly from an LDAP directory.

---

## 📁 Folder Structure

```
ActiveDirectory-SSO-Integrations/
│
├── 📂 NodeJS-API/                   # Parent folder for Node.js API integration
│   ├── 📜 package.json              # Project dependencies and startup script
│   ├── 📁 app.js                    # Main application file
│   ├── 📂 config/                   # Configuration folder
│   │   ├── 📜 ldap.config.json      # LDAP configuration
│   ├── 📂 controllers/              # API controllers
│   │   ├── 📜 authController.js     # Authentication logic
│   │   ├── 📜 userController.js     # User info retrieval
│   ├── 📂 middleware/               # Middleware logic
│   │   ├── 📜 ldapAuthMiddleware.js # Enforces authentication
│   ├── 📂 routes/                   # Express routes
│   │   ├── 📜 authRoutes.js         # Routes for login
│   │   ├── 📜 userRoutes.js         # Routes for user data
│   ├── 📂 utils/                    # Utility functions
│   │   ├── 📜 logger.js             # Event logging
│   ├── 📖 README.md                 # Documentation
```

---

## 🛠️ Prerequisites

- **Node.js 16+ and npm**
- **Active Directory instance** accessible via LDAP
- **LDAP credentials with read permissions**
- **Postman or cURL** (for API testing)

---

## ⚙️ Configuration

Modify `config/ldap.config.json` with your **LDAP credentials**:

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

---

## 🚀 How to Run

1. **Clone the repository**:
   ```bash
   git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
   cd Windows-SysAdmin-ProSuite/SysAdmin-Tools/ActiveDirectory-SSO-Integrations/NodeJS-API
   ```

2. **Set the LDAP password as an environment variable**:
   ```bash
   export LDAP_PASSWORD='your-secure-password'
   ```

3. **Install dependencies**:
   ```bash
   npm install
   ```

4. **Start the application**:
   ```bash
   npm start
   ```

5. The API will be available at `http://localhost:3000`.

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
    "message": "Authentication successful",
    "token": "eyJhbGciOiJIUzI1..."
  }
  ```

---

### 2️⃣ Get User Details

- **Endpoint**: `GET /api/user/:username`
- **Example Request**:
  ```bash
  curl -X GET http://localhost:3000/api/user/john.doe
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

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/LICENSE.txt)

---

## 🤝 Contributing

[![Contributions Welcome](https://img.shields.io/badge/Contributions-Welcome-brightgreen?style=for-the-badge)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/CONTRIBUTING.md)

---

## 📩 Support

[![Email Badge](https://img.shields.io/badge/Email-luizhamilton.lhr@gmail.com-D14836?style=for-the-badge&logo=gmail)](mailto:luizhamilton.lhr@gmail.com)  
[![GitHub Issues](https://img.shields.io/badge/GitHub%20Issues-Report%20Here-blue?style=for-the-badge&logo=github)](https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/blob/main/.github/BUG_REPORT.md)

---

<p align="center">🚀 <strong>Enjoy Seamless SSO Integration!</strong> 🎯</p>
