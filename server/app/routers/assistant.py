"""The proactive side of Dayby: what the caregiver hears before they ask.

MongoDB does the counting, the model does the talking. Every number a tip can use
is aggregated here from the family's real logs, so a tip can be warm without being
invented.
"""
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, Query

from ..care import OVERDUE_AFTER
from ..context import build_llm_context
from ..db import get_db
from ..deps import get_current_family, require_baby
from ..models.events import (
    AssistantTips,
    CareSignal,
    ScheduledReminder,
    UpcomingEvent,
)
from ..providers import get_llm_provider
from ..util import as_utc, now

router = APIRouter(prefix="/assistant", tags=["assistant"])

# How far ahead an appointment or a due todo is still worth mentioning.
UPCOMING_WINDOW = timedelta(days=7)

# Do not wake anyone for something a few minutes away; they are still holding the baby.
REMINDER_FLOOR = timedelta(minutes=20)

# A rule cannot schedule the whole month; keep the phone's queue short.
MAX_SCHEDULED = 10


async def routine_reminders(
    family: dict, baby_id: str, signals: list[CareSignal], now_dt: datetime
) -> list[ScheduledReminder]:
    """The family's own rules, turned into the next moment each one fires.

    An after-event rule fires from the last event of its type; a daily rule fires at
    its next occurrence on the caregiver's clock. now_dt carries their offset, so a
    daily time is read on their clock, not UTC's.
    """
    last_seen = {s.type: s.last_time for s in signals if s.last_time}
    cursor = get_db().routines.find({
        "family_id": family["_id"],
        "active": True,
        "$or": [{"baby_id": baby_id}, {"baby_id": None}],
    })

    out: list[ScheduledReminder] = []
    async for rule in cursor:
        text = rule.get("message", "").strip()
        if not text:
            continue

        if rule["kind"] == "after_event":
            last = last_seen.get(rule.get("trigger_type"))
            if last is None:
                continue  # nothing of that kind has happened yet to fire after
            fires_at = as_utc(last) + timedelta(minutes=rule.get("delay_min") or 0)
            if fires_at > now_dt:
                out.append(ScheduledReminder(at=fires_at, text=text))

        elif rule["kind"] == "daily":
            hours, _, minutes = rule.get("time_local", "").partition(":")
            fires_at = now_dt.replace(
                hour=int(hours), minute=int(minutes), second=0, microsecond=0
            )
            if fires_at <= now_dt:
                fires_at += timedelta(days=1)
            out.append(ScheduledReminder(at=fires_at, text=text))

    return out


def next_reminder(
    signals: list[CareSignal], now_dt: datetime
) -> tuple[Optional[datetime], Optional[str]]:
    """The next moment something goes overdue, and which thing it is.

    Deterministic arithmetic on real last-seen times — the model is only ever asked
    to write the sentence, never to decide when the phone should buzz.
    """
    due: list[tuple[datetime, str]] = []
    for signal in signals:
        gap = OVERDUE_AFTER.get(signal.type)
        # A sleep in progress is not a sleep that is late.
        if gap is None or signal.last_time is None:
            continue
        if signal.type == "sleep" and signal.last_subtype == "start":
            continue
        due.append((signal.last_time + gap, signal.type))

    ahead = [(at, topic) for at, topic in due if at >= now_dt + REMINDER_FLOOR]
    if not ahead:
        return None, None
    return min(ahead)


async def care_signals(
    family: dict, baby_id: str, now_dt: datetime
) -> list[CareSignal]:
    """Per event type: when it last happened, how often today, how often ever.

    One pass over the baby's history. "Today" means the caller's local day —
    now_dt carries their UTC offset, so local midnight is just a replace().
    """
    day_start = now_dt.replace(hour=0, minute=0, second=0, microsecond=0)
    pipeline = [
        {"$match": {
            "family_id": family["_id"],
            "baby_id": baby_id,
            "time": {"$lte": now_dt},
        }},
        {"$group": {
            "_id": "$type",
            "last_time": {"$max": "$time"},
            "last_subtype": {"$top": {"sortBy": {"time": -1}, "output": "$subtype"}},
            "count_today": {"$sum": {"$cond": [{"$gte": ["$time", day_start]}, 1, 0]}},
            "total": {"$sum": 1},
        }},
        {"$sort": {"last_time": -1}},
    ]
    signals: list[CareSignal] = []
    async for row in await get_db().events.aggregate(pipeline):
        last = row["last_time"]
        signals.append(CareSignal(
            type=row["_id"],
            last_time=last,
            last_subtype=row.get("last_subtype"),
            hours_since=round((now_dt - last).total_seconds() / 3600, 1),
            count_today=row["count_today"],
            total=row["total"],
        ))
    return signals


async def upcoming_events(
    family: dict, baby_id: str, now_dt: datetime
) -> list[UpcomingEvent]:
    """Anything already logged whose time is still ahead: appointments, due todos."""
    cursor = (
        get_db().events
        .find({
            "family_id": family["_id"],
            "baby_id": baby_id,
            "time": {"$gt": now_dt, "$lte": now_dt + UPCOMING_WINDOW},
        })
        .sort("time", 1)
        .limit(10)
    )
    out: list[UpcomingEvent] = []
    async for doc in cursor:
        fields = doc.get("fields") or {}
        out.append(UpcomingEvent(
            type=doc["type"],
            time=doc["time"],
            hours_until=round((doc["time"] - now_dt).total_seconds() / 3600, 1),
            label=fields.get("title") or fields.get("item") or doc.get("note"),
        ))
    return out


@router.get("/tips", response_model=AssistantTips)
async def tips(
    baby_id: str,
    family: dict = Depends(get_current_family),
    lang: Optional[str] = None,
    at: Optional[datetime] = Query(None, alias="now"),
) -> AssistantTips:
    """Two or three short lines for this baby, right now, in the caller's language —
    plus the one to send later, when they have stopped looking at the app."""
    await require_baby(family, baby_id)
    now_dt = at or now()

    ctx = await build_llm_context(family, now_dt, lang)
    signals = await care_signals(family, baby_id, now_dt)
    upcoming = await upcoming_events(family, baby_id, now_dt)
    remind_at, remind_topic = next_reminder(signals, now_dt)

    written = await get_llm_provider().proactive_tips(
        signals, upcoming, ctx, remind_at=remind_at, remind_topic=remind_topic
    )
    reminder = next((t.text for t in written if t.kind == "reminder"), None)

    # The overdue-gap nudge and the family's own rules go to the phone together.
    scheduled: list[ScheduledReminder] = []
    if remind_at and reminder:
        scheduled.append(ScheduledReminder(at=remind_at, text=reminder))
    scheduled.extend(await routine_reminders(family, baby_id, signals, now_dt))
    scheduled.sort(key=lambda r: r.at)
    scheduled = scheduled[:MAX_SCHEDULED]

    return AssistantTips(
        tips=[t for t in written if t.kind != "reminder"],
        signals=signals,
        upcoming=upcoming,
        scheduled=scheduled,
        remind_at=scheduled[0].at if scheduled else None,
        reminder=scheduled[0].text if scheduled else None,
        lang=lang or "en",
    )
