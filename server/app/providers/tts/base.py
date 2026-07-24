"""TTS provider interface."""
from abc import ABC, abstractmethod
from typing import Optional


class TTSProvider(ABC):
    """Turns the assistant's reply into speech."""

    name: str = "base"

    @abstractmethod
    async def synthesize(self, text: str, lang: Optional[str] = None) -> Optional[bytes]:
        """WAV audio for the text, or None when there is no server voice -- the app then
        falls back to on-device TTS, so a reply is always spoken one way or another."""
        ...
