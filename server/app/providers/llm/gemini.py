"""Real LLM provider backed by Google Gemini (AI Studio or Vertex AI Express).

Handles arbitrary phrasing in any language (English, Korean, ...). Requires
GEMINI_API_KEY; the model id is configurable via GEMINI_MODEL. Set
GOOGLE_GENAI_USE_VERTEXAI=true to use a Vertex AI Express api key.
"""
import json
import logging
from datetime import datetime
from typing import Optional

from google import genai
from google.genai import types

from ...config import settings
from ...models.events import (
    CareSignal,
    Confidence,
    LlmContext,
    StructuredEvent,
    StructuredResult,
    Tip,
    UpcomingEvent,
    WrappedStats,
)
from .base import LLMProvider
from .prompt import (
    build_photo_instruction,
    build_query_instruction,
    build_system_instruction,
    build_target_instruction,
    build_tips_instruction,
    build_wrapped_instruction,
)

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

    async def structure_photo(
        self, image: bytes, mime_type: str, text: str, ctx: LlmContext
    ) -> StructuredResult:
        said = text.strip() or "(the caregiver said nothing; describe the photo)"
        try:
            response = await self._client.aio.models.generate_content(
                model=self._model,
                contents=[
                    types.Part.from_bytes(data=image, mime_type=mime_type),
                    types.Part.from_text(text=said),
                ],
                config=types.GenerateContentConfig(
                    system_instruction=build_photo_instruction(ctx),
                    response_mime_type="application/json",
                    temperature=0.2,
                ),
            )
            return StructuredResult.model_validate_json((response.text or "").strip())
        except Exception:
            # A photo is never worth losing: keep it as a memo the caregiver can edit.
            logger.exception("Gemini photo structuring failed; falling back to memo")
            return StructuredResult(
                events=[
                    StructuredEvent(
                        type="memo", note=text or None, time=ctx.now,
                        confidence=Confidence.low,
                    )
                ],
                lang=ctx.lang or "en",
            )

    async def answer_query(
        self, question: str, events: list[dict], ctx: LlmContext
    ) -> str:
        context = json.dumps(events, ensure_ascii=False, default=str)
        try:
            response = await self._client.aio.models.generate_content(
                model=self._model,
                contents=f"Question: {question}\n\nLogged events (JSON): {context}",
                config=types.GenerateContentConfig(
                    system_instruction=build_query_instruction(ctx),
                    temperature=0.2,
                ),
            )
            return (response.text or "").strip()
        except Exception:
            logger.exception("Gemini answer_query failed")
            return "Sorry, I couldn't look that up right now."

    async def resolve_target(
        self, hint: str, candidates: list[dict], ctx: LlmContext
    ) -> Optional[int]:
        listing = "\n".join(
            f"{i}. {json.dumps(c, ensure_ascii=False, default=str)}"
            for i, c in enumerate(candidates)
        )
        try:
            response = await self._client.aio.models.generate_content(
                model=self._model,
                contents=f"Recent records, newest first:\n{listing}",
                config=types.GenerateContentConfig(
                    system_instruction=build_target_instruction(ctx, hint),
                    response_mime_type="application/json",
                    temperature=0.0,  # picking a record is not a creative act
                ),
            )
            index = json.loads((response.text or "{}").strip()).get("index")
            if isinstance(index, int) and 0 <= index < len(candidates):
                return index
            return None
        except Exception:
            # Not knowing which record they meant is a fine answer; guessing is not.
            logger.exception("Gemini resolve_target failed")
            return None

    async def write_wrapped(self, stats: WrappedStats, ctx: LlmContext) -> str:
        try:
            response = await self._client.aio.models.generate_content(
                model=self._model,
                contents="Write the retrospective.",
                config=types.GenerateContentConfig(
                    system_instruction=build_wrapped_instruction(ctx, stats),
                    temperature=0.8,  # it is a keepsake, not a report
                ),
            )
            return (response.text or "").strip()
        except Exception:
            # The numbers are the keepsake; the story is the wrapping paper.
            logger.exception("Gemini write_wrapped failed")
            return ""

    async def proactive_tips(
        self,
        signals: list[CareSignal],
        upcoming: list[UpcomingEvent],
        ctx: LlmContext,
        remind_at: Optional[datetime] = None,
        remind_topic: Optional[str] = None,
    ) -> list[Tip]:
        try:
            response = await self._client.aio.models.generate_content(
                model=self._model,
                contents="Write today's tips.",
                config=types.GenerateContentConfig(
                    system_instruction=build_tips_instruction(
                        ctx, signals, upcoming, remind_at, remind_topic
                    ),
                    response_mime_type="application/json",
                    # Warmer than structuring: the same three sentences every hour
                    # would stop being worth reading.
                    temperature=0.6,
                ),
            )
            data = json.loads((response.text or "{}").strip())
            return [Tip.model_validate(t) for t in data.get("tips", [])][:4]
        except Exception:
            # Tips are a bonus surface: on failure the card simply does not appear.
            logger.exception("Gemini proactive_tips failed")
            return []
