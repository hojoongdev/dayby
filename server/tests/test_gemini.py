"""Live Gemini test. Skipped unless GEMINI_API_KEY is set (it calls the real API)."""
import os
from datetime import datetime, timezone

import pytest

from app.models.events import LlmContext

_NO_KEY = not os.getenv("GEMINI_API_KEY")


@pytest.mark.skipif(_NO_KEY, reason="set GEMINI_API_KEY to run the live Gemini test")
async def test_gemini_structures_english_feeding():
    from app.providers.llm.gemini import GeminiLLMProvider

    provider = GeminiLLMProvider()
    result = await provider.structure_log(
        "formula 120ml", LlmContext(now=datetime.now(timezone.utc))
    )
    assert result.events
    assert result.events[0].type == "feeding"


@pytest.mark.skipif(_NO_KEY, reason="set GEMINI_API_KEY to run the live Gemini test")
async def test_gemini_handles_korean():
    from app.providers.llm.gemini import GeminiLLMProvider

    # Korean input passed at runtime (not stored in the repo): "formula 120".
    korean = "분유 120"
    provider = GeminiLLMProvider()
    result = await provider.structure_log(korean, LlmContext(now=datetime.now(timezone.utc)))
    assert result.events
    assert result.events[0].type == "feeding"
    assert result.lang == "ko"
