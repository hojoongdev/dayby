"""Integration tests for photo ingest and retrieval (needs MongoDB)."""
from fastapi.testclient import TestClient

from app.main import app

# The smallest thing GridFS will accept as an image: a 1x1 transparent PNG.
PNG = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06"
    b"\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00"
    b"\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82"
)


def _family_and_baby(c: TestClient) -> tuple[str, str]:
    fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
    bid = c.post("/babies", headers={"X-Family-Id": fid}, json={"name": "Haein"}).json()["id"]
    return fid, bid


def _upload(c: TestClient, fid: str, bid: str, text: str = "red spots on the cheek"):
    return c.post(
        "/ingest/photo",
        headers={"X-Family-Id": fid},
        files={"file": ("rash.png", PNG, "image/png")},
        data={"baby_id": bid, "text": text},
    )


def test_a_photo_travels_with_the_event_it_belongs_to(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)

        res = _upload(c, fid, bid)
        assert res.status_code == 200
        payload = res.json()
        photo_id = payload["photo_id"]

        # The model never sees the id; the server stitches it into what comes back.
        event = payload["result"]["events"][0]
        assert event["fields"]["photo_id"] == photo_id

        # Confirming the event keeps the photo with it, all the way to the timeline.
        event["baby_id"] = bid
        assert c.post("/events", headers={"X-Family-Id": fid}, json=event).status_code == 201
        timeline = c.get("/events", headers={"X-Family-Id": fid}).json()
        assert timeline[0]["fields"]["photo_id"] == photo_id


def test_the_stored_bytes_come_back_unchanged(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        photo_id = _upload(c, fid, bid).json()["photo_id"]

        got = c.get(f"/photos/{photo_id}", headers={"X-Family-Id": fid})
        assert got.status_code == 200
        assert got.content == PNG
        assert got.headers["content-type"] == "image/png"


def test_another_family_cannot_read_the_photo(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        photo_id = _upload(c, fid, bid).json()["photo_id"]
        other = c.post("/families", json={"name": "Other family"}).json()["id"]

        assert c.get(f"/photos/{photo_id}", headers={"X-Family-Id": other}).status_code == 404


def test_a_pdf_is_not_a_photo(clean_db):
    with TestClient(app) as c:
        fid, bid = _family_and_baby(c)
        res = c.post(
            "/ingest/photo",
            headers={"X-Family-Id": fid},
            files={"file": ("notes.pdf", b"%PDF-1.4", "application/pdf")},
            data={"baby_id": bid},
        )
        assert res.status_code == 415
