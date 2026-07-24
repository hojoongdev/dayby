"""OpenAI-compatible LLM provider.

Points at any /chat/completions endpoint -- a local Ollama or LM Studio, or a hosted
API -- so the model can be swapped, including for one running on your own machine. It
reuses the same prompts as the Gemini provider, so behaviour matches; only the transport
differs. Enable with LLM_PROVIDER=openai (or local) and OPENAI_BASE_URL / OPENAI_MODEL.
"""
import base64
import json
import logging
from datetime import datetime
from typing import Optional

import httpx

from ...config import settings
from ...models.events import (
    CareSignal,
    Confidence,
    DayStat,
    LlmContext,
    QueryPlan,
    StructuredEvent,
    StructuredResult,
    Tip,
    UpcomingEvent,
    WrappedStats,
)
from .base import LLMProvider
from .prompt import (
    build_insights_instruction,
    build_photo_instruction,
    build_query_instruction,
    build_query_plan_instruction,
    build_system_instruction,
    build_target_instruction,
    build_tips_instruction,
    build_wrapped_instruction,
)

logger = logging.getLogger("dayby.openai")


class OpenAICompatibleLLMProvider(LLMProvider):
    name = "openai"

    def __init__(self) -> None:
        self._base = settings.openai_base_url.rstrip("/")
        self._model = settings.openai_model
        self._headers = {"Content-Type": "application/json"}
        if settings.openai_api_key:
            self._headers["Authorization"] = f"Bearer {settings.openai_api_key}"
        self._timeout = settings.openai_timeout_ms / 1000

    async def _chat(
        self, system: str, user, *, json_mode: bool, temperature: float
    ) -> str:
        """One chat completion. `user` is a string, or a list of content parts for vision."""
        body: dict = {
            "model": self._model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "temperature": temperature,
        }
        if json_mode:
            # Servers that don't support this ignore it; the parsers below tolerate stray text.
            body["response_format"] = {"type": "json_object"}
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            res = await client.post(
                f"{self._base}/chat/completions", headers=self._headers, json=body
            )
            res.raise_for_status()
            data = res.json()
        return (data["choices"][0]["message"]["content"] or "").strip()

    async def structure_log(self, text: str, ctx: LlmContext) -> StructuredResult:
        try:
            out = await self._chat(
                build_system_instruction(ctx), text, json_mode=True, temperature=0.2
            )
            return StructuredResult.model_validate_json(out)
        except Exception:
            logger.exception("openai structure_log failed; falling back to memo")
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
        data_uri = f"data:{mime_type};base64," + base64.b64encode(image).decode()
        content = [
            {"type": "text", "text": said},
            {"type": "image_url", "image_url": {"url": data_uri}},
        ]
        try:
            out = await self._chat(
                build_photo_instruction(ctx), content, json_mode=True, temperature=0.2
            )
            return StructuredResult.model_validate_json(out)
        except Exception:
            # A local model may not do vision; keep the photo as a memo either way.
            logger.exception("openai structure_photo failed; falling back to memo")
            return StructuredResult(
                events=[
                    StructuredEvent(
                        type="memo", note=text or None, time=ctx.now,
                        confidence=Confidence.low,
                    )
                ],
                lang=ctx.lang or "en",
            )

    async def plan_query(self, question: str, ctx: LlmContext) -> QueryPlan:
        try:
            out = await self._chat(
                build_query_plan_instruction(ctx),
                f"Question: {question}",
                json_mode=True,
                temperature=0.0,
            )
            return QueryPlan.model_validate_json(out or "{}")
        except Exception:
            logger.exception("openai plan_query failed")
            return QueryPlan()

    async def answer_query(
        self, question: str, events: list[dict], ctx: LlmContext
    ) -> str:
        context = json.dumps(events, ensure_ascii=False, default=str)
        try:
            return await self._chat(
                build_query_instruction(ctx),
                f"Question: {question}\n\nLogged events (JSON): {context}",
                json_mode=False,
                temperature=0.2,
            )
        except Exception:
            logger.exception("openai answer_query failed")
            return "Sorry, I couldn't look that up right now."

    async def resolve_target(
        self, hint: str, candidates: list[dict], ctx: LlmContext
    ) -> Optional[int]:
        listing = "\n".join(
            f"{i}. {json.dumps(c, ensure_ascii=False, default=str)}"
            for i, c in enumerate(candidates)
        )
        try:
            out = await self._chat(
                build_target_instruction(ctx, hint),
                f"Recent records, newest first:\n{listing}",
                json_mode=True,
                temperature=0.0,
            )
            index = json.loads(out or "{}").get("index")
            if isinstance(index, int) and 0 <= index < len(candidates):
                return index
            return None
        except Exception:
            logger.exception("openai resolve_target failed")
            return None

    async def write_wrapped(self, stats: WrappedStats, ctx: LlmContext) -> str:
        try:
            return await self._chat(
                build_wrapped_instruction(ctx, stats),
                "Write the retrospective.",
                json_mode=False,
                temperature=0.8,
            )
        except Exception:
            logger.exception("openai write_wrapped failed")
            return ""

    async def write_insights(self, days: list[DayStat], ctx: LlmContext) -> list[str]:
        try:
            out = await self._chat(
                build_insights_instruction(ctx, days),
                "Write the week's observations.",
                json_mode=True,
                temperature=0.5,
            )
            data = json.loads(out or "{}")
            return [str(o).strip() for o in data.get("observations", []) if str(o).strip()][:3]
        except Exception:
            logger.exception("openai write_insights failed")
            return []

    async def proactive_tips(
        self,
        signals: list[CareSignal],
        upcoming: list[UpcomingEvent],
        ctx: LlmContext,
        remind_at: Optional[datetime] = None,
        remind_topic: Optional[str] = None,
    ) -> list[Tip]:
        try:
            out = await self._chat(
                build_tips_instruction(ctx, signals, upcoming, remind_at, remind_topic),
                "Write today's tips.",
                json_mode=True,
                temperature=0.6,
            )
            data = json.loads(out or "{}")
            return [Tip.model_validate(t) for t in data.get("tips", [])][:4]
        except Exception:
            logger.exception("openai proactive_tips failed")
            return []
