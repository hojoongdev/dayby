"""LLM provider interface."""
from abc import ABC, abstractmethod

from ...models.events import (
    CareSignal,
    LlmContext,
    StructuredResult,
    Tip,
    UpcomingEvent,
)


class LLMProvider(ABC):
    """Turns a natural-language utterance into a StructuredResult."""

    name: str = "base"

    @abstractmethod
    async def structure_log(self, text: str, ctx: LlmContext) -> StructuredResult:
        ...

    @abstractmethod
    async def answer_query(
        self, question: str, events: list[dict], ctx: LlmContext
    ) -> str:
        """Answer a natural-language question grounded ONLY in the given events."""
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
    ) -> list[Tip]:
        """Speak first: what the caregiver should hear before they ask.

        The signals are aggregated from the family's real logs and are the only
        facts available — the model writes the sentence, never the numbers.
        """
        ...
