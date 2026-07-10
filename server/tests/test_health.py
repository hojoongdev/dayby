"""Smoke tests for the health endpoints (run without a live database)."""
from fastapi.testclient import TestClient

from app.main import app


def test_root_ok():
    with TestClient(app) as client:
        res = client.get("/")
    assert res.status_code == 200
    assert res.json()["status"] == "ok"


def test_health_reports_mongo_flag():
    with TestClient(app) as client:
        res = client.get("/health")
    assert res.status_code == 200
    body = res.json()
    assert body["status"] == "ok"
    assert "mongo" in body
