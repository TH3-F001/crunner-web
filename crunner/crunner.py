#!/usr/bin/python3

from flask import Flask


@app.route('/')
def hello_world():
    return 'Hello, World!'