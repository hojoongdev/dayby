"""Account-less caregivers: who logged it, without a login (needs MongoDB).

Local use has no sign-in, so a device says which caregiver it is with a header and
that stamps the record's author. These run against the header bypass (auth off,
development), which is the only place it is allowed.
"""
from fastapi.testclient import TestClient

from app.main import app


def _family(c: TestClient) -> tuple[str, str]:
    fid = c.post("/families", json={"name": "Kim"}).json()["id"]
    bid = c.post("/babies", headers={"X-Family-Id": fid}, json={"name": "Haein"}).json()["id"]
    return fid, bid


def test_a_caregiver_stamps_the_record_it_logs(clean_db):
    with TestClient(app) as c:
        fid, bid = _family(c)
        dad = c.post("/families/caregivers", headers={"X-Family-Id": fid},
                     json={"name": "Dad"}).json()
        assert dad["name"] == "Dad"

        event = c.post(
            "/events",
            headers={"X-Family-Id": fid, "X-Caregiver-Id": dad["id"]},
            json={"baby_id": bid, "type": "feeding"},
        ).json()
        assert event["created_by"] == dad["id"]


def test_the_caregivers_are_listed_for_the_whole_family(clean_db):
    with TestClient(app) as c:
        fid, _ = _family(c)
        c.post("/families/caregivers", headers={"X-Family-Id": fid}, json={"name": "Dad"})
        c.post("/families/caregivers", headers={"X-Family-Id": fid}, json={"name": "Mum"})

        names = [cg["name"] for cg in
                 c.get("/families/caregivers", headers={"X-Family-Id": fid}).json()]
        assert names == ["Dad", "Mum"]


def test_without_a_caregiver_the_record_has_no_author(clean_db):
    with TestClient(app) as c:
        fid, bid = _family(c)
        event = c.post("/events", headers={"X-Family-Id": fid},
                       json={"baby_id": bid, "type": "feeding"}).json()
        assert event["created_by"] is None


def test_a_nameless_caregiver_is_refused(clean_db):
    with TestClient(app) as c:
        fid, _ = _family(c)
        res = c.post("/families/caregivers", headers={"X-Family-Id": fid}, json={"name": "  "})
        assert res.status_code == 422
