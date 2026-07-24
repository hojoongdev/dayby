"""Run a QueryPlan the model produced, against the family's events.

The model fills in a QueryPlan; this turns it into a real MongoDB query, family-scoped.
The model never writes Mongo itself, so a question can reach the whole history with no
chance of an injected query. An aggregate collapses a large match to one number, so
"how much has she eaten in total" does not drag thousands of records into the answer.
"""
import re
from datetime import tzinfo
from typing import Any, Optional

from .db import get_db
from .models.events import QueryPlan

# The fields a "contains" word is matched against: the open text of a record, not its id.
# Includes nested paths (a vaccine name inside an array of shots), so a question can reach
# into the open schema, not just the note.
_TEXT_FIELDS = ("note", "subtype", "type", "fields.title", "fields.item",
                "fields.name", "fields.brand", "fields.location", "fields.food",
                "fields.place", "fields.store", "fields.clinic", "fields.drug",
                "fields.doctor", "fields.vaccines.name", "fields.color")
_AGG_OPS = ("sum", "avg", "min", "max")
MAX_RECORDS = 200


def _match(plan: QueryPlan, family_id: str, baby_id: Optional[str]) -> dict[str, Any]:
    query: dict[str, Any] = {"family_id": family_id}
    if baby_id:
        query["baby_id"] = baby_id
    if plan.type:
        query["type"] = plan.type
    if plan.subtype:
        query["subtype"] = plan.subtype
    if plan.since or plan.until:
        span: dict[str, Any] = {}
        if plan.since:
            span["$gte"] = plan.since
        if plan.until:
            span["$lte"] = plan.until
        query["time"] = span
    if plan.contains:
        rx = {"$regex": re.escape(plan.contains), "$options": "i"}
        query["$or"] = [{field: rx} for field in _TEXT_FIELDS]
    return query


async def run_plan(
    plan: QueryPlan, family_id: str, baby_id: Optional[str], tz: Optional[tzinfo]
) -> list[dict]:
    """The records (or the single aggregate) a question is about, ready for the answer."""
    db = get_db()
    query = _match(plan, family_id, baby_id)

    if plan.aggregate:
        agg = plan.aggregate.strip().lower()
        if agg == "count":
            return [{"aggregate": "count", "value": await db.events.count_documents(query)}]
        op, _, field = agg.partition(":")
        if op in _AGG_OPS and field:
            cursor = await db.events.aggregate([
                {"$match": query},
                {"$group": {
                    "_id": None,
                    "value": {f"${op}": f"$fields.{field}"},
                    "count": {"$sum": 1},
                }},
            ])
            rows = await cursor.to_list(length=1)
            row = rows[0] if rows else {"value": None, "count": 0}
            return [{"aggregate": agg, "field": field,
                     "value": row["value"], "count": row["count"]}]

    order = -1 if plan.sort == "desc" else 1
    limit = max(1, min(plan.limit or 50, MAX_RECORDS))
    out: list[dict] = []
    async for e in db.events.find(query).sort("time", order).limit(limit):
        t = e.get("time")
        out.append({
            "type": e.get("type"),
            "subtype": e.get("subtype"),
            "fields": e.get("fields", {}),
            "time": t.astimezone(tz).isoformat() if hasattr(t, "astimezone") else str(t),
            "note": e.get("note"),
        })
    return out
