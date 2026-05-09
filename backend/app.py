"""Simple Flask backend API for the Kubernetes multi-pod demo."""

import os
import socket
import time
from datetime import datetime, timezone

from flask import Flask, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)


@app.route("/api/health")
def health():
    return jsonify({"status": "healthy"})


@app.route("/api/info")
def info():
    """Return pod/server information to demonstrate Kubernetes routing."""
    return jsonify({
        "message": "Hello from the Flask backend!",
        "hostname": socket.gethostname(),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "version": os.environ.get("APP_VERSION", "1.0.0"),
    })


@app.route("/api/items")
def items():
    """Return sample data to demonstrate frontend-backend communication."""
    return jsonify({
        "items": [
            {"id": 1, "name": "Kubernetes", "description": "Container orchestration platform"},
            {"id": 2, "name": "Docker", "description": "Container runtime"},
            {"id": 3, "name": "Flask", "description": "Python web microframework"},
            {"id": 4, "name": "React", "description": "JavaScript UI library"},
        ],
        "served_by": socket.gethostname(),
    })


@app.route("/api/slow")
def slow():
    """Hold a request open briefly so connection limiting is easy to prove."""
    time.sleep(3)
    return jsonify({
        "status": "completed",
        "served_by": socket.gethostname(),
    })


@app.route("/api/time")
def get_time():
    return jsonify({
        "time": datetime.now(timezone.utc).isoformat(),
        "served_by": socket.gethostname(),
    })

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
