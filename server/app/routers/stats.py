"""The numbers behind the charts (spec 9.1).

One $facet pass, like the keepsake: several different questions of the same collection
scan. The spec asked for a `daily_summaries` collection kept current on every write. At the
size of one family that is a cache with an invalidation problem and no cache miss to solve
— and a correction to a feed logged last Tuesday would have to find and fix its summary
too. The numbers are counted when they are asked for instead.

Every day here is the caregiver's day. Bucketing by UTC would put a 9pm feed in tomorrow
for half the world, and the whole point of a daily chart is that it lines up with the days
you actually had.
"""
from collections import defaultdict
from datetime import datetime, timedelta
from typing import Any

from fastapi import APIRouter, Depends, Query

from ..db import get_db
from ..deps import get_current_family, require_baby
from ..models.events import DayStat, GrowthPoint, RhythmBlock, Stats
from ..util import tz_offset

router = APIRouter(prefix="/stats", tags=["stats"])

MINUTES_A_DAY = 24 * 60

# A sleep that starts before this hour, or after the evening one, is the night's sleep
# rather than a nap. Split them and the chart says something; lumped together it does not.
NIGHT_STARTS_AT = 19
NIGHT_ENDS_AT = 7

# What earns a mark on the 24-hour view. Everything else would just be noise on it.
RHYTHM_TYPES = ("feeding", "sleep", "diaper")


def _local_minutes(tz: str) -> dict[str, Any]:
    """Minutes past the caregiver's own midnight."""
    return {
        "$add": [
            {"$multiply": [{"$hour": {"date": "$time", "timezone": tz}}, 60]},
            {"$minute": {"date": "$time", "timezone": tz}},
        ]
    }


def _local_date(tz: str) -> dict[str, Any]:
    return {"$dateToString": {"format": "%Y-%m-%d", "date": "$time", "timezone": tz}}


def _pipeline(family_id: str, baby_id: str, since: datetime, tz: str) -> list[dict[str, Any]]:
    return [
        {"$match": {
            "family_id": family_id,
            "baby_id": baby_id,
            "time": {"$gte": since},
        }},
        {"$set": {"day": _local_date(tz), "minute": _local_minutes(tz)}},
        {"$facet": {
            "feeds": [
                {"$match": {"type": "feeding"}},
                {"$sort": {"time": 1}},
                {"$group": {
                    "_id": "$day",
                    "count": {"$sum": 1},
                    "ml": {"$sum": {"$ifNull": ["$fields.amount_ml", 0]}},
                    # Kept so the gaps between them can be measured. A day's feeds are a
                    # handful, so this is a handful of timestamps.
                    "times": {"$push": "$time"},
                }},
            ],
            "diapers": [
                {"$match": {"type": "diaper"}},
                {"$group": {
                    "_id": {"day": "$day", "kind": {"$ifNull": ["$subtype", "other"]}},
                    "count": {"$sum": 1},
                }},
            ],
            # Only the waking-up carries the duration: it is the event that knows how long
            # the sleep it ended actually was.
            "sleeps": [
                {"$match": {"type": "sleep", "subtype": "end",
                            "fields.duration_min": {"$gt": 0}}},
                {"$set": {
                    "started": {"$subtract": [
                        "$time",
                        {"$multiply": ["$fields.duration_min", 60_000]},
                    ]},
                }},
                {"$set": {
                    "start_hour": {"$hour": {"date": "$started", "timezone": tz}},
                    "start_day": {"$dateToString": {
                        "format": "%Y-%m-%d", "date": "$started", "timezone": tz,
                    }},
                    "start_min": {"$add": [
                        {"$multiply": [{"$hour": {"date": "$started", "timezone": tz}}, 60]},
                        {"$minute": {"date": "$started", "timezone": tz}},
                    ]},
                }},
                {"$project": {
                    "_id": 0,
                    "day": "$start_day",
                    "start_min": 1,
                    "start_hour": 1,
                    "minutes": "$fields.duration_min",
                }},
            ],
            "growth": [
                {"$match": {"type": "growth"}},
                {"$sort": {"time": 1}},
                {"$project": {
                    "_id": 0,
                    "time": 1,
                    "weight_kg": "$fields.weight_kg",
                    "height_cm": "$fields.height_cm",
                }},
            ],
            "marks": [
                {"$match": {"type": {"$in": ["feeding", "diaper"]}}},
                {"$project": {"_id": 0, "day": 1, "type": 1, "start_min": "$minute"}},
            ],
        }},
    ]


