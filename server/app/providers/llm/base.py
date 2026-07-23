"""LLM provider interface."""
from abc import ABC, abstractmethod
from datetime import datetime
from typing import Optional

from ...models.events import (
    CareSignal,
    DayStat,
    LlmContext,
    QueryPlan,
    StructuredResult,
    Tip,
    UpcomingEvent,
    WrappedStats,
)


class LLMProvider(ABC):
    """Turns a natural-language utterance into a StructuredResult."""

    name: str = "base"

    @abstractmethod
    async def structure_log(self, text: str, ctx: LlmContext) -> StructuredResult:
        ...

    @abstractmethod
    async def plan_query(self, question: str, ctx: LlmContext) -> QueryPlan:
        """Turn a question into a query over the whole history: which records to fetch,
        or which aggregate to compute. The server runs it; the model never writes Mongo."""
        ...

    @abstractmethod
    async def answer_query(
        self, question: str, events: list[dict], ctx: LlmContext
    ) -> str:
        """Answer a natural-language question grounded ONLY in the given records."""
        ...

    @abstractmethod
    async def structure_photo(
        self, image: bytes, mime_type: str, text: str, ctx: LlmContext
    ) -> StructuredResult:
        """Same as structure_log, but the caregiver also took a picture.

        `text` may be empty: a photo on its own is a valid thing to log.
        """
        ...

    @abstractmethod
    async def proactive_tips(
        self,
        signals: list[CareSignal],
        upcoming: list[UpcomingEvent],
        ctx: LlmContext,
        remind_at: Optional[datetime] = None,
        remind_topic: Optional[str] = None,
    ) -> list[Tip]:
        """Speak first: what the caregiver should hear before they ask.

        The signals are aggregated from the family's real logs and are the only
        facts available — the model writes the sentence, never the numbers.

        When `remind_at` is given, one of the returned lines should have kind
        "reminder": what to say in a notification at that moment, which has not
        arrived yet. When it is not, none should.
        """
        ...

    @abstractmethod
    async def write_wrapped(self, stats: WrappedStats, ctx: LlmContext) -> str:
        """Tell a whole babyhood back to the parent, from the tally of it."""
        ...

    @abstractmethod
    async def write_insights(self, days: list[DayStat], ctx: LlmContext) -> list[str]:
        """Read the week's trends off the day tally: what is changing, in the caller's
        language. The numbers are the only facts; the model writes the observation."""
        ...

    @abstractmethod
    async def resolve_target(
        self, hint: str, candidates: list[dict], ctx: LlmContext
    ) -> Optional[int]:
        """Which of these already-logged records does the caregiver mean?

        Returns an index into `candidates`, or None when it is not clear enough to
        act on. The model is shown records, never ids, so it cannot name one that
        does not exist.
        """
        ...
