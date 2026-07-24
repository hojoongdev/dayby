"""Natural speech via a Gemini TTS model. Returns a WAV the app can play directly.

The model hands back raw PCM (L16, 24 kHz mono); this wraps it in a WAV header. It reads
whatever language the text is in, so a Korean reply is spoken in Korean with no locale set.
"""
import logging
import struct
from typing import Optional

from google import genai
from google.genai import types

from ...config import settings
from .base import TTSProvider

logger = logging.getLogger("dayby.tts")


def _pcm_to_wav(pcm: bytes, rate: int = 24000, channels: int = 1, bits: int = 16) -> bytes:
    byte_rate = rate * channels * bits // 8
    block_align = channels * bits // 8
    return (
        b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVE"
        + b"fmt " + struct.pack("<IHHIIHH", 16, 1, channels, rate, byte_rate, block_align, bits)
        + b"data" + struct.pack("<I", len(pcm)) + pcm
    )


class GeminiTTSProvider(TTSProvider):
    name = "gemini"

    def __init__(self) -> None:
        if not settings.gemini_api_key:
            raise RuntimeError("GEMINI_API_KEY is not set (required for TTS_PROVIDER=gemini)")
        http = types.HttpOptions(timeout=settings.gemini_timeout_ms)
        self._client = genai.Client(
            vertexai=settings.google_genai_use_vertexai,
            api_key=settings.gemini_api_key,
            http_options=http,
        )
        self._model = settings.tts_model
        self._voice = settings.tts_voice

    async def synthesize(self, text: str, lang: Optional[str] = None) -> Optional[bytes]:
        if not text.strip():
            return None
        try:
            resp = await self._client.aio.models.generate_content(
                model=self._model,
                contents=text,
                config=types.GenerateContentConfig(
                    response_modalities=["AUDIO"],
                    speech_config=types.SpeechConfig(
                        voice_config=types.VoiceConfig(
                            prebuilt_voice_config=types.PrebuiltVoiceConfig(
                                voice_name=self._voice
                            )
                        )
                    ),
                ),
            )
            part = resp.candidates[0].content.parts[0]
            data = getattr(part, "inline_data", None)
            if data and data.data:
                return _pcm_to_wav(data.data)
            return None
        except Exception:
            # A missing voice is not worth failing the reply over; the app speaks it on-device.
            logger.exception("gemini tts failed")
            return None
