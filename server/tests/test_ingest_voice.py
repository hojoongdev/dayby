"""Voice ingest: a recording in, a structured record out."""
from fastapi.testclient import TestClient

from app.main import app
from app.providers.stt.mock import MockSTTProvider

WAV = {"content-type": "audio/wav"}


async def test_mock_stt_returns_transcript():
    text = await MockSTTProvider().transcribe(b"\x00\x01ignored-audio", "audio/wav")
    assert text == "formula 120ml"


def test_voice_ingest_transcribes_and_structures(clean_db):
    with TestClient(app) as c:
        fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
        res = c.post(
            "/ingest/voice",
            headers={"X-Family-Id": fid, **WAV},
            content=b"\x00\x01fake-audio-bytes",
        )
        assert res.status_code == 200
        body = res.json()
        assert body["transcript"] == "formula 120ml"
        event = body["result"]["events"][0]
        assert event["type"] == "feeding"
        assert event["fields"]["amount_ml"] == 120


def test_voice_ingest_rejects_empty_audio(clean_db):
    with TestClient(app) as c:
        fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
        res = c.post(
            "/ingest/voice",
            headers={"X-Family-Id": fid, **WAV},
            content=b"",
        )
        assert res.status_code == 400


def test_voice_ingest_rejects_what_is_not_audio(clean_db):
    with TestClient(app) as c:
        fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
        res = c.post(
            "/ingest/voice",
            headers={"X-Family-Id": fid, "content-type": "application/octet-stream"},
            content=b"\x00\x01not-audio",
        )
        # A real transcriber has to know what it is being handed.
        assert res.status_code == 415
