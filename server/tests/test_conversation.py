"""Chat history: what the model is allowed to remember between utterances.

Every LLM call already took an LlmContext, so the history rides along in there and reaches
structuring, target resolution and question answering alike.
"""
from datetime import datetime, timezone

from fastapi.testclient import TestClient

from app.context import MAX_HISTORY_TURNS, MAX_TURN_CHARS, trim_history
from app.main import app
from app.models.events import LlmContext, Role, Turn
from app.providers.llm.mock import MockLLMProvider
from app.providers.llm.prompt import (
    build_query_instruction,
    build_system_instruction,
    build_target_instruction,
)

# What logging a bottle leaves on screen: what was said, and what the app said back once
# the event was really in the timeline.
LOGGED_A_FEED = [
    Turn(role=Role.user, text="formula 120ml"),
    Turn(role=Role.assistant, text="Feeding · formula · 120 ml — saved to the timeline"),
]


def _ctx(history: list[Turn] | None = None) -> LlmContext:
    return LlmContext(
        now=datetime(2026, 7, 13, 12, 0, tzinfo=timezone.utc),
        history=history or [],
    )


async def test_bare_correction_without_history_stays_a_memo():
    """With nothing behind it, "actually 200" names no event type. Keep the words rather
    than guess."""
    result = await MockLLMProvider().structure_log("actually 200", _ctx())

    assert result.action.value == "update"
    assert result.events[0].type == "memo"


async def test_correction_takes_its_type_from_the_previous_turn():
    result = await MockLLMProvider().structure_log("actually 200", _ctx(LOGGED_A_FEED))

    assert result.action.value == "update"
    event = result.events[0]
    assert event.type == "feeding"
    assert event.subtype == "formula"
    assert event.fields["amount_ml"] == 200


async def test_correction_does_not_reuse_the_previous_amount():
    """Otherwise it would re-log the very amount it is correcting."""
    result = await MockLLMProvider().structure_log("actually, change it", _ctx(LOGGED_A_FEED))

    event = result.events[0]
    assert event.type == "feeding"
    assert "amount_ml" not in event.fields


async def test_history_does_not_overrule_a_clear_utterance():
    result = await MockLLMProvider().structure_log("wet diaper", _ctx(LOGGED_A_FEED))

    assert result.action.value == "create"
    assert result.events[0].type == "diaper"


async def test_history_reaches_every_prompt_that_needs_it():
    ctx = _ctx(LOGGED_A_FEED)

    for instruction in (
        build_system_instruction(ctx),
        build_target_instruction(ctx, "make that 200"),
        build_query_instruction(ctx),
    ):
        assert "user: formula 120ml" in instruction
        # The "saved" line goes too: an offer that was never confirmed is not in the
        # timeline, and the model has to tell those apart.
        assert "assistant: Feeding · formula · 120 ml — saved to the timeline" in instruction


async def test_empty_history_is_spelled_out():
    assert "first thing they have said" in build_system_instruction(_ctx())


def test_history_is_capped_and_truncated():
    long_chat = [Turn(role=Role.user, text="x" * 900) for _ in range(50)]

    trimmed = trim_history(long_chat)

    assert len(trimmed) == MAX_HISTORY_TURNS
    assert all(len(turn.text) == MAX_TURN_CHARS for turn in trimmed)


def test_ingest_text_uses_the_history(clean_db):
    with TestClient(app) as c:
        fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
        res = c.post(
            "/ingest/text",
            headers={"X-Family-Id": fid},
            json={
                "text": "actually 200",
                "history": [turn.model_dump(mode="json") for turn in LOGGED_A_FEED],
            },
        )
        assert res.status_code == 200

        result = res.json()
        assert result["action"] == "update"
        assert result["events"][0]["type"] == "feeding"
        assert result["events"][0]["fields"]["amount_ml"] == 200


def test_malformed_history_is_ignored(clean_db):
    """A client bug in the chat log must not stop a caregiver logging a feed."""
    with TestClient(app) as c:
        fid = c.post("/families", json={"name": "Kim family"}).json()["id"]
        res = c.post(
            "/ingest/voice",
            headers={"X-Family-Id": fid},
            files={"file": ("rec.wav", b"\x00\x01fake-audio-bytes", "audio/wav")},
            data={"history": "not json at all"},
        )
        assert res.status_code == 200
        assert res.json()["result"]["events"][0]["type"] == "feeding"
