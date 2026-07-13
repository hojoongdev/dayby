"""Real speech-to-text, backed by Gemini's audio understanding.

The point is not only that it is real. On-device recognition has to be told which
language to listen for, which is why the app carries a KO/EN toggle at all. This
one is told nothing and returns whatever was actually said — so a parent can switch
mid-sentence and nobody has to touch a setting.
"""
import logging
from typing import Optional

from google import genai
from google.genai import types

from ... import lang
from ...config import settings
from .base import STTProvider

logger = logging.getLogger("dayby.stt")

# What Gemini accepts as inline audio.
SUPPORTED_TYPES = (
    "audio/wav",
    "audio/x-wav",
    "audio/mpeg",
    "audio/mp3",
    "audio/aiff",
    "audio/aac",
    "audio/ogg",
    "audio/flac",
    "audio/mp4",
    "audio/m4a",
)

INSTRUCTION = """You transcribe short recordings of a parent logging something about
their baby — a feed, a nappy change, a temperature, a question. They are usually holding
the baby, often in a room with the baby crying in it.

- Write exactly what was said, in the language it was said in. Never translate.
- Return the transcript and nothing else: no quotes, no speaker labels, no timestamps,
  no apology, no commentary.
- If the recording contains no intelligible speech, return an empty string."""


class GeminiSTTProvider(STTProvider):
    name = "gemini"

    def __init__(self) -> None:
        if not settings.gemini_api_key:
            raise RuntimeError(
                "GEMINI_API_KEY is not set (required for STT_PROVIDER=gemini)"
            )
        if settings.google_genai_use_vertexai:
            self._client = genai.Client(vertexai=True, api_key=settings.gemini_api_key)
        else:
            self._client = genai.Client(api_key=settings.gemini_api_key)
        self._model = settings.gemini_model

    async def transcribe(
        self, audio: bytes, mime_type: str, languages: Optional[list[str]] = None
    ) -> str:
        spoken = lang.spoken(languages or [])
        # Not a hint. Left to guess from the sound alone, a Korean sentence said quietly
        # over a crying baby comes back as Chinese; knowing which languages are even on
        # the table is what stops that.
        hint = (
            f"This caregiver speaks only: {spoken}. What was said is in one of those and "
            "nothing else. If it sounds like some other language, you have misheard — "
            "transcribe it as whichever of theirs it most nearly is."
        )
        try:
            response = await self._client.aio.models.generate_content(
                model=self._model,
                contents=[
                    types.Part.from_bytes(data=audio, mime_type=mime_type),
                    types.Part.from_text(text=hint),
                ],
                config=types.GenerateContentConfig(
                    system_instruction=INSTRUCTION,
                    temperature=0.0,
                ),
            )
            return (response.text or "").strip()
        except Exception:
            # An empty transcript is what the caller already has to handle: it means
            # "say that again", which is also the right thing to say here.
            logger.exception("Gemini transcription failed")
            return ""
