"""Unit tests for the mock LLM structuring (no HTTP, no database)."""
from datetime import datetime, timezone

from app.models.events import LlmContext
from app.providers.llm.mock import MockLLMProvider


def _ctx() -> LlmContext:
    return LlmContext(now=datetime(2026, 7, 10, 12, 0, tzinfo=timezone.utc))


async def test_formula_feeding_with_amount():
    result = await MockLLMProvider().structure_log("formula 120ml", _ctx())
    assert result.action.value == "create"
    event = result.events[0]
    assert event.type == "feeding"
    assert event.subtype == "formula"
    assert event.fields["amount_ml"] == 120


async def test_wet_diaper():
    result = await MockLLMProvider().structure_log("wet diaper", _ctx())
    assert result.events[0].type == "diaper"
    assert result.events[0].subtype == "wet"


async def test_sleep_start():
    result = await MockLLMProvider().structure_log("baby fell asleep", _ctx())
    assert result.events[0].type == "sleep"
    assert result.events[0].subtype == "start"


async def test_question_is_a_query():
    result = await MockLLMProvider().structure_log("when was the last feeding?", _ctx())
    assert result.action.value == "query"
    assert result.events == []


async def test_unknown_falls_back_to_memo():
    result = await MockLLMProvider().structure_log("she smiled at grandma", _ctx())
    assert result.events[0].type == "memo"
    assert result.events[0].note == "she smiled at grandma"
