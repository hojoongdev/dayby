"""When the phone should buzz, and about what.

The wording is the model's. The moment is arithmetic, and that is what is tested:
a nudge that arrives at the wrong hour is worse than no nudge at all.
"""
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from app.care import OVERDUE_AFTER
from app.main import app
from app.models.events import CareSignal
from app.routers.assistant import next_reminder

SEOUL = timezone(timedelta(hours=9))
NOW = datetime(2026, 7, 12, 15, 0, tzinfo=SEOUL)


def _signal(type: str, hours_ago: float, subtype: str | None = None) -> CareSignal:
    return CareSignal(
        type=type,
        last_time=NOW - timedelta(hours=hours_ago),
        last_subtype=subtype,
        hours_since=hours_ago,
        total=1,
    )


def test_the_next_buzz_is_the_soonest_gap_to_open():
    # Fed an hour ago (4h gap -> due in 3h); changed 2h ago (3h gap -> due in 1h).
    remind_at, topic = next_reminder(
        [_signal("feeding", 1), _signal("diaper", 2)], NOW
    )
    assert topic == "diaper"
    assert remind_at == NOW + timedelta(hours=1)


def test_nothing_to_say_about_a_gap_that_is_already_open():
    # Already overdue: the app is showing a nudge for this right now, and a
    # notification about it belongs in the past.
    remind_at, topic = next_reminder([_signal("feeding", 9)], NOW)
    assert remind_at is None
    assert topic is None


def test_a_sleep_in_progress_is_not_a_sleep_that_is_late():
    remind_at, topic = next_reminder([_signal("sleep", 1, subtype="start")], NOW)
    assert remind_at is None


def test_nobody_is_buzzed_about_something_minutes_away():
    # The gap opens in ten minutes. They are still holding the baby.
    almost = OVERDUE_AFTER["feeding"] - timedelta(minutes=10)
    remind_at, _ = next_reminder(
        [_signal("feeding", almost.total_seconds() / 3600)], NOW
    )
    assert remind_at is None


def test_the_endpoint_hands_the_app_a_time_and_something_to_say(clean_db):
    with TestClient(app) as c:
        fid = c.post("/families", json={"name": "Kim"}).json()["id"]
        bid = c.post("/babies", headers={"X-Family-Id": fid},
                     json={"name": "Haein"}).json()["id"]
        c.post(
            "/events",
            headers={"X-Family-Id": fid},
            json={"baby_id": bid, "type": "feeding",
                  "time": (NOW - timedelta(hours=1)).isoformat()},
        )

        payload = c.get(
            "/assistant/tips",
            headers={"X-Family-Id": fid},
            params={"baby_id": bid, "now": NOW.isoformat(), "lang": "en"},
        ).json()

        assert payload["reminder"]
        assert payload["remind_at"].startswith("2026-07-12T09:00")  # 18:00 Seoul, in UTC
        # The line to send later is not one of the lines shown now.
        assert all(t["kind"] != "reminder" for t in payload["tips"])
