"""The live family feed (needs MongoDB running as a replica set).

Change streams only exist on a replica set, which is why docker-compose runs mongo
with --replSet even though there is only one node.
"""
import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from app.main import app


def _family_and_baby(c: TestClient) -> tuple[str, str]:
    fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
    bid = c.post("/babies", headers={"X-Family-Id": fid}, json={"name": "Haein"}).json()["id"]
    return fid, bid


def test_one_parent_logs_and_the_other_sees_it(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)

        # The partner's phone, listening.
        with c.websocket_connect(f"/ws/events?family_id={fid}") as ws:
            c.post(
                "/events",
                headers={"X-Family-Id": fid},
                json={"baby_id": bid, "type": "feeding", "subtype": "formula",
                      "fields": {"amount_ml": 120}},
            )

            message = ws.receive_json()
            assert message["type"] == "event"
            assert message["event"]["type"] == "feeding"
            assert message["event"]["fields"]["amount_ml"] == 120
            assert message["event"]["baby_id"] == bid


def test_a_correction_reaches_the_other_phone_too(clean_db):
    """Only inserts used to be forwarded. One parent saying "actually 200" left the other
    reading 120 for as long as they did not think to pull down and refresh."""
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        eid = c.post(
            "/events",
            headers={"X-Family-Id": fid},
            json={"baby_id": bid, "type": "feeding", "fields": {"amount_ml": 120}},
        ).json()["id"]

        with c.websocket_connect(f"/ws/events?family_id={fid}") as ws:
            c.patch(
                f"/events/{eid}",
                headers={"X-Family-Id": fid},
                json={"fields": {"amount_ml": 200}},
            )

            message = ws.receive_json()
            assert message["change"] == "update"
            assert message["event"]["fields"]["amount_ml"] == 200


def test_taking_a_record_back_reaches_the_other_phone_too(clean_db):
    """A delete carries nothing but an id, so the pre-image is the only thing that says
    whose family it was and whose timeline just changed."""
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        eid = c.post(
            "/events",
            headers={"X-Family-Id": fid},
            json={"baby_id": bid, "type": "diaper", "subtype": "wet"},
        ).json()["id"]

        with c.websocket_connect(f"/ws/events?family_id={fid}") as ws:
            c.delete(f"/events/{eid}", headers={"X-Family-Id": fid})

            message = ws.receive_json()
            assert message["change"] == "delete"
            # The record that is gone, so the phone knows which timeline to refresh.
            assert message["event"]["id"] == eid
            assert message["event"]["baby_id"] == bid


def test_another_familys_log_is_not_forwarded(clean_db):
    with TestClient(app) as c:
        fid, _ = _family_and_baby(c)
        other_fid, other_bid = _family_and_baby(c)

        with c.websocket_connect(f"/ws/events?family_id={fid}") as ws:
            c.post(
                "/events",
                headers={"X-Family-Id": other_fid},
                json={"baby_id": other_bid, "type": "diaper"},
            )
            # Ours, logged after theirs: if theirs had leaked it would arrive first.
            fid_baby = c.post(
                "/babies", headers={"X-Family-Id": fid}, json={"name": "Second"}
            ).json()["id"]
            c.post(
                "/events",
                headers={"X-Family-Id": fid},
                json={"baby_id": fid_baby, "type": "bath"},
            )

            assert ws.receive_json()["event"]["type"] == "bath"


def test_an_unknown_family_is_refused(clean_db):
    with TestClient(app) as c:
        with pytest.raises(WebSocketDisconnect):
            with c.websocket_connect("/ws/events?family_id=nope") as ws:
                ws.receive_json()
