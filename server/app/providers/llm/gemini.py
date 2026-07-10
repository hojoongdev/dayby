"""Real LLM provider backed by Google Gemini (AI Studio or Vertex AI Express).

Handles arbitrary phrasing in any language (English, Korean, ...). Requires
GEMINI_API_KEY; the model id is configurable via GEMINI_MODEL. Set
GOOGLE_GENAI_USE_VERTEXAI=true to use a Vertex AI Express api key.
"""
import logging

from google import genai
from google.genai import types

from ...config import settings
from ...models.events import Confidence, LlmContext, StructuredEvent, StructuredResult
from .base import LLMProvider
from .prompt import build_system_instruction

logger = logging.getLogger("dayby.gemini")


class GeminiLLMProvider(LLMProvider):
    name = "gemini"

    def __init__(self) -> None:
        if not settings.gemini_api_key:
            raise RuntimeError("GEMINI_API_KEY is not set (required for LLM_PROVIDER=gemini)")
        if settings.google_genai_use_vertexai:
            # Vertex AI Express mode: api key + vertexai=True, no GCP project needed.
            self._client = genai.Client(vertexai=True, api_key=settings.gemini_api_key)
        else:
            self._client = genai.Client(api_key=settings.gemini_api_key)
        self._model = settings.gemini_model

    async def structure_log(self, text: str, ctx: LlmContext) -> StructuredResult:
        try:
            response = await self._client.aio.models.generate_content(
                model=self._model,
                contents=text,
                config=types.GenerateContentConfig(
                    system_instruction=build_system_instruction(ctx),
                    response_mime_type="application/json",
                    temperature=0.2,
                ),
            )
            return StructuredResult.model_validate_json((response.text or "").strip())
        except Exception:
            # Never hard-fail ingestion: log the cause and fall back to a low-confidence memo.
            logger.exception("Gemini structuring failed; falling back to memo")
            return StructuredResult(
                events=[
                    StructuredEvent(
                        type="memo", note=text, time=ctx.now, confidence=Confidence.low
                    )
                ],
                lang=ctx.lang or "en",
            )
