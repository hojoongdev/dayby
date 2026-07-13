"""Integration tests for families, babies, and family-scoped ingest (needs MongoDB)."""
import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app


@pytest.fixture
def auth(monkeypatch):
    """Mock identity, so join and rotate have a real person behind them."""
    monkeypatch.setattr(settings, "auth_provider", "mock")


def _signin(c: TestClient, email: str) -> dict:
    session = c.post("/auth/signin", json={"token": email}).json()
    return {"Authorization": f"Bearer {session['access_token']}"}


def test_create_family_and_babies(clean_db):
    with TestClient(app) as c:
        fam = c.post("/families", json={"name": "Kim family"})
        assert fam.status_code == 201
        fid = fam.json()["id"]
        assert fam.json()["invite_code"]

        # Naming no family at all is a missing credential, not a malformed request.
        assert c.post("/babies", json={"name": "Jiho"}).status_code == 401

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


def test_a_new_invite_code_comes_with_an_expiry(clean_db):
    with TestClient(app) as c:
        family = c.post("/families", json={"name": "Kim family"}).json()
        assert family["invite_expires_at"] is not None


def test_rotating_the_code_kills_the_old_one(clean_db, auth):
    with TestClient(app) as c:
        dad = _signin(c, "dad@dayby.app")
        first = c.post("/families", json={"name": "Kim family"}, headers=dad).json()

        rotated = c.post("/families/invite/rotate", headers=dad)
        assert rotated.status_code == 200
        second = rotated.json()["invite_code"]
        assert second != first["invite_code"]

        mum = _signin(c, "mum@dayby.app")
        # The code dad shared before rotating no longer belongs to any family.
        assert (
            c.post("/families/join", json={"invite_code": first["invite_code"]}, headers=mum)
            .status_code
            == 404
        )
        assert (
            c.post("/families/join", json={"invite_code": second}, headers=mum).status_code
            == 200
        )


def test_an_expired_invite_code_is_refused(clean_db, auth, monkeypatch):
    monkeypatch.setattr(settings, "invite_ttl_hours", -1)  # born already stale
    with TestClient(app) as c:
        dad = _signin(c, "dad@dayby.app")
        family = c.post("/families", json={"name": "Kim family"}, headers=dad).json()

        mum = _signin(c, "mum@dayby.app")
        joined = c.post(
            "/families/join", json={"invite_code": family["invite_code"]}, headers=mum
        )
        assert joined.status_code == 410
