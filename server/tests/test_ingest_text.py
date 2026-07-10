"""Tests for POST /ingest/text and the mock LLM structuring."""
from datetime import datetime, timezone

from fastapi.testclient import TestClient

from app.main import app
from app.models.events import LlmContext
from app.providers.llm.mock import MockLLMProvider


def _post(text: str):
    with TestClient(app) as client:
        return client.post("/ingest/text", json={"text": text})


def test_formula_feeding_with_amount():
    res = _post("formula 120ml")
    assert res.status_code == 200
    body = res.json()
    assert body["action"] == "create"
    event = body["events"][0]
    assert event["type"] == "feeding"
    assert event["subtype"] == "formula"
    assert event["fields"]["amount_ml"] == 120


def test_wet_diaper():
    body = _post("wet diaper").json()
    event = body["events"][0]
    assert event["type"] == "diaper"
    assert event["subtype"] == "wet"


def test_question_is_a_query():
    body = _post("when was the last feeding?").json()
    assert body["action"] == "query"
    assert body["events"] == []


def test_unknown_falls_back_to_memo():
    body = _post("she smiled at grandma").json()
    assert body["events"][0]["type"] == "memo"


async def test_mock_provider_detects_sleep_start():
    provider = MockLLMProvider()
    ctx = LlmContext(now=datetime.now(timezone.utc))
    result = await provider.structure_log("baby fell asleep", ctx)
    assert result.events[0].type == "sleep"
    assert result.events[0].subtype == "start"
