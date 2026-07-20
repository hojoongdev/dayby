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


class Role(str, Enum):
    user = "user"
    assistant = "assistant"


class Turn(BaseModel):
    """One line of the chat, as it was shown to the user.

    Includes the lines confirming a save: an event that was offered but never confirmed
    is not in the timeline, and the model has to tell those apart.
    """

    role: Role
    text: str


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

    # For update/delete: the record the server believes "the last feeding" means.
    # The model never sees an id, so it cannot invent one -- the server looks the
    # target up in the real timeline and puts it here for the caregiver to confirm.
    target: Optional["EventOut"] = None


class LlmContext(BaseModel):
    """Context injected into the LLM for every utterance."""

    now: datetime
    baby_names: list[str] = Field(default_factory=list)
    # e.g. "Haein (5 months old, female)" — lets the model answer/tip by age.
    baby_profiles: list[str] = Field(default_factory=list)
    lang: Optional[str] = None
    # The languages this caregiver says they speak. Nothing said to Dayby is in any other
    # one, and saying so is what stops a mumbled Korean sentence coming back as Chinese.
    languages: list[str] = Field(default_factory=list)
    # The chat so far, oldest first. What "actually 200" and "and yesterday?" resolve against.
    history: list[Turn] = Field(default_factory=list)


class IngestTextRequest(BaseModel):
    text: str
    lang: Optional[str] = None
    languages: list[str] = Field(default_factory=list)
    baby_ref: Optional[str] = None
    now: Optional[datetime] = None
    history: list[Turn] = Field(default_factory=list)


class IngestVoiceResponse(BaseModel):
    """Voice ingest: what the STT heard plus the structured result."""

    transcript: str
    result: StructuredResult


class IngestPhotoResponse(BaseModel):
    """Photo ingest: where the photo was stored plus the structured result.

    The photo is already in GridFS by the time this returns, and its id is stitched
    into every event's `fields`, so confirming the result saves the picture with it.
    """

    photo_id: str
    result: StructuredResult


class CareSignal(BaseModel):
    """One event type's recent history, aggregated from the family's real logs.

    These are the facts a proactive tip is allowed to lean on: the model writes the
    sentence, but never the numbers.
    """

    type: str
    last_time: Optional[datetime] = None
    # Whether the last one was a "start" or an "end" matters: a sleep that started
    # two hours ago and never ended means the baby is asleep right now.
    last_subtype: Optional[str] = None
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

    # "nudge"    something looks overdue right now
    # "tip"      age-appropriate guidance
    # "reminder" what to say later, in a notification, when the next gap opens up
    kind: str = "tip"
    topic: Optional[str] = None
    text: str


class ScheduledReminder(BaseModel):
    """One nudge to hand the phone, to arrive at a set moment with Dayby closed.

    Either the overdue-gap nudge the assistant writes, or a rule the family set for
    itself ("after a feeding, give vitamin D in 30 minutes").
    """

    at: datetime
    text: str


class AssistantTips(BaseModel):
    tips: list[Tip] = Field(default_factory=list)
    signals: list[CareSignal] = Field(default_factory=list)
    upcoming: list[UpcomingEvent] = Field(default_factory=list)

    # Everything to hand the operating system, so it arrives whether or not Dayby is
    # running -- the overdue-gap nudge plus whatever rules the family has set.
    scheduled: list[ScheduledReminder] = Field(default_factory=list)

    # The soonest of the above, kept for the app that still reads a single one.
    remind_at: Optional[datetime] = None
    reminder: Optional[str] = None

    lang: str = "en"


class Spend(BaseModel):
    currency: str
    total: float
    count: int


class Milestone(BaseModel):
    time: datetime
    text: Optional[str] = None


class WrappedStats(BaseModel):
    """A whole babyhood, counted. Every number comes from one aggregation pass."""

    days_tracked: int = 0
    total_events: int = 0
    first_log: Optional[datetime] = None
    last_log: Optional[datetime] = None

    feedings: int = 0
    total_feed_ml: float = 0
    night_feeds: int = 0
    diapers: int = 0
    sleeps: int = 0

    busiest_day: Optional[str] = None
    busiest_day_events: int = 0
    top_types: dict[str, int] = Field(default_factory=dict)
    spend: list[Spend] = Field(default_factory=list)
    milestones: list[Milestone] = Field(default_factory=list)

    first_weight_kg: Optional[float] = None
    last_weight_kg: Optional[float] = None
    first_height_cm: Optional[float] = None
    last_height_cm: Optional[float] = None


class Wrapped(BaseModel):
    stats: WrappedStats
    # The model's retrospective, written from the numbers above and nothing else.
    story: str = ""
    lang: str = "en"


class DayStat(BaseModel):
    """One day, as the caregiver lived it — their midnight, not UTC's."""

    date: str
    feeds: int = 0
    feed_ml: float = 0
    # What actually changes as a baby grows is not how much they take but how long they
    # go between takes.
    avg_feed_gap_min: Optional[int] = None
    diapers: dict[str, int] = Field(default_factory=dict)
    nap_min: int = 0
    night_sleep_min: int = 0


class GrowthPoint(BaseModel):
    time: datetime
    weight_kg: Optional[float] = None
    height_cm: Optional[float] = None


class RhythmBlock(BaseModel):
    """One block on the 24-hour view: a day, a kind, and where it falls on the clock.

    A sleep is a long block; a feed or a nappy is a mark. Laid one day above another, the
    shape of a baby's day is the thing a parent can actually see changing.
    """

    date: str
    type: str
    # Minutes past the caregiver's own midnight, so the blocks line up under each other.
    start_min: int
    minutes: int = 0


class Stats(BaseModel):
    days: list[DayStat] = Field(default_factory=list)
    growth: list[GrowthPoint] = Field(default_factory=list)
    rhythm: list[RhythmBlock] = Field(default_factory=list)


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


class EventUpdate(BaseModel):
    """A correction. Only what is given changes; `fields` merges rather than replaces,
    so "actually it was 150" does not wipe everything else that was said."""

    type: Optional[str] = None
    subtype: Optional[str] = None
    fields: Optional[dict[str, Any]] = None
    time: Optional[datetime] = None
    note: Optional[str] = None


class EventOut(BaseModel):
    id: str
    baby_id: str
    type: str
    subtype: Optional[str] = None
    fields: dict[str, Any] = Field(default_factory=dict)
    time: datetime
    note: Optional[str] = None
    source: Optional[str] = None
    # Which parent logged it. Null where the server asks nobody to sign in, because then
    # there is nobody to have been.
    created_by: Optional[str] = None
    created_at: datetime


# StructuredResult.target refers to EventOut, which is defined below it.
StructuredResult.model_rebuild()
