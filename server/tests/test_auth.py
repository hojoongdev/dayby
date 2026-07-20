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


@pytest.fixture
def password_auth(monkeypatch):
    monkeypatch.setattr(settings, "auth_provider", "password")
    yield


def _signup(c: TestClient, email: str, password: str = "correcthorse") -> dict:
    res = c.post("/auth/signup", json={"email": email, "password": password})
    assert res.status_code == 201, res.text
    return res.json()


def test_signup_then_signin_is_the_same_account(clean_db, password_auth):
    with TestClient(app) as c:
        created = _signup(c, "mum@dayby.app")
        back = c.post("/auth/signin", json={"email": "MUM@dayby.app", "password": "correcthorse"})

        assert back.status_code == 200, back.text
        assert back.json()["user"]["id"] == created["user"]["id"]
        assert created["family_id"] is None


def test_the_wrong_password_is_refused(clean_db, password_auth):
    with TestClient(app) as c:
        _signup(c, "mum@dayby.app")
        res = c.post("/auth/signin", json={"email": "mum@dayby.app", "password": "wrong"})
        assert res.status_code == 401


def test_an_unknown_email_and_a_wrong_password_look_the_same(clean_db, password_auth):
    with TestClient(app) as c:
        _signup(c, "mum@dayby.app")
        missing = c.post("/auth/signin", json={"email": "nobody@dayby.app", "password": "x"})
        wrong = c.post("/auth/signin", json={"email": "mum@dayby.app", "password": "x"})
        assert missing.status_code == wrong.status_code == 401
        assert missing.json()["detail"] == wrong.json()["detail"]


def test_you_cannot_take_an_email_twice(clean_db, password_auth):
    with TestClient(app) as c:
        _signup(c, "mum@dayby.app")
        again = c.post("/auth/signup", json={"email": "mum@dayby.app", "password": "correcthorse"})
        assert again.status_code == 409


def test_a_short_password_is_refused(clean_db, password_auth):
    with TestClient(app) as c:
        res = c.post("/auth/signup", json={"email": "mum@dayby.app", "password": "short"})
        assert res.status_code == 422


def test_a_second_account_makes_one_and_joins_by_invite(clean_db, password_auth):
    """The flow the app walks: create an account, then join the family with its code."""
    with TestClient(app) as c:
        mum = _signup(c, "mum@dayby.app")
        family = c.post("/families", headers=_bearer(mum), json={"name": "Kim"}).json()
        c.post("/babies", headers=_bearer(mum), json={"name": "Haein"})

        dad = _signup(c, "dad@dayby.app")
        joined = c.post(
            "/families/join",
            headers=_bearer(dad),
            json={"invite_code": family["invite_code"]},
        )
        assert joined.status_code == 200
        assert [b["name"] for b in c.get("/babies", headers=_bearer(dad)).json()] == ["Haein"]

        # And signing back in now lands the second parent on the shared family.
        assert c.post(
            "/auth/signin", json={"email": "dad@dayby.app", "password": "correcthorse"}
        ).json()["family_id"] == family["id"]


def test_signup_is_off_unless_the_provider_is_password(clean_db, auth_on):
    with TestClient(app) as c:
        res = c.post("/auth/signup", json={"email": "mum@dayby.app", "password": "correcthorse"})
        assert res.status_code == 404


def test_the_app_is_told_whether_to_ask_for_a_sign_in(clean_db, monkeypatch):
    monkeypatch.setattr(settings, "auth_provider", "none")
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
