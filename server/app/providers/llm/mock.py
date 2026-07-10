"""Deterministic, offline LLM stand-in.

Recognizes a few common ENGLISH logging phrases so the full ingest pipeline runs
with no API keys (local dev and tests). Real providers (added later, behind an API
key) handle arbitrary phrasing in any language via the model itself; this mock
stays intentionally simple and language-limited.
"""
import re
from datetime import datetime

from ...models.events import (
    Action,
    Confidence,
    LlmContext,
    StructuredEvent,
    StructuredResult,
)
from .base import LLMProvider

_NUMBER = re.compile(r"(\d+(?:\.\d+)?)")
_QUESTION_HINTS = ("?", "when ", "how much", "how many", "how long", "last ", "total")


def _first_number(text: str) -> int | float | None:
    match = _NUMBER.search(text)
    if not match:
        return None
    value = float(match.group(1))
    return int(value) if value.is_integer() else value


class MockLLMProvider(LLMProvider):
    name = "mock"

    async def structure_log(self, text: str, ctx: LlmContext) -> StructuredResult:
        lower = text.lower().strip()
        lang = ctx.lang or "en"

        # A question is a query, not a new record.
        if any(hint in lower for hint in _QUESTION_HINTS):
            return StructuredResult(action=Action.query, query_text=text, lang=lang)

        event = self._classify(text, lower, ctx.now)
        return StructuredResult(action=Action.create, events=[event], lang=lang)

    def _classify(self, text: str, lower: str, now: datetime) -> StructuredEvent:
        number = _first_number(lower)

        if any(k in lower for k in ("formula", "breast", "milk", "feed", "solid", "bottle")):
            if "formula" in lower or "bottle" in lower:
                subtype = "formula"
            elif "breast" in lower or "milk" in lower:
                subtype = "breast"
            elif "solid" in lower:
                subtype = "solid"
            else:
                subtype = None
            fields: dict = {}
            if number is not None:
                fields["amount_oz" if "oz" in lower else "amount_ml"] = number
            return StructuredEvent(
                type="feeding",
                subtype=subtype,
                fields=fields,
                time=now,
                confidence=Confidence.high if subtype else Confidence.medium,
            )

        if any(k in lower for k in ("diaper", "pee", "poop", "wet", "dirty")):
            if "wet" in lower or "pee" in lower:
                subtype = "wet"
            elif "dirty" in lower or "poop" in lower:
                subtype = "dirty"
            else:
                subtype = "mixed"
            return StructuredEvent(type="diaper", subtype=subtype, time=now, confidence=Confidence.high)

        if any(k in lower for k in ("sleep", "asleep", "nap", "woke", "awake", "wake")):
            subtype = "end" if any(k in lower for k in ("woke", "awake", "wake")) else "start"
            return StructuredEvent(type="sleep", subtype=subtype, time=now, confidence=Confidence.high)

        if "pump" in lower:
            fields = {"amount_ml": number} if number is not None else {}
            return StructuredEvent(type="pumping", fields=fields, time=now, confidence=Confidence.high)

        if any(k in lower for k in ("temp", "temperature", "fever")):
            fields = {"celsius": number} if number is not None else {}
            return StructuredEvent(type="temperature", fields=fields, time=now, confidence=Confidence.medium)

        if "bath" in lower:
            return StructuredEvent(type="bath", time=now, confidence=Confidence.high)

        if any(k in lower for k in ("medicine", "tylenol", "ibuprofen", "vitamin")):
            return StructuredEvent(type="medicine", note=text, time=now, confidence=Confidence.medium)

        return StructuredEvent(type="memo", note=text, time=now, confidence=Confidence.low)
