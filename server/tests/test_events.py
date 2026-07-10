"""Integration tests for event persistence and the timeline (needs MongoDB)."""
from fastapi.testclient import TestClient

from app.main import app


def _family_and_baby(c: TestClient) -> tuple[str, str]:
    fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
    bid = c.post("/babies", headers={"X-Family-Id": fid}, json={"name": "Jiho"}).json()["id"]
    return fid, bid


def test_save_and_list_event(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        saved = c.post(
            "/events",
            headers={"X-Family-Id": fid},
            json={"baby_id": bid, "type": "feeding", "subtype": "formula",
                  "fields": {"amount_ml": 120}, "source": "text"},
        )
        assert saved.status_code == 201
        assert saved.json()["fields"]["amount_ml"] == 120

        timeline = c.get("/events", headers={"X-Family-Id": fid})
        assert timeline.status_code == 200
        assert len(timeline.json()) == 1
        assert timeline.json()[0]["type"] == "feeding"


def test_filter_by_type(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        c.post("/events", headers={"X-Family-Id": fid}, json={"baby_id": bid, "type": "feeding"})
        c.post("/events", headers={"X-Family-Id": fid},
               json={"baby_id": bid, "type": "diaper", "subtype": "wet"})
        feeds = c.get("/events", headers={"X-Family-Id": fid}, params={"type": "feeding"})
        assert [e["type"] for e in feeds.json()] == ["feeding"]


def test_cannot_attach_event_to_a_foreign_baby(clean_db):
    with TestClient(app) as c:
        fid_a, bid_a = _family_and_baby(c)
        fid_b = c.post("/families", json={"name": "Other family"}).json()["id"]
        # Family B tries to log against family A's baby -> rejected.
        res = c.post("/events", headers={"X-Family-Id": fid_b},
                     json={"baby_id": bid_a, "type": "feeding"})
        assert res.status_code == 404


def test_end_to_end_text_to_timeline(clean_db):
    """The full P1 loop: text -> structure -> confirm/save -> timeline."""
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        structured = c.post(
            "/ingest/text", headers={"X-Family-Id": fid}, json={"text": "formula 120ml"}
        ).json()
        event = structured["events"][0]
        event["baby_id"] = bid
        event["source"] = "text"
        saved = c.post("/events", headers={"X-Family-Id": fid}, json=event)
        assert saved.status_code == 201

        timeline = c.get("/events", headers={"X-Family-Id": fid}).json()
        assert timeline[0]["fields"]["amount_ml"] == 120
