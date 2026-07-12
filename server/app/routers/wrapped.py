"""The keepsake: a whole babyhood, counted once and told back.

Every number here comes out of a single $facet pass over the baby's events --
twelve different questions of the same collection scan -- and the model is then
allowed to write the story from those numbers and nothing else.
"""
from datetime import datetime
from typing import Any, Optional

from fastapi import APIRouter, Depends, Query

from ..context import build_llm_context
from ..db import get_db
from ..deps import get_current_family, require_baby
from ..models.events import Milestone, Spend, Wrapped, WrappedStats
from ..providers import get_llm_provider
from ..util import now, tz_offset

router = APIRouter(prefix="/wrapped", tags=["wrapped"])

# A feed before this hour, in the caregiver's own timezone, is a night feed.
NIGHT_ENDS_AT = 5


def _pipeline(family_id: str, baby_id: str, tz: str) -> list[dict[str, Any]]:
    return [
        {"$match": {"family_id": family_id, "baby_id": baby_id}},
        {"$facet": {
            "totals": [{"$group": {
                "_id": None,
                "events": {"$sum": 1},
                "first": {"$min": "$time"},
                "last": {"$max": "$time"},
            }}],
            "by_type": [
                {"$group": {"_id": "$type", "count": {"$sum": 1}}},
                {"$sort": {"count": -1}},
                {"$limit": 8},
            ],
            "feeding": [
                {"$match": {"type": "feeding"}},
                {"$group": {
                    "_id": None,
                    "count": {"$sum": 1},
                    "total_ml": {"$sum": {"$ifNull": ["$fields.amount_ml", 0]}},
                }},
            ],
            "night_feeds": [
                {"$match": {"type": "feeding"}},
                {"$set": {"hour": {"$hour": {"date": "$time", "timezone": tz}}}},
                {"$match": {"hour": {"$lt": NIGHT_ENDS_AT}}},
                {"$count": "count"},
            ],
            "diapers": [{"$match": {"type": "diaper"}}, {"$count": "count"}],
            "sleeps": [{"$match": {"type": "sleep"}}, {"$count": "count"}],
            "busiest_day": [
                {"$group": {
                    "_id": {"$dateToString": {
                        "format": "%Y-%m-%d", "date": "$time", "timezone": tz,
                    }},
                    "count": {"$sum": 1},
                }},
                {"$sort": {"count": -1, "_id": 1}},
                {"$limit": 1},
            ],
            "spend": [
                {"$match": {"type": "purchase"}},
                {"$group": {
                    "_id": {"$ifNull": ["$fields.currency", "?"]},
                    "total": {"$sum": {"$ifNull": ["$fields.amount", 0]}},
                    "count": {"$sum": 1},
                }},
                {"$sort": {"total": -1}},
            ],
            "milestones": [
                {"$match": {"type": "milestone"}},
                {"$sort": {"time": 1}},
                {"$limit": 20},
                {"$project": {
                    "_id": 0,
                    "time": 1,
                    "text": {"$ifNull": ["$note", "$fields.title"]},
                }},
            ],
            "growth": [
                {"$match": {"type": "growth"}},
                {"$sort": {"time": 1}},
                {"$group": {
                    "_id": None,
                    "first_weight_kg": {"$first": "$fields.weight_kg"},
                    "last_weight_kg": {"$last": "$fields.weight_kg"},
                    "first_height_cm": {"$first": "$fields.height_cm"},
                    "last_height_cm": {"$last": "$fields.height_cm"},
                }},
            ],
        }},
    ]


def _one(rows: list[dict], key: str, default: Any = None) -> Any:
    """The single document a $facet branch produces, or a default when it is empty."""
    return rows[0].get(key, default) if rows else default


async def collect(family_id: str, baby_id: str, now_dt: datetime) -> WrappedStats:
    cursor = await get_db().events.aggregate(
        _pipeline(family_id, baby_id, tz_offset(now_dt))
    )
    facets = (await cursor.to_list(length=1))[0]

    totals = facets["totals"]
    first_log = _one(totals, "first")
    last_log = _one(totals, "last")

    growth = facets["growth"]
    busiest = facets["busiest_day"]

    return WrappedStats(
        days_tracked=(last_log - first_log).days + 1 if first_log and last_log else 0,
        total_events=_one(totals, "events", 0),
        first_log=first_log,
        last_log=last_log,
        feedings=_one(facets["feeding"], "count", 0),
        total_feed_ml=_one(facets["feeding"], "total_ml", 0),
        night_feeds=_one(facets["night_feeds"], "count", 0),
        diapers=_one(facets["diapers"], "count", 0),
        sleeps=_one(facets["sleeps"], "count", 0),
        busiest_day=_one(busiest, "_id"),
        busiest_day_events=_one(busiest, "count", 0),
        top_types={row["_id"]: row["count"] for row in facets["by_type"]},
        spend=[
            Spend(currency=row["_id"], total=row["total"], count=row["count"])
            for row in facets["spend"]
        ],
        milestones=[Milestone(**row) for row in facets["milestones"]],
        first_weight_kg=_one(growth, "first_weight_kg"),
        last_weight_kg=_one(growth, "last_weight_kg"),
        first_height_cm=_one(growth, "first_height_cm"),
        last_height_cm=_one(growth, "last_height_cm"),
    )


@router.get("", response_model=Wrapped)
async def wrapped(
    baby_id: str,
    family: dict = Depends(get_current_family),
    lang: Optional[str] = None,
    at: Optional[datetime] = Query(None, alias="now"),
) -> Wrapped:
    await require_baby(family, baby_id)
    now_dt = at or now()

    stats = await collect(family["_id"], baby_id, now_dt)
    ctx = await build_llm_context(family, now_dt, lang)

    return Wrapped(
        stats=stats,
        story=await get_llm_provider().write_wrapped(stats, ctx),
        lang=lang or "en",
    )
