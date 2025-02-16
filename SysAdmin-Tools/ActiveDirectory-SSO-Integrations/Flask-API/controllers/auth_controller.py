from flask import Blueprint, request, jsonify
from middleware.ldap_auth_middleware import authenticate_user

auth_bp = Blueprint('auth', __name__)

@auth_bp.route('/login', methods=['POST'])
def login():
    data = request.json
    username = data.get('username')
    password = data.get('password')

    if not username or not password:
        return jsonify({"error": "Missing credentials"}), 400

    auth_result = authenticate_user(username, password)

    if auth_result:
        return jsonify({"message": "Authentication successful"}), 200
    else:
        return jsonify({"error": "Invalid credentials"}), 401
