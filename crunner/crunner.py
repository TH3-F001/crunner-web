import json
import os
from flask import Flask, jsonify, request
from urllib.parse import unquote

#region Define Functions
def load_json_file(file_path):
    try:
        with open(file_path, 'r') as file: 
            return json.load(file)
    except FileNotFoundError:
        print(f"File Not Found: {file_path}")
        return None
    except json.JSONDecodeError:
        print(f"Failed To Decode JSON: {file_path}")
        return None


def get_file_contents(file_path, ftype='string'):
    try:
        with open(file_path, 'r') as file:
            if ftype == 'string':
                return file.read()
            elif ftype == 'list':
                return file.readlines()
            else:
                print(f"Invalid Type: {ftype}")                     
    except FileNotFoundError:
        print(f"File Not Found: {file_path}")
        return None
    except Exception as e:
        print(f"An error occurred: {e}")
        return None


def get_cert_from_file(cert_file_path):
    try:
        with open(cert_file_path, 'r') as file:
            # Read the certificate file and remove the header, footer, and newlines
            cert_content = ''.join([line.strip() for line in file.readlines()
                                    if '-----BEGIN CERTIFICATE-----' not in line and
                                    '-----END CERTIFICATE-----' not in line])
            # URL-encode the certificate content
            cert_content_encoded = cert_content.replace('\n', '%0A')
            return cert_content_encoded
    except FileNotFoundError:
        print(f"File Not Found: {cert_file_path}")
        return None
    except Exception as e:
        print(f"An error occurred: {e}")
        return None

def get_client_provided_cert():
    client_cert_encoded = request.headers.get('X-Client-Certificate')
    if client_cert_encoded:
        client_cert = client_cert_encoded.split('- ')[1].split
        return client_cert
    else:
        return None
        

def client_has_trusted_cert(trusted_cert):
    client_cert_encoded = request.headers.get('X-Client-Certificate')
    response_data = {
        "Trusted Cert": trusted_cert,
        "Supplied Cert": client_cert_encoded
    }
    print(response_data)  # for server-side logging

    if client_cert_encoded:
        client_cert = unquote(client_cert_encoded)  # URL-decode the certificate
        if client_cert == trusted_cert:
            response_data["Match"] = True
            return jsonify(response_data), 200  # Certificate matches
        else:
            response_data["Match"] = False
            return jsonify(response_data), 403  # Certificate does not match
    else:
        return jsonify({"Error": "No client certificate provided"}), 401  # No certificate provided



def password_is_set(password_file):
    try:
        with open(password_file, 'r') as file:
            # Read the first byte
            return file.read(1) != ''
    except FileNotFoundError:
        print(f"File Not Found: {password_file}")
        return False
    except Exception as e:
        print(f"An error occurred: {e}")
        return False


def verify_client(trusted_cert, password_file):
    if not client_has_trusted_cert(trusted_cert):
        return False
    if not password_is_set(password_file):
        return False
    return True
#endregion

#region Initialize the web app
app = Flask(__name__)
app.url_map.strict_slashes = False
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