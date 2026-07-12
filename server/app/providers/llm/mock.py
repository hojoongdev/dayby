"""Deterministic, offline LLM stand-in.

Recognizes a few common ENGLISH logging phrases so the full ingest pipeline runs
with no API keys (local dev and tests). Real providers (added later, behind an API
key) handle arbitrary phrasing in any language via the model itself; this mock
stays intentionally simple and language-limited.
"""
import re
from datetime import datetime
from typing import Optional

from ...care import OVERDUE_AFTER
from ...models.events import (
    Action,
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

_NUMBER = re.compile(r"(\d+(?:\.\d+)?)")
_QUESTION_HINTS = ("?", "when ", "how much", "how many", "how long", "last ", "total")
_DELETE_HINTS = ("delete", "remove", "undo", "scratch that")
_EDIT_HINTS = ("change", "correct", "actually", "make it", "fix")


def _first_number(text: str) -> int | float | None:
    match = _NUMBER.search(text)
    if not match:
        return None
    value = float(match.group(1))
    return int(value) if value.is_integer() else value


class MockLLMProvider(LLMProvider):
    name = "mock"

    async def answer_query(
        self, question: str, events: list[dict], ctx: LlmContext
    ) -> str:
        # Offline stand-in: real answering needs a real model. Give a truthful
        # fallback that still reflects the data size.
        return f"I have {len(events)} logged events, but I need a real model to answer that."

    async def proactive_tips(
        self,
        signals: list[CareSignal],
        upcoming: list[UpcomingEvent],
        ctx: LlmContext,
        remind_at: Optional[datetime] = None,
        remind_topic: Optional[str] = None,
    ) -> list[Tip]:
        # Nudges and reminders are arithmetic on real signals, so the mock gets those
        # right offline. The age tip is knowledge, so it stays honest about needing
        # a real model.
        tips: list[Tip] = []

        overdue = [
            s for s in signals
            if s.hours_since is not None
            and s.type in OVERDUE_AFTER
            and s.hours_since >= OVERDUE_AFTER[s.type].total_seconds() / 3600
            # A sleep still going is not a sleep that is overdue.
            and not (s.type == "sleep" and s.last_subtype == "start")
        ]
        if overdue:
            worst = max(overdue, key=lambda s: s.hours_since or 0)
            tips.append(Tip(
                kind="nudge",
                topic=worst.type,
                text=f"It has been {worst.hours_since} hours since the last {worst.type}.",
            ))

        if upcoming:
            soonest = upcoming[0]
            label = soonest.label or soonest.type
            tips.append(Tip(
                kind="nudge",
                topic=soonest.type,
                text=f"Coming up in {soonest.hours_until} hours: {label}.",
            ))

        if not signals:
            tips.append(Tip(
                kind="tip",
                topic="getting-started",
                text='Nothing logged yet — try "120 ml formula" to start.',
            ))
        else:
            who = ctx.baby_profiles[0] if ctx.baby_profiles else "your baby"
            tips.append(Tip(
                kind="tip",
                topic="development",
                text=f"Age tips for {who} need a real model.",
            ))

        if remind_at is not None and remind_topic is not None:
            tips.append(Tip(
                kind="reminder",
                topic=remind_topic,
                text=f"It has been a while since the last {remind_topic} — worth a look.",
            ))
        return tips

    async def write_wrapped(self, stats: WrappedStats, ctx: LlmContext) -> str:
        # The story is the one part that has to be written; the app shows the
        # numbers either way, so an empty story is an honest offline answer.
        return ""

    async def structure_photo(
        self, image: bytes, mime_type: str, text: str, ctx: LlmContext
    ) -> StructuredResult:
        # Seeing is the one thing a mock cannot fake. Keep the photo, classify from
        # the words alone, and be honest that nobody looked at the picture.
        lang = ctx.lang or "en"
        if not text.strip():
            return StructuredResult(
                events=[StructuredEvent(
                    type="memo", time=ctx.now, confidence=Confidence.low,
                )],
                reply="Photo saved. Looking at it needs a real model.",
                lang=lang,
            )
        result = await self.structure_log(text, ctx)
        result.reply = f"Photo saved. {result.reply or ''}".strip()
        return result

    async def resolve_target(
        self, hint: str, candidates: list[dict], ctx: LlmContext
    ) -> int | None:
        # Candidates are newest first, so "the last feeding" is the first one whose
        # kind is named. Naming no kind at all means the last thing logged.
        lower = hint.lower()
        for index, candidate in enumerate(candidates):
            if str(candidate.get("type", "")).lower() in lower:
                return index
        return 0 if candidates else None

    async def structure_log(self, text: str, ctx: LlmContext) -> StructuredResult:
        lower = text.lower().strip()
        lang = ctx.lang or "en"

        # Correcting or removing something comes first: "delete the last feeding"
        # also reads as a question about the last feeding.
        if any(hint in lower for hint in _DELETE_HINTS):
            return StructuredResult(
                action=Action.delete,
                target_hint=text,
                reply="Delete that?",
                lang=lang,
            )
        if any(hint in lower for hint in _EDIT_HINTS):
            return StructuredResult(
                action=Action.update,
                target_hint=text,
                events=[self._classify(text, lower, ctx.now)],
                reply="Change it to that?",
                lang=lang,
            )

        # A question is a query, not a new record.
        if any(hint in lower for hint in _QUESTION_HINTS):
            return StructuredResult(
                action=Action.query,
                query_text=text,
                reply="I can't answer questions yet.",
                lang=lang,
            )

        event = self._classify(text, lower, ctx.now)
        readback = event.type if not event.subtype else f"{event.type} ({event.subtype})"
        return StructuredResult(
            action=Action.create,
            events=[event],
            reply=f"Got it: {readback}. Save it?",
            lang=lang,
        )

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
