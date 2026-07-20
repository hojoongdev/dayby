"""User-defined care reminders.

A family writes its own rules -- "after each feeding, remind me to give vitamin D in
30 minutes", or "every day at 20:00, bath time". The server keeps the rules; the
assistant turns the active ones into the next thing the phone should say, in the same
place it already computes the overdue-gap nudge.
"""
from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, model_validator


class RoutineKind(str, Enum):
    # Fire delay_min after every logged event of trigger_type.
    after_event = "after_event"
    # Fire every day at time_local (the caregiver's own clock).
    daily = "daily"


def _valid_hhmm(value: str) -> bool:
    hours, _, minutes = value.partition(":")
    return (
        hours.isdigit()
        and minutes.isdigit()
        and 0 <= int(hours) < 24
        and 0 <= int(minutes) < 60
    )


class RoutineCreate(BaseModel):
    kind: RoutineKind
    message: str
    # Which baby the rule is for. Null means it follows whichever baby is active.
    baby_id: Optional[str] = None
    # after_event: what to watch for, and how long after it to nudge.
    trigger_type: Optional[str] = None
    delay_min: Optional[int] = None
    # daily: the time of day, "HH:MM" on the caregiver's clock.
    time_local: Optional[str] = None
    active: bool = True

    @model_validator(mode="after")
    def _check_shape(self) -> "RoutineCreate":
        if not self.message.strip():
            raise ValueError("A reminder needs something to say")
        if self.kind == RoutineKind.after_event:
            if not self.trigger_type:
                raise ValueError("after_event needs a trigger_type")
            if self.delay_min is None or self.delay_min < 0:
                raise ValueError("after_event needs a delay_min of 0 or more")
        elif self.kind == RoutineKind.daily:
            if not self.time_local or not _valid_hhmm(self.time_local):
                raise ValueError("daily needs a time_local as HH:MM")
        return self


class RoutineUpdate(BaseModel):
    """A change to a rule. Only the given fields move; the rest stay."""

    message: Optional[str] = None
    active: Optional[bool] = None
    trigger_type: Optional[str] = None
    delay_min: Optional[int] = None
    time_local: Optional[str] = None

    @model_validator(mode="after")
    def _check(self) -> "RoutineUpdate":
        if self.time_local is not None and not _valid_hhmm(self.time_local):
            raise ValueError("time_local must be HH:MM")
        if self.delay_min is not None and self.delay_min < 0:
            raise ValueError("delay_min must be 0 or more")
        return self


class RoutineOut(BaseModel):
    id: str
    kind: RoutineKind
    message: str
    baby_id: Optional[str] = None
    trigger_type: Optional[str] = None
    delay_min: Optional[int] = None
    time_local: Optional[str] = None
    active: bool = True
    created_at: datetime
