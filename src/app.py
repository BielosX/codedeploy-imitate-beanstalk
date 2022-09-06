from flask import Flask, request
import os
import json

app = Flask(__name__)

bucket_arn = os.environ['S3_BUCKET_ARN']


@app.route("/health")
def health():
    return "Ok"


@app.route("/hello")
def hello():
    print("Hello", flush=True)
    return "hello"


@app.route("/bucket")
def bucket():
    return bucket_arn


@app.route("/error")
def error():
    app.logger.error("Problem occurred")
    return "Error", 500


@app.route("/origin")
def origin():
    obj = {
        'origin': request.headers['X-Forwarded-For'],
        'realIp': request.headers['X-Real-IP'],
        'host': request.headers['Host']
    }
    return json.dumps(obj), 200, {'Content-Type': 'application/json'}
