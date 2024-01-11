import json
import os
import secrets
from flask import Flask, jsonify, request, session, Request
from flask_login import LoginManager
from werkzeug.utils import secure_filename
from urllib.parse import unquote

#region File Operations
class File_Ops():

    def load_json_file(file_path: str):
        try:
            with open(file_path, 'r') as file: 
                return json.load(file)
        except FileNotFoundError:
            print(f"File Not Found: {file_path}")
            return None
        except json.JSONDecodeError:
            print(f"Failed To Decode JSON: {file_path}")
            return None

    def get_file_contents(file_path: str, ftype: str='string'):
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

    def file_has_contents(filename: str):
        try:
            with open(filename, 'r') as file:
                # Read the first byte
                return file.read(1) != ''
        except FileNotFoundError:
            print(f"File Not Found: {filename}")
            return False
        except Exception as e:
            print(f"An error occurred: {e}")
            return False
            
#endregion


#region Authentication/Authorization Operations
class Auth_Ops():

    def client_has_cert(req: Request):
        if req.headers.get('X-Client-Certificate'):
            return True
        else:
            return False

    def cert_is_trusted(client_cert: str, trusted_cert: str):
        if client_cert:
            client_cert = unquote(client_cert)  # URL-decode the certificate
            if client_cert == trusted_cert:
                return True
            else:
                return False
        else:
            return False


    def client_is_valid(client_cert: str, trusted_cert: str, password_file: str):
        pass

    
#                   Working this out
# if client doesnt have an existing session:
#   if client_has_cert and cert_is_trusted:
        # return true
