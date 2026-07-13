"""Voice ingest: a recording in, a structured record out."""
import json

from fastapi.testclient import TestClient

from app.main import app
from app.providers.stt.mock import MockSTTProvider


def _recording(content: bytes = b"\x00\x01fake-audio-bytes", mime: str = "audio/wav"):
    return {"file": ("rec.wav", content, mime)}


async def test_mock_stt_returns_transcript():
    text = await MockSTTProvider().transcribe(b"\x00\x01ignored-audio", "audio/wav")
    assert text == "formula 120ml"


def test_voice_ingest_transcribes_and_structures(clean_db):
    with TestClient(app) as c:
        fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
        res = c.post("/ingest/voice", headers={"X-Family-Id": fid}, files=_recording())
        assert res.status_code == 200

        body = res.json()
        assert body["transcript"] == "formula 120ml"
        event = body["result"]["events"][0]
        assert event["type"] == "feeding"
        assert event["fields"]["amount_ml"] == 120


def test_voice_ingest_uses_the_history(clean_db, monkeypatch):
    """The reason the audio is a multipart field and not the raw body: a spoken "actually
    200" needs the previous turn just as much as a typed one does."""
    monkeypatch.setattr(MockSTTProvider, "transcript", "actually 200")
    history = [
        {"role": "user", "text": "formula 120ml"},
        {"role": "assistant", "text": "Feeding · formula · 120 ml — saved to the timeline"},
    ]

    with TestClient(app) as c:
        fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
        res = c.post(
            "/ingest/voice",
            headers={"X-Family-Id": fid},
            files=_recording(),
            data={"history": json.dumps(history)},
        )
        assert res.status_code == 200

        result = res.json()["result"]
        assert result["action"] == "update"
        event = result["events"][0]
        assert event["type"] == "feeding"
        assert event["fields"]["amount_ml"] == 200


def test_voice_ingest_rejects_empty_audio(clean_db):
    with TestClient(app) as c:
        fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
        res = c.post(
            "/ingest/voice",
            headers={"X-Family-Id": fid},
            files=_recording(content=b""),
        )
        assert res.status_code == 400


def test_voice_ingest_rejects_what_is_not_audio(clean_db):
    with TestClient(app) as c:
        fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
        res = c.post(
            "/ingest/voice",
            headers={"X-Family-Id": fid},
            files=_recording(mime="application/octet-stream"),
        )
        # A real transcriber has to know what it is being handed.
        assert res.status_code == 415
