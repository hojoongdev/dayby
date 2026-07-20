"""The numbers behind the charts.

The thing that breaks aggregations like this is the day boundary. A 9pm feed belongs to
tonight, and a sleep that starts at eleven and ends at six belongs to both nights — but
only if the days being counted are the caregiver's, not UTC's. So everything here is set
up in a timezone well away from UTC and checked against the days they actually had.
"""
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from app.main import app

# Seoul. Nine hours ahead, so a Korean evening is the same UTC day and a Korean early
# morning is not — which is exactly where a naive bucketing falls over.
KST = timezone(timedelta(hours=9))


def _family_and_baby(c: TestClient) -> tuple[str, str]:
    fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
    bid = c.post("/babies", headers={"X-Family-Id": fid}, json={"name": "Haein"}).json()["id"]
    return fid, bid


def _log(c: TestClient, fid: str, bid: str, when: datetime, **event) -> None:
    body = {"baby_id": bid, "time": when.isoformat(), **event}
    res = c.post("/events", headers={"X-Family-Id": fid}, json=body)
    assert res.status_code == 201, res.text


def _stats(c: TestClient, fid: str, bid: str, now: datetime, days: int = 7) -> dict:
    res = c.get(
        "/stats",
        headers={"X-Family-Id": fid},
        params={"baby_id": bid, "days": days, "now": now.isoformat()},
    )
    assert res.status_code == 200, res.text
    return res.json()


def test_a_day_is_the_day_they_had_not_the_day_utc_had(clean_db):
    now = datetime(2026, 7, 13, 12, 0, tzinfo=KST)
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)

        # 11pm on the 12th, Seoul. In UTC that is 2pm on the 12th — same date by luck.
        _log(c, fid, bid, datetime(2026, 7, 12, 23, 0, tzinfo=KST),
             type="feeding", fields={"amount_ml": 100})
        # 1am on the 13th, Seoul. In UTC that is 4pm on the *12th*: a naive bucket would
        # file this under the 12th, and the parent would swear they fed her that night.
        _log(c, fid, bid, datetime(2026, 7, 13, 1, 0, tzinfo=KST),
             type="feeding", fields={"amount_ml": 120})

        days = {d["date"]: d for d in _stats(c, fid, bid, now)["days"]}

        assert days["2026-07-12"]["feeds"] == 1
        assert days["2026-07-13"]["feeds"] == 1
        assert days["2026-07-13"]["feed_ml"] == 120


def test_the_gap_between_feeds_is_what_actually_changes(clean_db):
    now = datetime(2026, 7, 13, 20, 0, tzinfo=KST)
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        for hour in (8, 11, 14):  # three feeds, three hours apart
            _log(c, fid, bid, datetime(2026, 7, 13, hour, tzinfo=KST),
                 type="feeding", fields={"amount_ml": 120})

        today = _stats(c, fid, bid, now)["days"][-1]

        assert today["feeds"] == 3
        assert today["feed_ml"] == 360
        assert today["avg_feed_gap_min"] == 180


def test_a_nap_and_a_night_are_not_the_same_thing(clean_db):
    now = datetime(2026, 7, 13, 20, 0, tzinfo=KST)
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)

        # Down at 1pm, up at 2:30. A nap.
        _log(c, fid, bid, datetime(2026, 7, 13, 14, 30, tzinfo=KST),
             type="sleep", subtype="end", fields={"duration_min": 90})
        # Down at 8pm the night before, up at 6am. The night.
        _log(c, fid, bid, datetime(2026, 7, 13, 6, 0, tzinfo=KST),
             type="sleep", subtype="end", fields={"duration_min": 600})

        days = {d["date"]: d for d in _stats(c, fid, bid, now)["days"]}

        assert days["2026-07-13"]["nap_min"] == 90
        # The night's sleep started at 8pm on the 12th, so that is the night it belongs to.
        assert days["2026-07-12"]["night_sleep_min"] == 600
        assert days["2026-07-12"]["nap_min"] == 0


