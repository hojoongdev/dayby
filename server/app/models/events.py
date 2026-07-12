"""Domain schemas for structured baby-care logging (spec section 5.2)."""
from datetime import datetime
from enum import Enum
from typing import Any, Optional

from pydantic import BaseModel, Field


class Action(str, Enum):
    create = "create"
    update = "update"
    delete = "delete"
    query = "query"


class Confidence(str, Enum):
    high = "high"
    medium = "medium"
    low = "low"


# Recommended standard event types. The schema is intentionally open: anything
# outside this list is still valid (stored as-is with type "other" or a custom type).
STANDARD_EVENT_TYPES = (
    "feeding", "sleep", "diaper", "bath", "medicine", "temperature",
    "pumping", "growth", "milestone", "todo", "appointment", "memo", "other",
)


class StructuredEvent(BaseModel):
    type: str
    subtype: Optional[str] = None
    fields: dict[str, Any] = Field(default_factory=dict)
    time: Optional[datetime] = None
    note: Optional[str] = None
    confidence: Confidence = Confidence.medium


class StructuredResult(BaseModel):
    """What the LLM returns for a single utterance."""

    action: Action = Action.create
    baby_ref: Optional[str] = None
    events: list[StructuredEvent] = Field(default_factory=list)
    target_hint: Optional[str] = None
    query_text: Optional[str] = None
    needs_clarification: Optional[str] = None
    # A short, friendly spoken confirmation in the caller's own language, for the
    # app to speak (TTS) and show in the chat. Never hardcoded — the model writes it.
    reply: Optional[str] = None
    # A settings change requested by voice, e.g. {"temp": "f", "volume": "oz"}.
    # When present, the app applies it instead of saving an event.
    settings: Optional[dict[str, Any]] = None
    lang: str = "ko"


class LlmContext(BaseModel):
    """Context injected into the LLM for every utterance."""

    now: datetime
    baby_names: list[str] = Field(default_factory=list)
    # e.g. "해인 (5 months old, female)" — lets the model answer/tip by age.
    baby_profiles: list[str] = Field(default_factory=list)
    lang: Optional[str] = None


class IngestTextRequest(BaseModel):
    text: str
    lang: Optional[str] = None
    baby_ref: Optional[str] = None
    now: Optional[datetime] = None


class IngestVoiceResponse(BaseModel):
    """Voice ingest: what the STT heard plus the structured result."""

    transcript: str
    result: StructuredResult


class CareSignal(BaseModel):
    """One event type's recent history, aggregated from the family's real logs.

    These are the facts a proactive tip is allowed to lean on: the model writes the
    sentence, but never the numbers.
    """

    type: str
    last_time: Optional[datetime] = None
    hours_since: Optional[float] = None
    count_today: int = 0
    total: int = 0


class UpcomingEvent(BaseModel):
    """A logged event still ahead of us: an appointment, a todo with a due date."""

    type: str
    time: datetime
    hours_until: float
    label: Optional[str] = None


class Tip(BaseModel):
    """A short proactive line the assistant says before being asked."""

    # "nudge" = something looks overdue; "tip" = age-appropriate guidance.
    kind: str = "tip"
    topic: Optional[str] = None
    text: str


class AssistantTips(BaseModel):
    tips: list[Tip] = Field(default_factory=list)
    signals: list[CareSignal] = Field(default_factory=list)
    upcoming: list[UpcomingEvent] = Field(default_factory=list)
    lang: str = "en"


class EventCreate(BaseModel):
    """A confirmed event to persist (after the user reviews the ingest result)."""

    baby_id: str
    type: str
    subtype: Optional[str] = None
    fields: dict[str, Any] = Field(default_factory=dict)
    time: Optional[datetime] = None
    note: Optional[str] = None
    source: Optional[str] = None  # "voice" | "text" | "intent"
    raw_text: Optional[str] = None


class EventOut(BaseModel):
    id: str
    baby_id: str
    type: str
    subtype: Optional[str] = None
    fields: dict[str, Any] = Field(default_factory=dict)
    time: datetime
    note: Optional[str] = None
    source: Optional[str] = None
    created_at: datetime
