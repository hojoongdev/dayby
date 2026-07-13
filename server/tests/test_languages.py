"""The languages a caregiver says they speak, and what the model is allowed to hear.

The transcriber is told nothing about the language and returns whatever it believes it
heard. A Korean sentence said quietly over a crying baby comes back as Chinese often
enough to matter, so the set of possible languages is closed rather than left open.
"""
from datetime import datetime, timezone

from fastapi.testclient import TestClient

from app import lang
from app.context import build_llm_context
from app.main import app
from app.models.events import LlmContext
from app.providers.llm.prompt import build_system_instruction
from app.providers.stt.gemini import INSTRUCTION  # noqa: F401  (import must not break)


def _ctx(languages: list[str]) -> LlmContext:
    return LlmContext(
        now=datetime(2026, 7, 13, 12, 0, tzinfo=timezone.utc),
        languages=languages,
    )


def test_unknown_codes_are_dropped():
    assert lang.known(["ko", "kl", "en", ""]) == ["ko", "en"]


def test_languages_are_named_for_the_prompt():
    assert lang.spoken(["ko", "en"]) == "Korean (ko), English (en)"


def test_the_prompt_names_only_the_languages_they_speak():
    instruction = build_system_instruction(_ctx(["ko"]))

    assert "Korean (ko)" in instruction
    assert "English" not in instruction.split("Languages this caregiver speaks:")[1].split("\n")[0]
    # And it is a constraint, not a hint.
    assert "in no other" in instruction


def test_a_caregiver_who_says_nothing_gets_the_default():
    result = build_system_instruction(_ctx([]))

    assert lang.spoken(lang.DEFAULT) in result


def test_ingest_text_takes_the_languages(clean_db):
    with TestClient(app) as c:
        fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
        res = c.post(
            "/ingest/text",
            headers={"X-Family-Id": fid},
            json={"text": "formula 120ml", "languages": ["en"]},
        )
        assert res.status_code == 200
        assert res.json()["events"][0]["type"] == "feeding"


def test_the_reply_never_comes_back_in_a_language_they_do_not_speak(clean_db, monkeypatch):
    """Naming their languages is a strong prior, but a prior is not a promise: a quiet
    sentence over a crying baby can still be believed to be Chinese. The words are the
    model's to get wrong; the voice the phone speaks in is not."""
    from app.models.events import Confidence, StructuredEvent, StructuredResult
    from app.providers.llm.mock import MockLLMProvider

    async def _drifts(self, text, ctx):
        return StructuredResult(
            events=[StructuredEvent(type="memo", note=text, confidence=Confidence.low)],
            # Escaped, because the repo is English: "fed 120 ml", in Chinese.
            reply="\u5582\u4e86 120 \u6beb\u5347",
            lang="zh",
        )

    monkeypatch.setattr(MockLLMProvider, "structure_log", _drifts)

    with TestClient(app) as c:
        fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
        res = c.post(
            "/ingest/text",
            headers={"X-Family-Id": fid},
            json={"text": "formula 120ml", "languages": ["ko", "en"]},
        )
        assert res.status_code == 200
        # The app reads `reply` out loud in `lang`. Chinese is not a voice they can use.
        assert res.json()["lang"] == "ko"


def test_ingest_voice_takes_the_languages(clean_db):
    """They ride the multipart endpoints as "ko,en"."""
    with TestClient(app) as c:
        fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
        res = c.post(
            "/ingest/voice",
            headers={"X-Family-Id": fid},
            files={"file": ("rec.wav", b"\x00\x01audio", "audio/wav")},
            data={"languages": "ko,en"},
        )
        assert res.status_code == 200
        assert res.json()["result"]["events"][0]["type"] == "feeding"


async def test_the_context_falls_back_rather_than_leaving_it_open(monkeypatch):
    """An empty list would let the model reach for any language on earth."""

    async def _no_babies(*_args, **_kwargs):
        return []

    monkeypatch.setattr("app.context.get_db", lambda: _EmptyDb())

    ctx = await build_llm_context({"_id": "fam1"}, datetime.now(timezone.utc), languages=[])

    assert ctx.languages == lang.DEFAULT


class _EmptyDb:
    """A family with no babies yet: build_llm_context only iterates that one cursor."""

    class _Babies:
        def find(self, *_args, **_kwargs):
            return _EmptyDb._Cursor()

    class _Cursor:
        def __aiter__(self):
            return self

        async def __anext__(self):
            raise StopAsyncIteration

    babies = _Babies()
