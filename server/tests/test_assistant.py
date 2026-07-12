"""Integration tests for the proactive assistant (needs MongoDB).

The point of these is the aggregation, not the wording: the tips come from whichever
LLM provider is configured, but the signals they are allowed to lean on must be the
family's real numbers.
"""
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from app.main import app

SEOUL = timezone(timedelta(hours=9))


def _family_and_baby(c: TestClient) -> tuple[str, str]:
    fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
    bid = c.post(
        "/babies",
        headers={"X-Family-Id": fid},
        json={"name": "Haein", "birthdate": "2026-02-01", "sex": "female"},
    ).json()["id"]
    return fid, bid


def _log(c: TestClient, fid: str, bid: str, type: str, when: datetime, **fields):
    body = {"baby_id": bid, "type": type, "time": when.isoformat()}
    if fields:
        body["fields"] = fields
    return c.post("/events", headers={"X-Family-Id": fid}, json=body)


def _signal(payload: dict, type: str) -> dict:
    return next(s for s in payload["signals"] if s["type"] == type)


def test_signals_report_the_gap_and_todays_count(clean_db):
    now = datetime(2026, 7, 12, 15, 0, tzinfo=SEOUL)
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        _log(c, fid, bid, "feeding", now - timedelta(hours=4), amount_ml=120)
        _log(c, fid, bid, "feeding", now - timedelta(hours=9))
        _log(c, fid, bid, "diaper", now - timedelta(minutes=30))
        # Yesterday, in the caller's timezone: counted in the total, not in "today".
        _log(c, fid, bid, "feeding", now - timedelta(hours=20))

        res = c.get(
            "/assistant/tips",
            headers={"X-Family-Id": fid},
            params={"baby_id": bid, "now": now.isoformat(), "lang": "en"},
        )
        assert res.status_code == 200
        payload = res.json()

        feeding = _signal(payload, "feeding")
        assert feeding["hours_since"] == 4.0
        assert feeding["count_today"] == 2
        assert feeding["total"] == 3
        assert _signal(payload, "diaper")["hours_since"] == 0.5


def test_a_long_gap_produces_a_nudge(clean_db):
    now = datetime(2026, 7, 12, 15, 0, tzinfo=SEOUL)
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        _log(c, fid, bid, "feeding", now - timedelta(hours=6))

        payload = c.get(
            "/assistant/tips",
            headers={"X-Family-Id": fid},
            params={"baby_id": bid, "now": now.isoformat(), "lang": "en"},
        ).json()
        assert any(t["kind"] == "nudge" for t in payload["tips"])


def test_a_future_appointment_is_upcoming_not_overdue(clean_db):
    now = datetime(2026, 7, 12, 15, 0, tzinfo=SEOUL)
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        _log(c, fid, bid, "appointment", now + timedelta(hours=20), title="Checkup")

        payload = c.get(
            "/assistant/tips",
            headers={"X-Family-Id": fid},
            params={"baby_id": bid, "now": now.isoformat(), "lang": "en"},
        ).json()

        assert payload["signals"] == []
        assert payload["upcoming"][0]["label"] == "Checkup"
        assert payload["upcoming"][0]["hours_until"] == 20.0


def test_tips_are_family_scoped(clean_db):
    now = datetime(2026, 7, 12, 15, 0, tzinfo=SEOUL)
    with TestClient(app) as c:
        _, bid_a = _family_and_baby(c)
        fid_b = c.post("/families", json={"name": "Other family"}).json()["id"]

        res = c.get(
            "/assistant/tips",
            headers={"X-Family-Id": fid_b},
            params={"baby_id": bid_a, "now": now.isoformat()},
        )
        assert res.status_code == 404
