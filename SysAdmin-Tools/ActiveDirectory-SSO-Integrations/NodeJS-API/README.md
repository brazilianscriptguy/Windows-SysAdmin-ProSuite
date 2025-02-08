# NodeJS-API Integration Model

This module demonstrates a Node.js API that integrates with an LDAP server for SSO using the `passport-ldapauth` strategy and a generalized configuration.

## Files
- **package.json:** Lists project dependencies and startup script.
- **app.js:** Main application file with Express and LDAP authentication configuration.
- **config/ldap.config.json:** Contains the LDAP configuration settings.

## Setup Instructions
1. Set the `LDAP_PASSWORD` environment variable.
2. Navigate to this folder and run `npm install` to install dependencies.
3. Start the server with `npm start`. The API will be available on port 3000.
