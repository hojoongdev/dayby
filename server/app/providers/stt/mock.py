"""Offline STT stand-in. Real STT (cloud / on-device) arrives with voice in P2."""
from .base import STTProvider


class MockSTTProvider(STTProvider):
    name = "mock"
    transcript = "formula 120ml"

    async def transcribe(self, audio: bytes, lang: str | None = None) -> str:
        return self.transcript
