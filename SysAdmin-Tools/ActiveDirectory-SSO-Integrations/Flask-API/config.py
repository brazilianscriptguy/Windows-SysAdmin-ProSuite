import os

LDAP_CONFIG = {
    "LDAP_SERVER": "ldap://ldap.headq.scriptguy:3268",
    "BASE_DN": "dc=headq,dc=scriptguy",
    "BIND_DN": "cn=ad-sso-authentication,ou=ServiceAccounts,dc=headq,dc=scriptguy",
    "BIND_PASSWORD": os.getenv("LDAP_PASSWORD"),
    "USER_SEARCH_FILTER": "(sAMAccountName={username})"
}
