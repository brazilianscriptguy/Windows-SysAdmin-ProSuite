import os

class Config:
    # Generalized LDAP configuration values
    LDAP_SERVER = "ldap://ldap.headq.scriptguy:3268"
    LDAP_BASE_DN = "dc=HEADQ,dc=SCRIPTGUY"
    LDAP_BIND_USER = "binduser@headq"
    LDAP_BIND_PASSWORD = os.environ.get("LDAP_PASSWORD", "your_generic_password")
    LDAP_USER_SEARCH_FILTER = "(sAMAccountName={username})"
    LDAP_GROUP_SEARCH_FILTER = "(member={user_dn})"
