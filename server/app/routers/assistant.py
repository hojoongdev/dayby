"""The proactive side of Dayby: what the caregiver hears before they ask.

MongoDB does the counting, the model does the talking. Every number a tip can use
is aggregated here from the family's real logs, so a tip can be warm without being
invented.
"""
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, Query

from ..context import build_llm_context
from ..db import get_db
from ..deps import get_current_family, require_baby
from ..models.events import AssistantTips, CareSignal, UpcomingEvent
from ..providers import get_llm_provider
from ..util import now

router = APIRouter(prefix="/assistant", tags=["assistant"])

# How far ahead an appointment or a due todo is still worth mentioning.
UPCOMING_WINDOW = timedelta(days=7)


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
    """Two or three short lines for this baby, right now, in the caller's language."""
    await require_baby(family, baby_id)
    now_dt = at or now()

    ctx = await build_llm_context(family, now_dt, lang)
    signals = await care_signals(family, baby_id, now_dt)
    upcoming = await upcoming_events(family, baby_id, now_dt)

    return AssistantTips(
        tips=await get_llm_provider().proactive_tips(signals, upcoming, ctx),
        signals=signals,
        upcoming=upcoming,
        lang=lang or "en",
    )
