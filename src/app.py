from flask import Flask

app = Flask(__name__)


@app.route("/health")
def health():
    return "Ok"


@app.route("/hello")
def hello():
    print("Hello", flush=True)
    return "hello"
