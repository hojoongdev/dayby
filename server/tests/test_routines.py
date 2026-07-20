"""Reminder rules: the list a family edits (needs MongoDB).

Turning a rule into a scheduled nudge is tested with the assistant; this is only the
CRUD and its family boundary.
"""
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from app.main import app

KST = timezone(timedelta(hours=9))


def _family(c: TestClient) -> str:
    fid = c.post("/families", json={"name": "Kim"}).json()["id"]
    c.post("/babies", headers={"X-Family-Id": fid}, json={"name": "Haein"})
    return fid


def _headers(fid: str) -> dict:
    return {"X-Family-Id": fid}


def test_an_after_event_rule_round_trips(clean_db):
    with TestClient(app) as c:
        fid = _family(c)
        res = c.post("/routines", headers=_headers(fid), json={
            "kind": "after_event",
            "trigger_type": "feeding",
            "delay_min": 30,
            "message": "Give vitamin D",
        })
        assert res.status_code == 201, res.text
        rule = res.json()
        assert rule["kind"] == "after_event"
        assert rule["delay_min"] == 30
        assert rule["active"] is True

        listed = c.get("/routines", headers=_headers(fid)).json()
        assert [r["message"] for r in listed] == ["Give vitamin D"]


def test_a_daily_rule_needs_a_time(clean_db):
    with TestClient(app) as c:
        fid = _family(c)
        ok = c.post("/routines", headers=_headers(fid), json={
            "kind": "daily", "time_local": "20:00", "message": "Bath time",
        })
        assert ok.status_code == 201

        bad = c.post("/routines", headers=_headers(fid), json={
            "kind": "daily", "message": "Bath time",
        })
        assert bad.status_code == 422

        nonsense = c.post("/routines", headers=_headers(fid), json={
            "kind": "daily", "time_local": "25:99", "message": "Bath time",
        })
        assert nonsense.status_code == 422


def test_an_after_event_rule_needs_a_trigger_and_delay(clean_db):
    with TestClient(app) as c:
        fid = _family(c)
        res = c.post("/routines", headers=_headers(fid), json={
            "kind": "after_event", "message": "Give vitamin D",
        })
        assert res.status_code == 422


def test_toggling_a_rule_off_leaves_the_rest_of_it(clean_db):
    with TestClient(app) as c:
        fid = _family(c)
        rule = c.post("/routines", headers=_headers(fid), json={
            "kind": "after_event", "trigger_type": "feeding",
            "delay_min": 30, "message": "Give vitamin D",
        }).json()

        off = c.patch(f"/routines/{rule['id']}", headers=_headers(fid), json={"active": False})
        assert off.status_code == 200
        body = off.json()
        assert body["active"] is False
        assert body["delay_min"] == 30
        assert body["message"] == "Give vitamin D"


def test_deleting_a_rule_removes_it(clean_db):
    with TestClient(app) as c:
        fid = _family(c)
        rule = c.post("/routines", headers=_headers(fid), json={
            "kind": "daily", "time_local": "20:00", "message": "Bath time",
        }).json()

        assert c.delete(f"/routines/{rule['id']}", headers=_headers(fid)).status_code == 204
        assert c.get("/routines", headers=_headers(fid)).json() == []
        assert c.delete(f"/routines/{rule['id']}", headers=_headers(fid)).status_code == 404


def test_a_rule_is_not_visible_to_another_family(clean_db):
    with TestClient(app) as c:
        mine = _family(c)
        rule = c.post("/routines", headers=_headers(mine), json={
            "kind": "daily", "time_local": "20:00", "message": "Bath time",
        }).json()

        theirs = _family(c)
        assert c.get("/routines", headers=_headers(theirs)).json() == []
        assert c.patch(
            f"/routines/{rule['id']}", headers=_headers(theirs), json={"active": False}
        ).status_code == 404
        assert c.delete(
            f"/routines/{rule['id']}", headers=_headers(theirs)
        ).status_code == 404