def _is_night(hour: int) -> bool:
    return hour >= NIGHT_STARTS_AT or hour < NIGHT_ENDS_AT


def _shift(day: str, days: int) -> str:
    return (datetime.strptime(day, "%Y-%m-%d") + timedelta(days=days)).strftime("%Y-%m-%d")


def _night_of(day: str, start_hour: int) -> str:
    """Which day a sleep counts towards.

    A stretch that starts after midnight belongs to the night before it. Counted on the
    day it begins, a Tuesday holds the tail of Monday's night as well as all of its own,
    and reports fifteen hours. Naps never start before NIGHT_ENDS_AT, so they never move.
    """
    return _shift(day, -1) if start_hour < NIGHT_ENDS_AT else day


def _average_gap(times: list[datetime]) -> int | None:
    """How long, on average, this baby went between feeds today."""
    if len(times) < 2:
        return None
    ordered = sorted(times)
    total = (ordered[-1] - ordered[0]).total_seconds() / 60
    return round(total / (len(ordered) - 1))


def _rhythm(sleeps: list[dict], marks: list[dict]) -> list[RhythmBlock]:
    """The 24-hour view, one row per day.

    A sleep that starts at eleven at night and ends at six is not one block, it is the end
    of one day and the start of the next. Cut at midnight, or it would run off the row.
    """
    blocks: list[RhythmBlock] = []
    for sleep in sleeps:
        start, left, day = sleep["start_min"], sleep["minutes"], sleep["day"]
        while left > 0:
            tonight = min(left, MINUTES_A_DAY - start)
            blocks.append(
                RhythmBlock(date=day, type="sleep", start_min=start, minutes=tonight)
            )
            left -= tonight
            start = 0
            day = _shift(day, 1)

    blocks.extend(
        RhythmBlock(date=mark["day"], type=mark["type"], start_min=mark["start_min"])
        for mark in marks
    )
    return blocks


async def collect(family_id: str, baby_id: str, days: int, at: datetime) -> Stats:
    """The chart numbers for one baby. Shared with insights, which reads the same days
    for trends. `at` carries the caller's offset, which is what makes a "day" theirs."""
    tz = tz_offset(at)
    since = at - timedelta(days=days)
    cursor = await get_db().events.aggregate(_pipeline(family_id, baby_id, since, tz))
    facets = (await cursor.to_list(length=1))[0]

    by_day: dict[str, DayStat] = defaultdict(lambda: DayStat(date=""))
    for feed in facets["feeds"]:
        day = by_day[feed["_id"]]
        day.date = feed["_id"]
        day.feeds = feed["count"]
        day.feed_ml = feed["ml"]
        day.avg_feed_gap_min = _average_gap(feed["times"])

    for diaper in facets["diapers"]:
        day = by_day[diaper["_id"]["day"]]
        day.date = diaper["_id"]["day"]
        day.diapers[diaper["_id"]["kind"]] = diaper["count"]

    for sleep in facets["sleeps"]:
        date = _night_of(sleep["day"], sleep["start_hour"])
        day = by_day[date]
        day.date = date
        if _is_night(sleep["start_hour"]):
            day.night_sleep_min += sleep["minutes"]
        else:
            day.nap_min += sleep["minutes"]

    return Stats(
        days=sorted(by_day.values(), key=lambda d: d.date),
        growth=[GrowthPoint(**point) for point in facets["growth"]],
        rhythm=_rhythm(facets["sleeps"], facets["marks"]),
    )


@router.get("", response_model=Stats)
async def stats(
    baby_id: str,
    days: int = Query(14, ge=1, le=180),
    at: datetime = Query(..., alias="now"),
    family: dict = Depends(get_current_family),
) -> Stats:
    """Everything the charts are drawn from. `now` carries the caller's offset, which is
    what makes a "day" mean the day they had."""
    await require_baby(family, baby_id)
    return await collect(family["_id"], baby_id, days, at)
