from flask import Flask, request, jsonify
from ldap3 import Server, Connection, ALL
from config import Config

app = Flask(__name__)
app.config.from_object(Config)

def ldap_authenticate(username, password):
    server = Server(app.config['LDAP_SERVER'], get_info=ALL)
    # Construct user DN; in a real scenario, you may perform a search to get the DN
    user_dn = f"CN={username},{app.config['LDAP_BASE_DN']}"
    try:
        # Bind using provided credentials
        conn = Connection(server, user=user_dn, password=password, auto_bind=True)
        return True, f"Authenticated as {user_dn}"
    except Exception as e:
        return False, str(e)

@app.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    username = data.get('username')
    password = data.get('password')
    success, message = ldap_authenticate(username, password)
    if success:
        return jsonify({"message": message}), 200
    else:
        return jsonify({"error": message}), 401

if __name__ == '__main__':
    app.run(debug=True, port=5000)
