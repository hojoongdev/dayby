"""LLM provider interface."""
from abc import ABC, abstractmethod

from ...models.events import LlmContext, StructuredResult


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
