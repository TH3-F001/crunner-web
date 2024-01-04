import json
from flask import Flask, jsonify
from urllib.parse import unquote


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
    

def client_has_trusted_cert(trusted_cert):
    client_cert_encoded = request.headers.get('X-Client-Certificate')
    if client_cert_encoded:
        client_cert = unquote(client_cert_encoded)  # URL-decode the certificate
        if client_cert == trusted_cert:
            return True
    return False


def password_is_set():
    pass


def verify_client():
    pass

app = Flask(__name__)
paths_file = "/var/www/crunner/instance/config/paths.json"
paths = load_json_file(paths_file)
trusted_client_cert_file = paths['CLT_TRUSTED_CERT_FILE']
trusted_cert = get_file_contents(trusted_client_cert_file)

@app.route('/')
def home():
    return jsonify(message="Home Page")

@app.route('/enroll', methods=['GET', 'POST'])
def enroll():
    # Placeholder for enrollment logic
    return jsonify(message="Enrollment Endpoint")

@app.route('/login', methods=['GET', 'POST'])
def login():
    # Placeholder for login logic
    return jsonify(message="Login Endpoint")

@app.route('/test', methods=['GET'])
def test():
    return jsonify(message="Test Endpoint")

if __name__ == '__main__':
    app.run(debug=True)