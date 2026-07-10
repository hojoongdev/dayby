"""STT provider interface."""
from abc import ABC, abstractmethod


class STTProvider(ABC):
    """Transcribes audio to text."""

    name: str = "base"

    @abstractmethod
    async def transcribe(self, audio: bytes, lang: str | None = None) -> str:
        ...
