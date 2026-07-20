"""Reminder rules a family defines for itself. Family-scoped, like everything else.

The rules live here; turning them into an actual scheduled nudge is the assistant's
job (it already computes the next thing the phone should say). This router is only the
list a caregiver edits.
"""
from fastapi import APIRouter, Depends, HTTPException

from ..db import get_db
from ..deps import get_current_family, require_baby
from ..models.routine import RoutineCreate, RoutineOut, RoutineUpdate
from ..util import new_id, now

router = APIRouter(prefix="/routines", tags=["routines"])


def _out(doc: dict) -> RoutineOut:
    return RoutineOut(
        id=doc["_id"],
        kind=doc["kind"],
        message=doc["message"],
        baby_id=doc.get("baby_id"),
        trigger_type=doc.get("trigger_type"),
        delay_min=doc.get("delay_min"),
        time_local=doc.get("time_local"),
        active=doc.get("active", True),
        created_at=doc["created_at"],
    )


@router.post("", response_model=RoutineOut, status_code=201)
async def create_routine(
    body: RoutineCreate,
    family: dict = Depends(get_current_family),
) -> RoutineOut:
    if body.baby_id:
        await require_baby(family, body.baby_id)
    doc = {
        "_id": new_id(),
        "family_id": family["_id"],
        "kind": body.kind.value,
        "message": body.message.strip(),
        "baby_id": body.baby_id,
        "trigger_type": body.trigger_type,
        "delay_min": body.delay_min,
        "time_local": body.time_local,
        "active": body.active,
        "created_at": now(),
    }
    await get_db().routines.insert_one(doc)
    return _out(doc)


@router.get("", response_model=list[RoutineOut])
async def list_routines(family: dict = Depends(get_current_family)) -> list[RoutineOut]:
    cursor = get_db().routines.find({"family_id": family["_id"]}).sort("created_at", 1)
    return [_out(doc) async for doc in cursor]


@router.patch("/{routine_id}", response_model=RoutineOut)
async def update_routine(
    routine_id: str,
    body: RoutineUpdate,
    family: dict = Depends(get_current_family),
) -> RoutineOut:
    db = get_db()
    doc = await db.routines.find_one({"_id": routine_id, "family_id": family["_id"]})
    if doc is None:
        raise HTTPException(status_code=404, detail="Reminder not found")

    updates = body.model_dump(exclude_unset=True)
    if "message" in updates:
        message = (updates["message"] or "").strip()
        if not message:
            raise HTTPException(status_code=422, detail="A reminder needs something to say")
        updates["message"] = message
    if updates:
        await db.routines.update_one({"_id": routine_id}, {"$set": updates})
        doc.update(updates)
    return _out(doc)


@router.delete("/{routine_id}", status_code=204)
async def delete_routine(
    routine_id: str,
    family: dict = Depends(get_current_family),
) -> None:
    result = await get_db().routines.delete_one(
        {"_id": routine_id, "family_id": family["_id"]}
    )
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Reminder not found")
