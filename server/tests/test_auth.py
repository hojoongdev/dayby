"""Sign-in, sessions, and what a session is allowed to reach (needs MongoDB).

These run against the mock identity provider, which signs in whoever asks. What is
being tested is everything downstream of that: the session, the refresh, the family
membership, and the boundaries between families.
"""
import pytest
from fastapi.testclient import TestClient

from app.config import DEFAULT_JWT_SECRET, settings
from app.main import app, guard_config


@pytest.fixture
def auth_on(monkeypatch):
    monkeypatch.setattr(settings, "auth_provider", "mock")
    yield


def _signin(c: TestClient, email: str) -> dict:
    res = c.post("/auth/signin", json={"token": email})
    assert res.status_code == 200, res.text
    return res.json()


def _bearer(session: dict) -> dict:
    return {"Authorization": f"Bearer {session['access_token']}"}


def test_signing_in_twice_is_the_same_person(clean_db, auth_on):
    with TestClient(app) as c:
        first = _signin(c, "mum@dayby.app")
        second = _signin(c, "mum@dayby.app")

        assert first["user"]["id"] == second["user"]["id"]
        assert first["user"]["email"] == "mum@dayby.app"
        # No family yet: that is the app's next screen, not an error.
        assert first["family_id"] is None


def test_a_session_reaches_its_own_family_and_no_other(clean_db, auth_on):
    with TestClient(app) as c:
        mum = _signin(c, "mum@dayby.app")
        family = c.post("/families", headers=_bearer(mum), json={"name": "Kim"}).json()
        c.post("/babies", headers=_bearer(mum), json={"name": "Haein"})

        # Signing in again now finds the family she created.
        assert _signin(c, "mum@dayby.app")["family_id"] == family["id"]

        # A stranger is signed in, but is in no family at all.
        stranger = _signin(c, "stranger@dayby.app")
        assert c.get("/babies", headers=_bearer(stranger)).status_code == 404


def test_the_invite_code_lets_the_other_parent_in(clean_db, auth_on):
    with TestClient(app) as c:
        mum = _signin(c, "mum@dayby.app")
        family = c.post("/families", headers=_bearer(mum), json={"name": "Kim"}).json()
        c.post("/babies", headers=_bearer(mum), json={"name": "Haein"})

        dad = _signin(c, "dad@dayby.app")
        joined = c.post(
            "/families/join",
            headers=_bearer(dad),
            json={"invite_code": family["invite_code"]},
        )
        assert joined.status_code == 200

        # Same family, same baby.
        babies = c.get("/babies", headers=_bearer(dad))
        assert [b["name"] for b in babies.json()] == ["Haein"]


def test_you_cannot_start_a_second_family(clean_db, auth_on):
    with TestClient(app) as c:
        mum = _signin(c, "mum@dayby.app")
        assert c.post("/families", headers=_bearer(mum), json={"name": "Kim"}).status_code == 201

        # Every request resolves to one family, so a second one would be a family
        # nobody could ever reach again.
        second = c.post("/families", headers=_bearer(mum), json={"name": "Other"})
        assert second.status_code == 409


def test_no_session_no_data(clean_db, auth_on):
    with TestClient(app) as c:
        assert c.get("/babies").status_code == 401
        assert c.get("/babies", headers={"Authorization": "Bearer nonsense"}).status_code == 401


def test_the_header_bypass_is_dead_once_auth_is_on(clean_db, auth_on):
    with TestClient(app) as c:
        mum = _signin(c, "mum@dayby.app")
        family = c.post("/families", headers=_bearer(mum), json={"name": "Kim"}).json()

        # The development shortcut must not be a way in once anyone is signing in.
        assert c.get("/babies", headers={"X-Family-Id": family["id"]}).status_code == 401


def test_a_refresh_token_is_not_an_access_token(clean_db, auth_on):
    with TestClient(app) as c:
        mum = _signin(c, "mum@dayby.app")

        # It lives for months. Being usable as a credential would be the whole point
        # of the short access token, gone.
        refresh_as_bearer = {"Authorization": f"Bearer {mum['refresh_token']}"}
        assert c.get("/auth/me", headers=refresh_as_bearer).status_code == 401

        renewed = c.post("/auth/refresh", json={"refresh_token": mum["refresh_token"]})
        assert renewed.status_code == 200
        assert c.get("/auth/me", headers=_bearer(renewed.json())).status_code == 200


def test_the_app_is_told_whether_to_ask_for_a_sign_in(clean_db):
    with TestClient(app) as c:
        off = c.get("/auth/config").json()
        assert off == {"enabled": False, "provider": "none"}


def test_a_placeholder_secret_is_refused_outside_development(monkeypatch):
    monkeypatch.setattr(settings, "auth_provider", "google")
    monkeypatch.setattr(settings, "app_env", "production")
    monkeypatch.setattr(settings, "jwt_secret", DEFAULT_JWT_SECRET)
    with pytest.raises(RuntimeError):
        guard_config()


def test_a_real_secret_passes(monkeypatch):
    monkeypatch.setattr(settings, "auth_provider", "google")
    monkeypatch.setattr(settings, "app_env", "production")
    monkeypatch.setattr(settings, "jwt_secret", "a-real-deployment-secret")
    guard_config()  # does not raise


def test_development_tolerates_the_default_secret(monkeypatch):
    # Auth on, but locally: the default secret is not worth refusing to start over.
    monkeypatch.setattr(settings, "auth_provider", "mock")
    guard_config()  # does not raise
