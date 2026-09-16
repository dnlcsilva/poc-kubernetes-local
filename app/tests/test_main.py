from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_healthz():
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

def test_root():
    response = client.get("/")
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/html")
    assert "POC Kubernetes Local" in response.text
    assert "Operacional" in response.text
    assert 'id="environment"' in response.text
    assert 'id="version"' in response.text
    assert "fetch(\"/info\")" in response.text
    assert 'href="/healthz"' in response.text
    assert 'href="/metrics"' in response.text
    assert 'href="/docs"' in response.text


def test_info_uses_environment(monkeypatch):
    monkeypatch.setenv("APP_ENV", "test")
    monkeypatch.setenv("API_KEY", "test-key")
    response = client.get("/info")
    assert response.status_code == 200
    assert response.json() == {
        "environment": "test",
        "version": app.version,
        "api_key_configured": True,
    }

def test_secure_rejects_missing_or_invalid_api_key(monkeypatch):
    monkeypatch.setenv("API_KEY", "test-key")
    assert client.get("/secure").status_code == 401
    assert client.get("/secure", headers={"X-API-Key": "invalid"}).status_code == 401

def test_secure_accepts_configured_api_key(monkeypatch):
    monkeypatch.setenv("API_KEY", "test-key")
    response = client.get("/secure", headers={"X-API-Key": "test-key"})
    assert response.status_code == 200
    assert response.json() == {"status": "authorized"}


def test_alerts_rejects_invalid_token(monkeypatch):
    monkeypatch.setenv("API_KEY", "test-key")
    response = client.post(
        "/alerts",
        headers={"Authorization": "Bearer invalid"},
        json={"status": "firing", "alerts": []},
    )
    assert response.status_code == 401


def test_alerts_accepts_alertmanager_payload(monkeypatch):
    monkeypatch.setenv("API_KEY", "test-key")
    response = client.post(
        "/alerts",
        headers={"Authorization": "Bearer test-key"},
        json={
            "status": "firing",
            "alerts": [
                {
                    "status": "firing",
                    "labels": {"alertname": "PocAppDown"},
                }
            ],
        },
    )
    assert response.status_code == 200
    assert response.json() == {"status": "accepted", "alerts": 1}
