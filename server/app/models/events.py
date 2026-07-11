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
    "pumping", "growth", "milestone", "memo", "other",
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
    lang: str = "ko"


class LlmContext(BaseModel):
    """Context injected into the LLM for every utterance."""

    now: datetime
    baby_names: list[str] = Field(default_factory=list)
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
