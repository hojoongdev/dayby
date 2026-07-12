"""Sleep is logged twice — down, then up — and the duration is arithmetic."""
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from app.main import app

SEOUL = timezone(timedelta(hours=9))
NOW = datetime(2026, 7, 12, 15, 0, tzinfo=SEOUL)


def _family_and_baby(c: TestClient) -> tuple[str, str]:
    fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
    bid = c.post("/babies", headers={"X-Family-Id": fid}, json={"name": "Haein"}).json()["id"]
    return fid, bid


def _sleep(c: TestClient, fid: str, bid: str, subtype: str, when: datetime) -> dict:
    return c.post(
        "/events",
        headers={"X-Family-Id": fid},
        json={"baby_id": bid, "type": "sleep", "subtype": subtype,
              "time": when.isoformat()},
    ).json()


def test_waking_up_measures_the_nap(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        _sleep(c, fid, bid, "start", NOW - timedelta(hours=2, minutes=15))
        woke = _sleep(c, fid, bid, "end", NOW)

        assert woke["fields"]["duration_min"] == 135


def test_a_sleep_still_going_has_no_duration_yet(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        went_down = _sleep(c, fid, bid, "start", NOW - timedelta(minutes=40))

        assert "duration_min" not in went_down["fields"]

        # And the assistant knows she is asleep rather than overdue for a nap.
        payload = c.get(
            "/assistant/tips",
            headers={"X-Family-Id": fid},
            params={"baby_id": bid, "now": NOW.isoformat(), "lang": "en"},
        ).json()
        sleep_signal = next(s for s in payload["signals"] if s["type"] == "sleep")
        assert sleep_signal["last_subtype"] == "start"


def test_two_wake_ups_in_a_row_measure_nothing(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        _sleep(c, fid, bid, "start", NOW - timedelta(hours=3))
        _sleep(c, fid, bid, "end", NOW - timedelta(hours=1))
        # A second wake-up with no nap between: there is nothing to measure.
        again = _sleep(c, fid, bid, "end", NOW)

        assert "duration_min" not in again["fields"]


def test_a_duration_that_was_said_out_loud_is_kept(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        _sleep(c, fid, bid, "start", NOW - timedelta(hours=2))

        # "She napped for 90 minutes" — the caregiver's number wins over the clock's.
        woke = c.post(
            "/events",
            headers={"X-Family-Id": fid},
            json={"baby_id": bid, "type": "sleep", "subtype": "end",
                  "fields": {"duration_min": 90}, "time": NOW.isoformat()},
        ).json()
        assert woke["fields"]["duration_min"] == 90
