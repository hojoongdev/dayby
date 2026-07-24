"""Provider factories. Swap implementations via settings (LLM_PROVIDER / STT_PROVIDER)."""
from ..config import settings
from .llm.base import LLMProvider
from .llm.mock import MockLLMProvider
from .stt.base import STTProvider
from .stt.mock import MockSTTProvider
from .tts.base import TTSProvider
from .tts.mock import MockTTSProvider


def get_llm_provider() -> LLMProvider:
    name = settings.llm_provider
    if name == "mock":
        return MockLLMProvider()
    if name == "gemini":
        # Lazy import so google-genai is only loaded when actually used.
        from .llm.gemini import GeminiLLMProvider

        return GeminiLLMProvider()
    if name in ("openai", "local"):
        # Any OpenAI-compatible endpoint, including a local Ollama or LM Studio.
        from .llm.openai_compatible import OpenAICompatibleLLMProvider

        return OpenAICompatibleLLMProvider()
    raise ValueError(f"Unknown LLM_PROVIDER: {name!r}")


def get_stt_provider() -> STTProvider:
    name = settings.stt_provider
    if name == "mock":
        return MockSTTProvider()
    if name == "gemini":
        from .stt.gemini import GeminiSTTProvider

        return GeminiSTTProvider()
    raise ValueError(f"Unknown STT_PROVIDER: {name!r}")


def get_tts_provider() -> TTSProvider:
    name = settings.tts_provider
    if name == "mock":
        return MockTTSProvider()
    if name == "gemini":
        from .tts.gemini import GeminiTTSProvider

        return GeminiTTSProvider()
    raise ValueError(f"Unknown TTS_PROVIDER: {name!r}")
