from flask import Blueprint, jsonify
from middleware.ldap_auth_middleware import get_user_details

user_bp = Blueprint('user', __name__)

@user_bp.route('/<username>', methods=['GET'])
def get_user(username):
    user_info = get_user_details(username)

    if user_info:
        return jsonify(user_info), 200
    else:
        return jsonify({"error": "User not found"}), 404
