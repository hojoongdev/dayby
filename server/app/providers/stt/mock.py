"""Offline STT stand-in, so the voice endpoint runs with no API keys."""
from typing import Optional

from .base import STTProvider


class MockSTTProvider(STTProvider):
    name = "mock"
    transcript = "formula 120ml"

    async def transcribe(
        self, audio: bytes, mime_type: str, languages: Optional[list[str]] = None
    ) -> str:
        return self.transcript
