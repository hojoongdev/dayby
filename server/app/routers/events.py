"""Event persistence and timeline. Family-scoped; a baby must belong to the family."""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, Query

from ..db import get_db
from ..deps import get_current_family, require_baby
from ..models.events import EventCreate, EventOut
from ..util import new_id, now

router = APIRouter(prefix="/events", tags=["events"])


def event_out(doc: dict) -> EventOut:
    return EventOut(
        id=doc["_id"],
        baby_id=doc["baby_id"],
        type=doc["type"],
        subtype=doc.get("subtype"),
        fields=doc.get("fields", {}),
        time=doc["time"],
        note=doc.get("note"),
        source=doc.get("source"),
        created_at=doc["created_at"],
    )


@router.post("", response_model=EventOut, status_code=201)
async def create_event(
    body: EventCreate,
    family: dict = Depends(get_current_family),
) -> EventOut:
    await require_baby(family, body.baby_id)
    doc = {
        "_id": new_id(),
        "family_id": family["_id"],
        "baby_id": body.baby_id,
        "type": body.type,
        "subtype": body.subtype,
        "fields": body.fields,
        "time": body.time or now(),
        "note": body.note,
        "source": body.source,
        "raw_text": body.raw_text,
        "created_at": now(),
    }
    await get_db().events.insert_one(doc)
    return event_out(doc)


@router.get("", response_model=list[EventOut])
async def list_events(
    family: dict = Depends(get_current_family),
    baby_id: Optional[str] = None,
    type: Optional[str] = None,
    since: Optional[datetime] = Query(None, alias="from"),
    until: Optional[datetime] = Query(None, alias="to"),
    limit: int = Query(100, ge=1, le=500),
) -> list[EventOut]:
    query: dict = {"family_id": family["_id"]}
    if baby_id:
        query["baby_id"] = baby_id
    if type:
        query["type"] = type
    if since or until:
        time_range: dict = {}
        if since:
            time_range["$gte"] = since
        if until:
            time_range["$lte"] = until
        query["time"] = time_range

    cursor = get_db().events.find(query).sort("time", -1).limit(limit)
    return [event_out(doc) async for doc in cursor]
