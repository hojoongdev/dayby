"""STT provider interface."""
from abc import ABC, abstractmethod
from typing import Optional


class STTProvider(ABC):
    """Transcribes audio to text."""

    name: str = "base"

    @abstractmethod
    async def transcribe(
        self, audio: bytes, mime_type: str, languages: Optional[list[str]] = None
    ) -> str:
        """What was said, in the language it was said in.

        `languages` is the set this caregiver says they speak, and it is a constraint
        rather than a hint: nothing they say to Dayby is in any other one. Without it, a
        Korean sentence said quietly over a crying baby comes back as Chinese. Inside the
        set the transcriber is still free — a Korean speaker who says "120 ml formula"
        gets it back in English, and may switch mid-sentence.
        """
        ...
