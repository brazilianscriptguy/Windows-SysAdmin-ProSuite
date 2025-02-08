# Python-API Integration Model

This module demonstrates a Flask API using the `ldap3` library to authenticate users against an LDAP server with a generalized configuration.

## Files
- **requirements.txt:** Lists Python dependencies.
- **app.py:** Main application file with LDAP authentication logic.
- **config.py:** Contains the LDAP configuration settings.

## Setup Instructions
1. Set the `LDAP_PASSWORD` environment variable.
2. Navigate to this folder and install dependencies with `pip install -r requirements.txt`.
3. Run the application with `python app.py`. The API will be available on port 5000.
