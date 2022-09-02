from flask import Flask
import os

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
