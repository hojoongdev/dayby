"""Two phones, two people, one timeline.

Everything here runs with AUTH_PROVIDER=mock, where the "identity token" is simply the
email you claim to be. That is enough to be two different people in one family, which is
the only way to test the thing the app is actually for.
"""
import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app


@pytest.fixture
def two_parents(clean_db, monkeypatch):
    monkeypatch.setattr(settings, "auth_provider", "mock")


def _sign_in(c: TestClient, email: str) -> tuple[dict, str]:
    """The headers that make you this person, and the id you are to the server."""
    res = c.post("/auth/signin", json={"token": email})
    assert res.status_code == 200, res.text
    session = res.json()
    return {"Authorization": f"Bearer {session['access_token']}"}, session["user"]["id"]


def test_the_second_parent_joins_with_the_code_the_first_one_shared(two_parents):
    with TestClient(app) as c:
        dad, _ = _sign_in(c, "dad@dayby.app")
        family = c.post("/families", json={"name": "Kim family"}, headers=dad).json()

        mum, mum_id = _sign_in(c, "mum@dayby.app")
        joined = c.post(
            "/families/join", json={"invite_code": family["invite_code"]}, headers=mum
        )
        assert joined.status_code == 200
        assert joined.json()["id"] == family["id"]

        # And now the same babies, the same timeline, from either phone.
        c.post("/babies", json={"name": "Haein"}, headers=dad)
        assert [b["name"] for b in c.get("/babies", headers=mum).json()] == ["Haein"]


def test_the_timeline_says_which_of_them_logged_it(two_parents):
    """A shared timeline that cannot answer "did you feed her or did I?" is not much use
    to two people who are both half asleep."""
    with TestClient(app) as c:
        dad, _ = _sign_in(c, "dad@dayby.app")
        family = c.post("/families", json={"name": "Kim family"}, headers=dad).json()
        baby = c.post("/babies", json={"name": "Haein"}, headers=dad).json()["id"]

        mum, mum_id = _sign_in(c, "mum@dayby.app")
        c.post("/families/join", json={"invite_code": family["invite_code"]}, headers=mum)

        c.post("/events", json={"baby_id": baby, "type": "feeding"}, headers=dad)
        c.post("/events", json={"baby_id": baby, "type": "diaper"}, headers=mum)

        timeline = c.get("/events", headers=mum).json()
        who = {event["type"]: event["created_by"] for event in timeline}

        members = {u["id"]: u["email"] for u in c.get("/families/members", headers=mum).json()}
        assert members[who["feeding"]] == "dad@dayby.app"
        assert members[who["diaper"]] == "mum@dayby.app"


def test_an_author_cannot_be_claimed_by_the_client(two_parents):
    """Whoever is holding the phone is whoever signed in on it, and nothing they send."""
    with TestClient(app) as c:
        dad, _ = _sign_in(c, "dad@dayby.app")
        family = c.post("/families", json={"name": "Kim family"}, headers=dad).json()
        baby = c.post("/babies", json={"name": "Haein"}, headers=dad).json()["id"]

        mum, mum_id = _sign_in(c, "mum@dayby.app")
        c.post("/families/join", json={"invite_code": family["invite_code"]}, headers=mum)

        logged = c.post(
            "/events",
            json={"baby_id": baby, "type": "feeding", "created_by": mum_id},
            headers=dad,
        ).json()

        assert logged["created_by"] != mum_id


def test_a_stranger_cannot_read_the_family(two_parents):
    with TestClient(app) as c:
        dad, _ = _sign_in(c, "dad@dayby.app")
        c.post("/families", json={"name": "Kim family"}, headers=dad)

        stranger, _ = _sign_in(c, "nobody@dayby.app")
        assert c.get("/events", headers=stranger).status_code == 404
