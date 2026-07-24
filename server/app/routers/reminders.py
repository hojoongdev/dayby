"""One-off reminders, possibly for another caregiver.

Family-scoped. There is no push server: each targeted caregiver's app picks these up
from /assistant/tips and raises them as local notifications, so one arrives even with the
app closed -- provided that phone opened Dayby at least once after the reminder was set.
"""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException

from ..db import get_db
from ..deps import get_caller, get_current_family, require_baby
from ..models.events import ReminderCreate, ReminderOut
from ..util import as_utc, new_id, now

router = APIRouter(prefix="/reminders", tags=["reminders"])


def _out(doc: dict) -> ReminderOut:
    return ReminderOut(
        id=doc["_id"],
        message=doc["message"],
        at=doc["at"],
        target_caregivers=doc.get("target_caregivers", []),
        created_by=doc.get("created_by"),
        created_at=doc["created_at"],
    )


@router.post("", response_model=ReminderOut, status_code=201)
async def create_reminder(
    body: ReminderCreate,
    family: dict = Depends(get_current_family),
    caller: Optional[dict] = Depends(get_caller),
) -> ReminderOut:
    if body.baby_id:
        await require_baby(family, body.baby_id)
    message = body.message.strip()
    if not message:
        raise HTTPException(status_code=422, detail="A reminder needs something to say")
    doc = {
        "_id": new_id(),
        "family_id": family["_id"],
        "baby_id": body.baby_id,
        "message": message,
        "at": as_utc(body.at),
        # Caregiver ids this is for; empty means everyone in the family.
        "target_caregivers": body.target_caregivers,
        "created_by": caller["_id"] if caller else None,
        "created_at": now(),
    }
    await get_db().reminders.insert_one(doc)
    return _out(doc)


@router.get("", response_model=list[ReminderOut])
async def list_reminders(
    family: dict = Depends(get_current_family),
) -> list[ReminderOut]:
    cursor = get_db().reminders.find({"family_id": family["_id"]}).sort("at", 1)
    return [_out(doc) async for doc in cursor]


@router.delete("/{reminder_id}", status_code=204)
async def delete_reminder(
    reminder_id: str, family: dict = Depends(get_current_family)
) -> None:
    result = await get_db().reminders.delete_one(
        {"_id": reminder_id, "family_id": family["_id"]}
    )
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Reminder not found")
