from flask import Flask, request
from threading import Thread
import os
import json
import boto3
import time

app = Flask(__name__)

bucket_arn = os.environ['S3_BUCKET_ARN']
queue_url = os.environ['QUEUE_URL']

sqs_client = boto3.client('sqs')


def handler():
    print("Handler started, queue url: {}".format(queue_url), flush=True)
    while True:
        response = sqs_client.receive_message(QueueUrl=queue_url,
                                              WaitTimeSeconds=20,
                                              MaxNumberOfMessages=10)
        for message in response['Messages']:
            print("Received event: {}".format(message), flush=True)
            receipt_handle = message['ReceiptHandle']
            sqs_client.delete_message(QueueUrl=queue_url, ReceiptHandle=receipt_handle)
            time.sleep(10.0)


thread = Thread(target=handler, daemon=True)
thread.start()


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
