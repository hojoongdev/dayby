"""STT provider interface."""
from abc import ABC, abstractmethod
from typing import Optional


class STTProvider(ABC):
    """Transcribes audio to text."""

    name: str = "base"

    @abstractmethod
    async def transcribe(
        self, audio: bytes, mime_type: str, lang: Optional[str] = None
    ) -> str:
        """What was said, in the language it was said in.

        `lang` is at most a hint about who is usually holding the phone. It must
        never force the answer: a Korean-speaking parent saying "120 ml formula"
        should come back in English.
        """
        ...
