"""Real LLM provider backed by Google Gemini (AI Studio API key).

Handles arbitrary phrasing in any language (English, Korean, ...). Requires
GEMINI_API_KEY; the model id is configurable via GEMINI_MODEL.
"""
from google import genai
from google.genai import types

from ...config import settings
from ...models.events import Confidence, LlmContext, StructuredEvent, StructuredResult
from .base import LLMProvider
from .prompt import build_system_instruction


class GeminiLLMProvider(LLMProvider):
    name = "gemini"

    def __init__(self) -> None:
        if not settings.gemini_api_key:
            raise RuntimeError("GEMINI_API_KEY is not set (required for LLM_PROVIDER=gemini)")
        self._client = genai.Client(api_key=settings.gemini_api_key)
        self._model = settings.gemini_model

    async def structure_log(self, text: str, ctx: LlmContext) -> StructuredResult:
        response = await self._client.aio.models.generate_content(
            model=self._model,
            contents=text,
            config=types.GenerateContentConfig(
                system_instruction=build_system_instruction(ctx),
                response_mime_type="application/json",
                temperature=0.2,
            ),
        )
        raw = (response.text or "").strip()
        try:
            return StructuredResult.model_validate_json(raw)
        except Exception:
            # Never hard-fail ingestion: fall back to a low-confidence memo.
            return StructuredResult(
                events=[
                    StructuredEvent(
                        type="memo", note=text, time=ctx.now, confidence=Confidence.low
                    )
                ],
                lang=ctx.lang or "en",
            )
