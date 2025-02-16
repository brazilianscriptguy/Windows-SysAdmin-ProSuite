from flask import Flask
from controllers.auth_controller import auth_bp
from controllers.user_controller import user_bp

app = Flask(__name__)

# Register blueprints (routes)
app.register_blueprint(auth_bp, url_prefix='/api/auth')
app.register_blueprint(user_bp, url_prefix='/api/user')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
