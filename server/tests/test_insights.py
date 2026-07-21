"""Predictions and weekly trends (needs MongoDB).

The prediction is arithmetic on the baby's own rhythm and is tested here; the trend
observations are the model's, so with the mock they are only checked for shape.
"""
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from app.main import app

KST = timezone(timedelta(hours=9))


def _family_and_baby(c: TestClient) -> tuple[str, str]:
    fid = c.post("/families", json={"name": "Kim"}).json()["id"]
    bid = c.post("/babies", headers={"X-Family-Id": fid}, json={"name": "Haein"}).json()["id"]
    return fid, bid


def _log(c: TestClient, fid: str, bid: str, type: str, when: datetime, **fields) -> None:
    body: dict = {"baby_id": bid, "type": type, "time": when.isoformat()}
    if fields:
        body["fields"] = fields
    assert c.post("/events", headers={"X-Family-Id": fid}, json=body).status_code == 201


def _insights(c: TestClient, fid: str, bid: str, now: datetime) -> dict:
    res = c.get(
        "/insights",
        headers={"X-Family-Id": fid},
        params={"baby_id": bid, "now": now.isoformat()},
    )
    assert res.status_code == 200, res.text
    return res.json()


def test_it_predicts_the_next_feed_from_the_rhythm(clean_db):
    now = datetime(2026, 7, 20, 14, 0, tzinfo=KST)
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        # Feeds every 3 hours, the last one two hours ago.
        for hours_ago in (12, 9, 6, 3, 2):
            _log(c, fid, bid, "feeding", now - timedelta(hours=hours_ago), amount_ml=120)

        data = _insights(c, fid, bid, now)
        feed = next(p for p in data["predictions"] if p["type"] == "feeding")
        # Last feed + a ~3h median gap ~= an hour from now.
        predicted = datetime.fromisoformat(feed["at"])
        assert timedelta(minutes=45) < predicted - now < timedelta(minutes=75)
        assert "every" in feed["basis"]


def test_too_few_of_something_is_not_predicted(clean_db):
    now = datetime(2026, 7, 20, 14, 0, tzinfo=KST)
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        _log(c, fid, bid, "feeding", now - timedelta(hours=2), amount_ml=120)

        data = _insights(c, fid, bid, now)
        assert [p for p in data["predictions"] if p["type"] == "feeding"] == []


def test_observations_come_back_as_a_list(clean_db):
    now = datetime(2026, 7, 20, 14, 0, tzinfo=KST)
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        for day in range(6):
            when = now - timedelta(days=day)
            for hour in (8, 12, 16):
                _log(c, fid, bid, "feeding", when.replace(hour=hour), amount_ml=120)

        data = _insights(c, fid, bid, now)
        assert isinstance(data["observations"], list)


def test_another_familys_baby_is_off_limits(clean_db):
    now = datetime(2026, 7, 20, 14, 0, tzinfo=KST)
    with TestClient(app) as c:
        _family_and_baby(c)
        fid, _ = _family_and_baby(c)
        _, other_baby = _family_and_baby(c)

        res = c.get(
            "/insights",
            headers={"X-Family-Id": fid},
            params={"baby_id": other_baby, "now": now.isoformat()},
        )
        assert res.status_code == 404
