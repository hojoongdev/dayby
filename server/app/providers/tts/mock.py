"""Mock TTS: no server voice. The app falls back to on-device TTS, so the whole flow
still speaks with no API key."""
from typing import Optional

from .base import TTSProvider


class MockTTSProvider(TTSProvider):
    name = "mock"

    async def synthesize(self, text: str, lang: Optional[str] = None) -> Optional[bytes]:
        return None
