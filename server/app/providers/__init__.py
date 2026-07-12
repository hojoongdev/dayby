"""Provider factories. Swap implementations via settings (LLM_PROVIDER / STT_PROVIDER)."""
from ..config import settings
from .llm.base import LLMProvider
from .llm.mock import MockLLMProvider
from .stt.base import STTProvider
from .stt.mock import MockSTTProvider


def get_llm_provider() -> LLMProvider:
    name = settings.llm_provider
    if name == "mock":
        return MockLLMProvider()
    if name == "gemini":
        # Lazy import so google-genai is only loaded when actually used.
        from .llm.gemini import GeminiLLMProvider

        return GeminiLLMProvider()
    raise ValueError(f"Unknown LLM_PROVIDER: {name!r}")


def get_stt_provider() -> STTProvider:
    name = settings.stt_provider
    if name == "mock":
        return MockSTTProvider()
    if name == "gemini":
        from .stt.gemini import GeminiSTTProvider

        return GeminiSTTProvider()
    raise ValueError(f"Unknown STT_PROVIDER: {name!r}")
