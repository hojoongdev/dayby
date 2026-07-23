"""Notes between caregivers (needs MongoDB), and the model reading "tell mum ...".

Runs against the mock identity provider: messaging needs a caller, so there has to be
a signed-in sender and someone in the family to send to.
"""
from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app
from app.models.events import LlmContext
from app.providers.llm.mock import MockLLMProvider


@pytest.fixture
def auth_on(monkeypatch):
    monkeypatch.setattr(settings, "auth_provider", "mock")
    yield


def _signin(c: TestClient, email: str) -> dict:
    return c.post("/auth/signin", json={"token": email}).json()


def _bearer(session: dict) -> dict:
    return {"Authorization": f"Bearer {session['access_token']}"}


def _two_parents(c: TestClient) -> tuple[dict, dict]:
    mum = _signin(c, "mum@dayby.app")
    family = c.post("/families", headers=_bearer(mum), json={"name": "Kim"}).json()
    dad = _signin(c, "dad@dayby.app")
    c.post("/families/join", headers=_bearer(dad),
           json={"invite_code": family["invite_code"]})
    return mum, dad


def test_a_note_reaches_the_other_parent(clean_db, auth_on):
    with TestClient(app) as c:
        mum, dad = _two_parents(c)
        assert c.post("/messages", headers=_bearer(mum),
                      json={"text": "buy diapers"}).status_code == 201

        dad_inbox = c.get("/messages", headers=_bearer(dad)).json()
        assert [m["text"] for m in dad_inbox] == ["buy diapers"]
        assert dad_inbox[0]["mine"] is False
        assert dad_inbox[0]["read"] is False
        assert dad_inbox[0]["from_name"] == "mum"

        mum_inbox = c.get("/messages", headers=_bearer(mum)).json()
        assert mum_inbox[0]["mine"] is True
        assert mum_inbox[0]["read"] is True


def test_opening_the_thread_marks_it_read(clean_db, auth_on):
    with TestClient(app) as c:
        mum, dad = _two_parents(c)
        c.post("/messages", headers=_bearer(mum), json={"text": "she has a fever"})

        assert c.get("/messages", headers=_bearer(dad)).json()[0]["read"] is False
        assert c.post("/messages/read", headers=_bearer(dad)).status_code == 204
        assert c.get("/messages", headers=_bearer(dad)).json()[0]["read"] is True


def test_an_empty_note_is_refused(clean_db, auth_on):
    with TestClient(app) as c:
        mum = _signin(c, "mum@dayby.app")
        c.post("/families", headers=_bearer(mum), json={"name": "Kim"})
        assert c.post("/messages", headers=_bearer(mum),
                      json={"text": "   "}).status_code == 422


def test_another_family_never_sees_the_note(clean_db, auth_on):
    with TestClient(app) as c:
        mum, _ = _two_parents(c)
        c.post("/messages", headers=_bearer(mum), json={"text": "private"})

        stranger = _signin(c, "stranger@dayby.app")
        c.post("/families", headers=_bearer(stranger), json={"name": "Other"})
        assert c.get("/messages", headers=_bearer(stranger)).json() == []


async def test_the_mock_reads_tell_mum_as_a_note():
    ctx = LlmContext(now=datetime.now(timezone.utc), languages=["ko", "en"])
    result = await MockLLMProvider().structure_log("tell mum to buy diapers", ctx)

    assert result.message is not None
    assert result.message.to == "mum"
    assert "diaper" in result.message.text.lower()
    # A note is not also a logged event.
    assert result.events == []
