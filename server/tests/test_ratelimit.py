"""The ingest endpoints are capped, so an abused one cannot run up a Gemini bill."""
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app


def test_a_caller_is_throttled_past_its_limit(clean_db, monkeypatch):
    monkeypatch.setattr(settings, "ingest_rate_per_minute", 2)
    with TestClient(app) as c:
        fid = c.post("/families", json={"name": "Kim"}).json()["id"]
        h = {"X-Family-Id": fid}

        assert c.post("/ingest/text", headers=h, json={"text": "formula 120ml"}).status_code == 200
        assert c.post("/ingest/text", headers=h, json={"text": "wet nappy"}).status_code == 200

        third = c.post("/ingest/text", headers=h, json={"text": "she slept"})
        assert third.status_code == 429
        assert third.headers.get("Retry-After")


def test_each_caller_has_its_own_budget(clean_db, monkeypatch):
    monkeypatch.setattr(settings, "ingest_rate_per_minute", 1)
    with TestClient(app) as c:
        one = c.post("/families", json={"name": "One"}).json()["id"]
        two = c.post("/families", json={"name": "Two"}).json()["id"]

        assert c.post("/ingest/text", headers={"X-Family-Id": one}, json={"text": "formula 120ml"}).status_code == 200
        # One is spent; two is untouched.
        assert c.post("/ingest/text", headers={"X-Family-Id": one}, json={"text": "wet nappy"}).status_code == 429
        assert c.post("/ingest/text", headers={"X-Family-Id": two}, json={"text": "formula 120ml"}).status_code == 200
