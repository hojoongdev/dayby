"""Integration tests for families, babies, and family-scoped ingest (needs MongoDB)."""
from fastapi.testclient import TestClient

from app.main import app


def test_create_family_and_babies(clean_db):
    with TestClient(app) as c:
        fam = c.post("/families", json={"name": "Kim family"})
        assert fam.status_code == 201
        fid = fam.json()["id"]
        assert fam.json()["invite_code"]

        # A baby requires the family header.
        assert c.post("/babies", json={"name": "Jiho"}).status_code == 422

        baby = c.post(
            "/babies",
            headers={"X-Family-Id": fid},
            json={"name": "Jiho", "nicknames": ["little one"]},
        )
        assert baby.status_code == 201
        assert baby.json()["family_id"] == fid

        babies = c.get("/babies", headers={"X-Family-Id": fid})
        assert [b["name"] for b in babies.json()] == ["Jiho"]


def test_unknown_family_is_rejected(clean_db):
    with TestClient(app) as c:
        assert c.get("/babies", headers={"X-Family-Id": "does-not-exist"}).status_code == 404


def test_ingest_is_family_scoped(clean_db):
    with TestClient(app) as c:
        fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
        c.post("/babies", headers={"X-Family-Id": fid}, json={"name": "Jiho"})
        res = c.post(
            "/ingest/text",
            headers={"X-Family-Id": fid},
            json={"text": "formula 120ml"},
        )
        assert res.status_code == 200
        assert res.json()["events"][0]["type"] == "feeding"
