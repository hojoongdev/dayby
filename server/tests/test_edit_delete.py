"""Correcting and removing what was already logged (needs MongoDB).

A caregiver logging one-handed at 3am will get it wrong sometimes. What matters is
that the fix lands on the record they meant, and on nothing else.
"""
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from app.main import app

SEOUL = timezone(timedelta(hours=9))
NOW = datetime(2026, 7, 12, 15, 0, tzinfo=SEOUL)

PNG = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06"
    b"\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00"
    b"\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82"
)


def _family_and_baby(c: TestClient) -> tuple[str, str]:
    fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
    bid = c.post("/babies", headers={"X-Family-Id": fid}, json={"name": "Haein"}).json()["id"]
    return fid, bid


def _log(c: TestClient, fid: str, bid: str, type: str, when: datetime, **fields) -> str:
    body: dict = {"baby_id": bid, "type": type, "time": when.isoformat()}
    if fields:
        body["fields"] = fields
    return c.post("/events", headers={"X-Family-Id": fid}, json=body).json()["id"]


def _ingest(c: TestClient, fid: str, text: str) -> dict:
    return c.post(
        "/ingest/text",
        headers={"X-Family-Id": fid},
        json={"text": text, "now": NOW.isoformat()},
    ).json()


def test_a_correction_changes_only_what_was_corrected(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        event_id = _log(
            c, fid, bid, "feeding", NOW - timedelta(hours=1),
            amount_ml=120, brand="hipp",
        )

        patched = c.patch(
            f"/events/{event_id}",
            headers={"X-Family-Id": fid},
            json={"fields": {"amount_ml": 150}},
        )
        assert patched.status_code == 200
        assert patched.json()["fields"] == {"amount_ml": 150, "brand": "hipp"}


def test_the_server_picks_the_record_out_of_the_real_timeline(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        _log(c, fid, bid, "diaper", NOW - timedelta(minutes=20))
        feeding = _log(c, fid, bid, "feeding", NOW - timedelta(hours=1), amount_ml=120)

        result = _ingest(c, fid, "change the last feeding to 150 ml")

        assert result["action"] == "update"
        # Not the diaper, which is the newer record.
        assert result["target"]["id"] == feeding
        assert result["events"][0]["fields"]["amount_ml"] == 150


def test_a_removal_asks_before_it_removes(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        diaper = _log(c, fid, bid, "diaper", NOW - timedelta(minutes=20))

        result = _ingest(c, fid, "delete the last diaper")
        assert result["action"] == "delete"
        assert result["target"]["id"] == diaper
        # Nothing has happened yet: the app confirms first.
        assert len(c.get("/events", headers={"X-Family-Id": fid}).json()) == 1

        assert c.delete(f"/events/{diaper}", headers={"X-Family-Id": fid}).status_code == 204
        assert c.get("/events", headers={"X-Family-Id": fid}).json() == []


def test_deleting_the_record_takes_its_photo_with_it(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        ingested = c.post(
            "/ingest/photo",
            headers={"X-Family-Id": fid},
            files={"file": ("rash.png", PNG, "image/png")},
            data={"baby_id": bid, "text": "red spots"},
        ).json()
        photo_id = ingested["photo_id"]

        event = ingested["result"]["events"][0]
        event["baby_id"] = bid
        event_id = c.post("/events", headers={"X-Family-Id": fid}, json=event).json()["id"]
        assert c.get(f"/photos/{photo_id}", headers={"X-Family-Id": fid}).status_code == 200

        c.delete(f"/events/{event_id}", headers={"X-Family-Id": fid})
        # No orphan left behind in GridFS.
        assert c.get(f"/photos/{photo_id}", headers={"X-Family-Id": fid}).status_code == 404


def test_another_family_cannot_touch_the_record(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        event_id = _log(c, fid, bid, "feeding", NOW, amount_ml=120)
        other = c.post("/families", json={"name": "Other"}).json()["id"]

        assert c.patch(
            f"/events/{event_id}",
            headers={"X-Family-Id": other},
            json={"fields": {"amount_ml": 999}},
        ).status_code == 404
        assert c.delete(f"/events/{event_id}", headers={"X-Family-Id": other}).status_code == 404

        # Untouched.
        timeline = c.get("/events", headers={"X-Family-Id": fid}).json()
        assert timeline[0]["fields"]["amount_ml"] == 120
