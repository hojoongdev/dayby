"""Provider factories. Swap implementations via settings (LLM_PROVIDER / STT_PROVIDER)."""
from ..config import settings
from .llm.base import LLMProvider
from .llm.mock import MockLLMProvider
from .stt.base import STTProvider
from .stt.mock import MockSTTProvider

_LLM_PROVIDERS: dict[str, type[LLMProvider]] = {"mock": MockLLMProvider}
_STT_PROVIDERS: dict[str, type[STTProvider]] = {"mock": MockSTTProvider}


def get_llm_provider() -> LLMProvider:
    try:
        return _LLM_PROVIDERS[settings.llm_provider]()
    except KeyError:
        raise ValueError(f"Unknown LLM_PROVIDER: {settings.llm_provider!r}")


def get_stt_provider() -> STTProvider:
    try:
        return _STT_PROVIDERS[settings.stt_provider]()
    except KeyError:
        raise ValueError(f"Unknown STT_PROVIDER: {settings.stt_provider!r}")
