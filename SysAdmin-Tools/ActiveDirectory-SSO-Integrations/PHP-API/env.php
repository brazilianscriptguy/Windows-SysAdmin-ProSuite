<?php
// Path: env.php
// Loads environment variables manually for local dev or CLI testing

putenv("LDAP_URL=ldap://ldap.headq.scriptguy:3268");
putenv("LDAP_USERNAME=ad-sso-authentication@scriptguy");
putenv("LDAP_PASSWORD=YourStrongPasswordHere");
putenv("LDAP_BASE_DN=dc=headq,dc=scriptguy");
