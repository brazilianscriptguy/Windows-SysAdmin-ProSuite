# 🔹 Flask-API: Active Directory SSO Integration

## 📌 Overview

The **Flask-API** is a **Python-based REST API** built with **Flask** that enables **LDAP-based Single Sign-On (SSO) authentication** with **Active Directory** using the `ldap3` library.

---

## 📁 Folder Structure

```
ActiveDirectory-SSO-Integrations/
│
├── 📂 Flask-API/                     # Parent folder for Flask API integration
│   ├── 📜 requirements.txt           # Python dependencies
│   ├── 📁 app.py                     # Main application file with LDAP logic
│   ├── 📜 config.py                  # LDAP configuration settings
│   ├── 📂 controllers/               # API endpoints
│   │   ├── 📜 auth_controller.py     # Handles authentication
│   │   ├── 📜 user_controller.py     # Fetches user details
│   ├── 📂 middleware/                # Authentication middleware
│   │   ├── 📜 ldap_auth_middleware.py # Enforces authentication
│   ├── 📂 utils/                     # Helper functions
│   │   ├── 📜 logger.py              # Logs authentication events
│   ├── 📖 README.md                  # Documentation for Flask-API
```

---

## 🛠️ Prerequisites

- **Python 3.8+**
- **Active Directory instance**
- **LDAP access credentials**
- **Postman or cURL** (for API testing)

---

## ⚙️ Configuration

Modify `config.py` with your **LDAP credentials**:

```python
LDAP_CONFIG = {
    "LDAP_SERVER": "ldap://ldap.headq.scriptguy:3268",
    "BASE_DN": "dc=headq,dc=scriptguy",
    "BIND_DN": "cn=ad-sso-authentication,ou=ServiceAccounts,dc=headq,dc=scriptguy",
    "BIND_PASSWORD": os.getenv("LDAP_PASSWORD"),
    "USER_FILTER": "(sAMAccountName={0})"
}
```

---

## 🚀 How to Run

1. **Clone the repository**:
   ```bash
   git clone https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite.git
   cd Windows-SysAdmin-ProSuite/SysAdmin-Tools/ActiveDirectory-SSO-Integrations/Flask-API
   ```

2. **Set the LDAP password as an environment variable**:
   ```bash
   export LDAP_PASSWORD='your-secure-password'
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Run the application**:
   ```bash
   python app.py
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
- **Example Request**:
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
