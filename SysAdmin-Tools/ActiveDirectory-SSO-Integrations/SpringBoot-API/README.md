# SpringBoot-API Integration Model

This module demonstrates a Spring Boot API that integrates with an LDAP server for Single Sign-On (SSO) using a generalized configuration. The configuration is externalized via the `application.yml` file, allowing you to adapt the settings across different environments by simply updating environment variables (e.g., `LDAP_PASSWORD`).

---

## Files

- **application.yml**  
  Contains the LDAP connection and Spring Security configuration details:
  - **Base DN:** `dc=HEADQ,dc=SCRIPTGUY`
  - **LDAP URL:** `ldap://ldap.headq.scriptguy:3268`
  - **Bind User:** `ad-sso-authentication@headq`
  - **Bind Password:** `${LDAP_PASSWORD}` (externalized via environment variables)
  - **User Search Filter:** `(sAMAccountName={0})`
  - **Group Search Base:** `dc=headq,dc=scriptguy`
  - **Group Search Filter:** `(member={0})`

---

## Setup Instructions

1. **Set Environment Variables:**

   Ensure that the `LDAP_PASSWORD` environment variable is set. For example, in a Unix-based shell:
   ```bash
   export LDAP_PASSWORD=your_ldap_password
