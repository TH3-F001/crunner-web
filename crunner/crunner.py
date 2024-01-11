#!/var/www/crunner/venv/bin/python3

from flask import Flask, jsonify, request, session
from flask_login import LoginManager
from werkzeug.utils import secure_filename
from urllib.parse import unquote

import json
import os
import secrets

from utils import Auth_Ops, File_Ops

#region Functions

#region Getters

def get_client_cert():
    return request.headers.get('X-Client-Certificate')
#endregion


def verify_client(trusted_cert, password_file):
    if not Auth_Ops.client_has_trusted_cert(trusted_cert):
        return False
    if not Auth_Ops.password_is_set(password_file):
        return False
    return True
#endregion

#region Initialize the web app
app = Flask(__name__)
app.url_map.strict_slashes = False
login_manager = LoginManager()
login_manager.init_app(app)
paths_file = "/var/www/crunner/instance/config/paths.json"
paths = load_json_file(paths_file)
trusted_client_cert_file = paths['CLT_TRUSTED_CERT_FILE']
trusted_cert = get_file_contents(trusted_client_cert_file)
password_file = paths['WEB_PASS_ENC_FILE']
#endregion


@app.route('/')
def home():
    if verify_client(trusted_cert, password_file):
        return jsonify(message="Home Page")
    else: 
        return jsonify(message="NO SOUP FOR YOU!")

@app.route('/enroll', methods=['GET', 'POST'])
def enroll():
    cert = get_client_provided_cert()
    if cert:
        return jsonify(message=cert)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if verify_client(trusted_cert, password_file):
        return jsonify(message="Home Page")
    else: 
        return jsonify(message="NO SOUP FOR YOU!")

@app.route('/test', methods=['GET'])
def test():
    if verify_client(trusted_cert, password_file):
        return jsonify(message="Home Page")
    else: 
        return jsonify(message="NO SOUP FOR YOU!")

if __name__ == '__main__':
    app.run(debug=True)