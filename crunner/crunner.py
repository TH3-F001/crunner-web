from flask import Flask, jsonify

app = Flask(__name__)

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