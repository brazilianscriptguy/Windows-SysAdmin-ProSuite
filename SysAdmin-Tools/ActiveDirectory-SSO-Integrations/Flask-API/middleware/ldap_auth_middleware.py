from ldap3 import Server, Connection, ALL, NTLM
from config import LDAP_CONFIG

def authenticate_user(username, password):
    server = Server(LDAP_CONFIG["LDAP_SERVER"], get_info=ALL)
    user_dn = f"{LDAP_CONFIG['BIND_DN']}"
    
    try:
        conn = Connection(server, user=username, password=password, authentication=NTLM, auto_bind=True)
        return True
    except Exception as e:
        print(f"Authentication failed: {str(e)}")
        return False

def get_user_details(username):
    server = Server(LDAP_CONFIG["LDAP_SERVER"], get_info=ALL)
    
    try:
        conn = Connection(server, LDAP_CONFIG["BIND_DN"], LDAP_CONFIG["BIND_PASSWORD"], auto_bind=True)
        conn.search(LDAP_CONFIG["BASE_DN"], LDAP_CONFIG["USER_SEARCH_FILTER"].format(username=username), attributes=['cn', 'mail', 'memberOf'])
        
        if conn.entries:
            user_data = conn.entries[0]
            return {
                "username": username,
                "displayName": user_data.cn.value,
                "email": user_data.mail.value if hasattr(user_data, 'mail') else "N/A",
                "groups": user_data.memberOf.value if hasattr(user_data, 'memberOf') else []
            }
        return None
    except Exception as e:
        print(f"LDAP search failed: {str(e)}")
        return None