def _tips(c: TestClient, fid: str, baby_id: str, now: datetime) -> dict:
    return c.get(
        "/assistant/tips",
        headers=_headers(fid),
        params={"baby_id": baby_id, "now": now.isoformat()},
    ).json()


def test_an_after_event_rule_schedules_from_the_last_event(clean_db):
    now = datetime(2026, 7, 20, 12, 0, tzinfo=KST)
    with TestClient(app) as c:
        fid = _family(c)
        baby = c.get("/babies", headers=_headers(fid)).json()[0]["id"]
        c.post("/events", headers=_headers(fid), json={
            "baby_id": baby, "type": "feeding",
            "time": (now - timedelta(minutes=10)).isoformat(),
        })
        c.post("/routines", headers=_headers(fid), json={
            "kind": "after_event", "trigger_type": "feeding",
            "delay_min": 30, "message": "Give vitamin D",
        })

        scheduled = _tips(c, fid, baby, now)["scheduled"]
        vitd = [s for s in scheduled if s["text"] == "Give vitamin D"]
        assert len(vitd) == 1
        # Ten minutes ago plus thirty is twenty minutes from now.
        assert datetime.fromisoformat(vitd[0]["at"]) == now + timedelta(minutes=20)


def test_an_after_event_rule_that_already_passed_is_not_scheduled(clean_db):
    now = datetime(2026, 7, 20, 12, 0, tzinfo=KST)
    with TestClient(app) as c:
        fid = _family(c)
        baby = c.get("/babies", headers=_headers(fid)).json()[0]["id"]
        # The feed was an hour ago; a +30min rule was due half an hour back.
        c.post("/events", headers=_headers(fid), json={
            "baby_id": baby, "type": "feeding",
            "time": (now - timedelta(minutes=60)).isoformat(),
        })
        c.post("/routines", headers=_headers(fid), json={
            "kind": "after_event", "trigger_type": "feeding",
            "delay_min": 30, "message": "Give vitamin D",
        })

        scheduled = _tips(c, fid, baby, now)["scheduled"]
        assert "Give vitamin D" not in [s["text"] for s in scheduled]


def test_a_daily_rule_schedules_its_next_time(clean_db):
    now = datetime(2026, 7, 20, 12, 0, tzinfo=KST)
    with TestClient(app) as c:
        fid = _family(c)
        baby = c.get("/babies", headers=_headers(fid)).json()[0]["id"]
        c.post("/routines", headers=_headers(fid), json={
            "kind": "daily", "time_local": "20:00", "message": "Bath time",
        })

        scheduled = _tips(c, fid, baby, now)["scheduled"]
        bath = [s for s in scheduled if s["text"] == "Bath time"]
        assert len(bath) == 1
        assert bath[0]["at"].startswith("2026-07-20T20:00")


def test_a_paused_rule_is_not_scheduled(clean_db):
    now = datetime(2026, 7, 20, 12, 0, tzinfo=KST)
    with TestClient(app) as c:
        fid = _family(c)
        baby = c.get("/babies", headers=_headers(fid)).json()[0]["id"]
        rule = c.post("/routines", headers=_headers(fid), json={
            "kind": "daily", "time_local": "20:00", "message": "Bath time",
        }).json()
        c.patch(f"/routines/{rule['id']}", headers=_headers(fid), json={"active": False})

        scheduled = _tips(c, fid, baby, now)["scheduled"]
        assert "Bath time" not in [s["text"] for s in scheduled]


def test_a_rule_for_a_baby_that_isnt_yours_is_refused(clean_db):
    with TestClient(app) as c:
        mine = _family(c)
        theirs = _family(c)
        their_baby = c.get("/babies", headers=_headers(theirs)).json()[0]["id"]

        res = c.post("/routines", headers=_headers(mine), json={
            "kind": "daily", "time_local": "20:00", "message": "Bath time",
            "baby_id": their_baby,
        })
        assert res.status_code == 404
