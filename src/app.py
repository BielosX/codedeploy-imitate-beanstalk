from flask import Flask

app = Flask(__name__)


@app.route("/health")
def health():
    return "Ok"


@app.route("/hello")
def hello():
    return "hello"
