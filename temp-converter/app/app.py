import json
import logging
import os
import sys
import time
import uuid

from flask import Flask, request, jsonify, g, Response
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST

from app import tracing

APP_VERSION = os.environ.get("APP_VERSION", "dev")
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")
SHOW_FORMULA = os.environ.get("SHOW_FORMULA", "false").lower() == "true"
MAX_VALUE = 1e9
UNITS = ["C", "F", "K"]
# lowest possible temperature in each unit
ABSOLUTE_ZERO = {"C": -273.15, "F": -459.67, "K": 0.0}
FORMULAS = {
    ("C", "F"): "F = C * 9/5 + 32",
    ("F", "C"): "C = (F - 32) * 5/9",
    ("C", "K"): "K = C + 273.15",
    ("K", "C"): "C = K - 273.15",
    ("F", "K"): "K = (F - 32) * 5/9 + 273.15",
    ("K", "F"): "F = (K - 273.15) * 9/5 + 32",
}

app = Flask(__name__)
tracing.setup(app)

REQUESTS = Counter(
    "tempconv_requests_total",
    "Number of HTTP requests",
    ["endpoint", "method", "status"],
)
LATENCY = Histogram(
    "tempconv_request_duration_seconds",
    "Time taken to handle a request",
    ["endpoint"],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5],
)
CONVERSIONS = Counter(
    "tempconv_conversions_total",
    "Number of successful conversions by unit pair",
    ["from_unit", "to_unit"],
)
BUILD_INFO = Gauge(
    "tempconv_build_info",
    "Running version of the app",
    ["version"],
)
BUILD_INFO.labels(version=APP_VERSION).set(1)


class JsonFormatter(logging.Formatter):
    def format(self, record):
        line = {
            "time": self.formatTime(record, "%Y-%m-%dT%H:%M:%S"),
            "level": record.levelname,
            "message": record.getMessage(),
            "version": APP_VERSION,
        }
        extra = getattr(record, "extra_fields", None)
        if extra:
            line.update(extra)
        return json.dumps(line)


handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
log = logging.getLogger("tempconv")
log.setLevel(LOG_LEVEL)
log.addHandler(handler)
log.propagate = False

logging.getLogger("werkzeug").setLevel(logging.WARNING)


def to_celsius(value, unit):
    if unit == "C":
        return value
    if unit == "F":
        return (value - 32) * 5 / 9
    return value - 273.15


def from_celsius(value, unit):
    if unit == "C":
        return value
    if unit == "F":
        return value * 9 / 5 + 32
    return value + 273.15


def convert(value, from_unit, to_unit):
    return round(from_celsius(to_celsius(value, from_unit), to_unit), 2)


@app.before_request
def start_timer():
    g.start = time.time()
    g.request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))


@app.after_request
def record_request(response):
    endpoint = request.url_rule.rule if request.url_rule else "unknown"

    if endpoint in ["/healthz", "/readyz", "/metrics"]:
        return response

    duration = time.time() - g.start
    REQUESTS.labels(endpoint=endpoint, method=request.method, status=response.status_code).inc()
    LATENCY.labels(endpoint=endpoint).observe(duration)

    response.headers["X-Request-ID"] = g.request_id
    response.headers["X-App-Version"] = APP_VERSION

    log.info("request", extra={"extra_fields": {
        "request_id": g.request_id,
        "trace_id": tracing.current_trace_id(),
        "method": request.method,
        "path": request.path,
        "query": request.query_string.decode()[:200],
        "status": response.status_code,
        "duration_ms": round(duration * 1000, 2),
    }})
    return response


@app.route("/")
def home():
    return "Temperature converter. Try /convert?value=100&from=C&to=F\n"


@app.route("/convert")
def convert_route():
    value = request.args.get("value")
    from_unit = request.args.get("from", "").strip().upper()
    to_unit = request.args.get("to", "").strip().upper()

    if value is None or value.strip() == "":
        return jsonify({"error": "value is required"}), 400

    if from_unit not in UNITS or to_unit not in UNITS:
        return jsonify({"error": "from and to must be one of C, F, K"}), 400

    try:
        number = float(value)
    except ValueError:
        return jsonify({"error": "value must be a number"}), 400

    # float() accepts "nan" and "inf", abs() check rejects both along with huge values
    if not abs(number) <= MAX_VALUE:
        return jsonify({"error": "value must be between -1e9 and 1e9"}), 400

    if number < ABSOLUTE_ZERO[from_unit]:
        return jsonify({"error": "value is below absolute zero"}), 400

    result = convert(number, from_unit, to_unit)
    CONVERSIONS.labels(from_unit=from_unit, to_unit=to_unit).inc()

    body = {"value": number, "from": from_unit, "to": to_unit, "result": result}
    if SHOW_FORMULA and from_unit != to_unit:
        body["formula"] = FORMULAS[(from_unit, to_unit)]

    return jsonify(body)


@app.route("/healthz")
def healthz():
    return jsonify({"status": "ok"})


@app.route("/readyz")
def readyz():
    return jsonify({"status": "ready"})


@app.route("/version")
def version():
    return jsonify({"version": APP_VERSION})


@app.route("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000)
