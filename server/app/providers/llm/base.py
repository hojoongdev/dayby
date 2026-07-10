"""LLM provider interface."""
from abc import ABC, abstractmethod

from ...models.events import LlmContext, StructuredResult


class LLMProvider(ABC):
    """Turns a natural-language utterance into a StructuredResult."""

    name: str = "base"

    @abstractmethod
    async def structure_log(self, text: str, ctx: LlmContext) -> StructuredResult:
        ...
