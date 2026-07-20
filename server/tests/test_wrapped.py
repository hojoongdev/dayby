"""Integration tests for the wrapped retrospective (needs MongoDB).

The story is the model's; the numbers are MongoDB's, and those are what is tested.
"""
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from app.main import app

SEOUL = timezone(timedelta(hours=9))
NOW = datetime(2026, 7, 12, 15, 0, tzinfo=SEOUL)


def _family_and_baby(c: TestClient) -> tuple[str, str]:
    fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
    bid = c.post("/babies", headers={"X-Family-Id": fid}, json={"name": "Haein"}).json()["id"]
    return fid, bid


def _log(c: TestClient, fid: str, bid: str, type: str, when: datetime, **fields):
    body: dict = {"baby_id": bid, "type": type, "time": when.isoformat()}
    if fields:
        body["fields"] = fields
    c.post("/events", headers={"X-Family-Id": fid}, json=body)


def _wrapped(c: TestClient, fid: str, bid: str) -> dict:
    return c.get(
        "/wrapped",
        headers={"X-Family-Id": fid},
        params={"baby_id": bid, "now": NOW.isoformat(), "lang": "en"},
    ).json()["stats"]


def test_it_counts_a_babyhood(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)

        for day in range(10):
            when = NOW - timedelta(days=day)
            _log(c, fid, bid, "feeding", when.replace(hour=9), amount_ml=120)
            _log(c, fid, bid, "feeding", when.replace(hour=13), amount_ml=100)
            _log(c, fid, bid, "diaper", when.replace(hour=10))
            # 2am in Seoul, which is 17:00 UTC the day before: a night feed only if
            # the aggregation buckets hours in the caller's timezone.
            _log(c, fid, bid, "feeding", when.replace(hour=2), amount_ml=80)

        stats = _wrapped(c, fid, bid)

        assert stats["feedings"] == 30
        assert stats["diapers"] == 10
        assert stats["total_feed_ml"] == 3000  # 10 * (120 + 100 + 80)
        assert stats["night_feeds"] == 10
        assert stats["days_tracked"] == 10
        assert stats["total_events"] == 40
        assert stats["top_types"]["feeding"] == 30


def test_it_finds_the_busiest_day_in_the_callers_timezone(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)

        for hour in (6, 8, 11, 14):
            _log(c, fid, bid, "feeding", NOW.replace(hour=hour))
        _log(c, fid, bid, "feeding", (NOW - timedelta(days=1)).replace(hour=9))

        stats = _wrapped(c, fid, bid)
        assert stats["busiest_day"] == "2026-07-12"
        assert stats["busiest_day_events"] == 4


def test_it_tallies_growth_and_spending(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)

        _log(c, fid, bid, "growth", NOW - timedelta(days=90), weight_kg=3.4, height_cm=50)
        _log(c, fid, bid, "growth", NOW - timedelta(days=1), weight_kg=7.1, height_cm=66)
        _log(c, fid, bid, "purchase", NOW - timedelta(days=5),
             item="formula", amount=30000, currency="KRW")
        _log(c, fid, bid, "purchase", NOW - timedelta(days=2),
             item="diapers", amount=45000, currency="KRW")
        _log(c, fid, bid, "milestone", NOW - timedelta(days=3))

        stats = _wrapped(c, fid, bid)

        assert stats["first_weight_kg"] == 3.4
        assert stats["last_weight_kg"] == 7.1
        assert stats["first_height_cm"] == 50
        assert stats["last_height_cm"] == 66
        assert stats["spend"] == [{"currency": "KRW", "total": 75000, "count": 2}]
        assert len(stats["milestones"]) == 1


def test_something_still_ahead_is_not_counted(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)

        _log(c, fid, bid, "feeding", NOW - timedelta(days=1), amount_ml=120)
        _log(c, fid, bid, "appointment", NOW + timedelta(days=5))

        stats = _wrapped(c, fid, bid)

        assert stats["total_events"] == 1
        assert stats["days_tracked"] == 1
        assert "appointment" not in stats["top_types"]


def test_an_empty_history_is_all_zeroes_not_a_crash(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        stats = _wrapped(c, fid, bid)

        assert stats["total_events"] == 0
        assert stats["days_tracked"] == 0
        assert stats["busiest_day"] is None
        assert stats["spend"] == []
