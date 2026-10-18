import pytest

from app.app import app, convert


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


def test_convert():
    assert convert(100, "C", "F") == 212
    assert convert(32, "F", "C") == 0
    assert convert(0, "C", "K") == 273.15
    assert convert(0, "K", "C") == -273.15
    assert convert(-40, "C", "F") == -40
    assert convert(212, "F", "K") == 373.15
    assert convert(373.15, "K", "F") == 212
    assert convert(25, "C", "C") == 25


def test_convert_endpoint(client):
    res = client.get("/convert?value=100&from=C&to=F")
    assert res.status_code == 200
    assert res.get_json() == {"value": 100.0, "from": "C", "to": "F", "result": 212.0}


def test_units_are_case_insensitive(client):
    res = client.get("/convert?value=0&from=c&to=k")
    assert res.status_code == 200
    assert res.get_json()["result"] == 273.15


def test_decimal_and_negative(client):
    res = client.get("/convert?value=-40.5&from=F&to=C")
    assert res.status_code == 200
    assert res.get_json()["result"] == -40.28


def test_missing_value(client):
    assert client.get("/convert?from=C&to=F").status_code == 400
    assert client.get("/convert?value=&from=C&to=F").status_code == 400


def test_bad_units(client):
    assert client.get("/convert?value=10").status_code == 400
    assert client.get("/convert?value=10&from=C&to=X").status_code == 400


def test_not_a_number(client):
    for bad in ["abc", "nan", "inf", "-inf", "1e10"]:
        res = client.get("/convert?value=%s&from=C&to=F" % bad)
        assert res.status_code == 400, bad


def test_below_absolute_zero(client):
    assert client.get("/convert?value=-1&from=K&to=C").status_code == 400
    assert client.get("/convert?value=-300&from=C&to=F").status_code == 400
    assert client.get("/convert?value=-273.15&from=C&to=K").status_code == 200


def test_health_and_ready(client):
    assert client.get("/healthz").status_code == 200
    assert client.get("/readyz").status_code == 200


def test_version(client):
    res = client.get("/version")
    assert res.status_code == 200
    assert "version" in res.get_json()


def test_response_headers(client):
    res = client.get("/convert?value=1&from=C&to=F", headers={"X-Request-ID": "abc123"})
    assert res.headers["X-Request-ID"] == "abc123"
    assert "X-App-Version" in res.headers


def test_metrics(client):
    client.get("/convert?value=10&from=C&to=F")
    client.get("/convert?value=abc&from=C&to=F")
    res = client.get("/metrics")
    text = res.get_data(as_text=True)

    assert res.status_code == 200
    assert "tempconv_requests_total" in text
    assert 'tempconv_conversions_total{from_unit="C",to_unit="F"}' in text
    assert 'status="400"' in text