def test_a_night_split_by_a_feed_belongs_to_one_day(clean_db):
    """Waking at 1am does not start a second night. Filed under the day each stretch
    begins on, a Tuesday would carry the tail of Monday's night as well as its own."""
    now = datetime(2026, 7, 13, 20, 0, tzinfo=KST)
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)

        # Down at 8pm on the 12th, awake at 1am to be fed.
        _log(c, fid, bid, datetime(2026, 7, 13, 1, 0, tzinfo=KST),
             type="sleep", subtype="end", fields={"duration_min": 300})
        # Back down at 1:30am, up for the day at 6:30. Same night, other side of midnight.
        _log(c, fid, bid, datetime(2026, 7, 13, 6, 30, tzinfo=KST),
             type="sleep", subtype="end", fields={"duration_min": 300})

        days = {d["date"]: d for d in _stats(c, fid, bid, now)["days"]}

        assert days["2026-07-12"]["night_sleep_min"] == 600
        assert "2026-07-13" not in days


def test_a_sleep_across_midnight_is_cut_in_two_for_the_rhythm_view(clean_db):
    """One row per day on the 24-hour chart. A sleep from 11pm to 6am cannot be one block
    or it would run off the end of the row it started on."""
    now = datetime(2026, 7, 13, 20, 0, tzinfo=KST)
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        # Down at 11pm on the 12th, up at 6am on the 13th: 420 minutes.
        _log(c, fid, bid, datetime(2026, 7, 13, 6, 0, tzinfo=KST),
             type="sleep", subtype="end", fields={"duration_min": 420})

        sleeps = [b for b in _stats(c, fid, bid, now)["rhythm"] if b["type"] == "sleep"]
        by_day = {b["date"]: b for b in sleeps}

        assert len(sleeps) == 2
        # The 12th: from 11pm to midnight.
        assert by_day["2026-07-12"]["start_min"] == 23 * 60
        assert by_day["2026-07-12"]["minutes"] == 60
        # The 13th: from midnight to 6am.
        assert by_day["2026-07-13"]["start_min"] == 0
        assert by_day["2026-07-13"]["minutes"] == 360


def test_diapers_are_counted_by_kind(clean_db):
    now = datetime(2026, 7, 13, 20, 0, tzinfo=KST)
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        for subtype in ("wet", "wet", "dirty"):
            _log(c, fid, bid, datetime(2026, 7, 13, 10, tzinfo=KST),
                 type="diaper", subtype=subtype)

        today = _stats(c, fid, bid, now)["days"][-1]

        assert today["diapers"] == {"wet": 2, "dirty": 1}


def test_growth_comes_back_in_the_order_it_happened(clean_db):
    now = datetime(2026, 7, 13, 20, 0, tzinfo=KST)
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        _log(c, fid, bid, datetime(2026, 7, 10, 10, tzinfo=KST),
             type="growth", fields={"weight_kg": 6.1, "height_cm": 60})
        _log(c, fid, bid, datetime(2026, 7, 13, 10, tzinfo=KST),
             type="growth", fields={"weight_kg": 6.4, "height_cm": 61})

        growth = _stats(c, fid, bid, now)["growth"]

        assert [p["weight_kg"] for p in growth] == [6.1, 6.4]
        assert [p["height_cm"] for p in growth] == [60, 61]


def test_another_familys_baby_is_not_yours_to_chart(clean_db):
    now = datetime(2026, 7, 13, 20, 0, tzinfo=KST)
    with TestClient(app) as c:
        fid, _ = _family_and_baby(c)
        _, other_baby = _family_and_baby(c)

        res = c.get(
            "/stats",
            headers={"X-Family-Id": fid},
            params={"baby_id": other_baby, "days": 7, "now": now.isoformat()},
        )
        assert res.status_code == 404
