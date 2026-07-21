"""Looking forward and back: when the next few things are due, and the week's trends.

Distinct from /assistant/tips (which is about right now). Predictions are deterministic
arithmetic on the baby's own rhythm -- an estimate, never a rule -- and the trend
observations come from the same day tally the charts use, written by the model.
"""
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, Query

from ..context import build_llm_context
from ..db import get_db
from ..deps import get_current_family, require_baby
from ..models.events import Insights, Prediction
from ..providers import get_llm_provider
from ..util import as_utc
from .stats import collect

router = APIRouter(prefix="/insights", tags=["insights"])

# How far back to read a rhythm, and how many of an event it takes to trust one.
LOOKBACK_DAYS = 4
MIN_SAMPLES = 3

# What is worth predicting a next-time for: the things that happen on a rhythm.
PREDICTABLE = ("feeding", "diaper")


def _basis(minutes: float) -> str:
    hours, mins = divmod(round(minutes), 60)
    if hours and mins:
        return f"usually about every {hours}h {mins}m"
    if hours:
        return f"usually about every {hours}h"
    return f"usually about every {mins}m"


async def _predict(
    family_id: str, baby_id: str, type_: str, now_dt: datetime
) -> Optional[Prediction]:
    """The next one of `type_`, from the median gap between the recent ones.

    Median, not mean, so the one long overnight gap does not drag every daytime
    estimate late.
    """
    cursor = (
        get_db().events
        .find({
            "family_id": family_id,
            "baby_id": baby_id,
            "type": type_,
            "time": {"$gte": now_dt - timedelta(days=LOOKBACK_DAYS), "$lte": now_dt},
        })
        .sort("time", 1)
    )
    times = [as_utc(doc["time"]) async for doc in cursor]
    if len(times) < MIN_SAMPLES:
        return None

    gaps = sorted(
        (times[i] - times[i - 1]).total_seconds() / 60 for i in range(1, len(times))
    )
    median = gaps[len(gaps) // 2]
    # If more than two typical gaps have passed with nothing logged, the rhythm is broken
    # (or just went unlogged), and a "next" time computed from it would be fiction.
    if now_dt - times[-1] > timedelta(minutes=2 * median):
        return None
    return Prediction(
        type=type_, at=times[-1] + timedelta(minutes=median), basis=_basis(median)
    )


@router.get("", response_model=Insights)
async def insights(
    baby_id: str,
    family: dict = Depends(get_current_family),
    lang: Optional[str] = None,
    at: datetime = Query(..., alias="now"),
) -> Insights:
    """The next few things due, and the week's trends. `now` carries the caller's offset."""
    await require_baby(family, baby_id)

    predictions = [
        p for type_ in PREDICTABLE
        if (p := await _predict(family["_id"], baby_id, type_, at)) is not None
    ]

    week = await collect(family["_id"], baby_id, 7, at)
    ctx = await build_llm_context(family, at, lang)
    observations = await get_llm_provider().write_insights(week.days, ctx)

    return Insights(predictions=predictions, observations=observations, lang=lang or "en")
