#!/usr/bin/python3
"""
This is the client-side script responsible for setting the cloud-runner Web-Access password.
Once the server is confirmed working, this script will be moved to https://github.com/TH3-F001/cloud-runner
"""

import requests
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.serialization import load_pem_private_key
from cryptography.hazmat.backends import default_backend
import os
import socket
import argparse

#region Function Derclarations
def port_is_open(host, port=443, timeout=3):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect((host, port))
            return True
    except socket.error:
        return False
#endregion

def set_webaccess_password(web_args: dict):
    timeout = 3

    url = f"https://{web_args['ip']}/enroll"
    cert_path = web_args["cert_path"]
    privkey_path = web_args["key_path"]
    password = web_args["password"]

    # 1) - Load Client Certificate and Key
    # ToDo configure client to also create a random key to use as the privkey password
    with open(cert_path, 'rb') as cert_file, open(privkey_path, 'rb') as key_file:
        cert = cert_file.read()
        private_key = load_pem_private_key(key_file.read(), password=None, backend=default_backend())
    
    # 2) - Establish HTTPS session using the client certificate
    session = requests.Session()
    session.cert = (cert_path, privkey_path)

    # 3) - Negotiate nonce with the server
    response = session.get(url, timeout=timeout)
    if response.status_code != 200:
        raise Exception("Failed to connect to server.")
    nonce = response.json().get('nonce')

    # 4) - Hash password with the nonce and the shared secret
    # ToDo hash_password
    shared_secret = 'shared_secret'  # Placeholder
    password_hash = hash_password(password, nonce, shared_secret)

    # 5) - Send the hashed password to the server
    response = session.post(url, json={'password': password_hash}, timeout=timeout)
    if response.status_code == 200:
        print("Password set successfully.")
    else:
        print("Failed to set password.")




if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Script to handle server configurations.")

    parser.add_argument("-c", "--cert", required=True, help="Path to the certificate file.")
    parser.add_argument("-k", "--key", required=True, help="Path to the key file.")
    parser.add_argument("-i", "--ip", required=True, help="Server IP address.")
    parser.add_argument("-p", "--pass", dest="password", required=True, help="Password.")

    args = parser.parse_args()

    certificate_path = args.cert
    key_path = args.key
    server_ip = args.ip
    password = args.password

    web_args = {
        "cert_path": certificate_path,
        "key_path": key_path,
        "ip": server_ip,
        "password": password
    }

    # Placeholder
    print(f"Certificate Path: {certificate_path}")
    print(f"Key Path: {key_path}")
    print(f"Server IP: {server_ip}")
    print(f"Password: {password}")
 