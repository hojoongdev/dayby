"""Family and baby management. All baby routes are scoped to the caller's family."""
from typing import Optional

from fastapi import APIRouter, Depends, Header, HTTPException

from ..config import settings
from ..db import get_db
from ..deps import get_current_family, get_current_user
from ..models.family import (
    BabyCreate,
    BabyOut,
    BabyUpdate,
    FamilyCreate,
    FamilyJoin,
    FamilyOut,
)
from ..util import invite_code, new_id, now

router = APIRouter(tags=["families"])


def _baby_out(doc: dict) -> BabyOut:
    return BabyOut(
        id=doc["_id"],
        family_id=doc["family_id"],
        name=doc["name"],
        nicknames=doc.get("nicknames", []),
        birthdate=doc.get("birthdate"),
        sex=doc.get("sex"),
    )


def _family_out(doc: dict) -> FamilyOut:
    return FamilyOut(id=doc["_id"], name=doc["name"], invite_code=doc["invite_code"])


@router.post("/families", response_model=FamilyOut, status_code=201)
async def create_family(
    body: FamilyCreate,
    authorization: Optional[str] = Header(None),
) -> FamilyOut:
    """Start a family. Whoever creates it is its first member."""
    members: list[str] = []
    if settings.auth_enabled:
        user_id = (await get_current_user(authorization))["_id"]
        # A person belongs to one family, and that is the one every request
        # resolves to. A second one would simply be unreachable.
        if await get_db().families.find_one({"members": user_id}, {"_id": 1}):
            raise HTTPException(status_code=409, detail="You are already in a family")
        members = [user_id]

    doc = {
        "_id": new_id(),
        "name": body.name,
        "invite_code": invite_code(),
        "members": members,
        "created_at": now(),
    }
    await get_db().families.insert_one(doc)
    return _family_out(doc)


@router.post("/families/join", response_model=FamilyOut)
async def join_family(
    body: FamilyJoin,
    user: dict = Depends(get_current_user),
) -> FamilyOut:
    """The other half of the invite code the app has been showing all along."""
    family = await get_db().families.find_one({"invite_code": body.invite_code.strip()})
    if family is None:
        raise HTTPException(status_code=404, detail="No family with that invite code")

    await get_db().families.update_one(
        {"_id": family["_id"]}, {"$addToSet": {"members": user["_id"]}}
    )
    return _family_out(family)


@router.post("/babies", response_model=BabyOut, status_code=201)
async def add_baby(body: BabyCreate, family: dict = Depends(get_current_family)) -> BabyOut:
    doc = {
        "_id": new_id(),
        "family_id": family["_id"],
        "name": body.name,
        "nicknames": body.nicknames,
        "birthdate": body.birthdate.isoformat() if body.birthdate else None,
        "sex": body.sex,
        "created_at": now(),
    }
    await get_db().babies.insert_one(doc)
    return _baby_out(doc)


@router.get("/babies", response_model=list[BabyOut])
async def list_babies(family: dict = Depends(get_current_family)) -> list[BabyOut]:
    return [_baby_out(doc) async for doc in get_db().babies.find({"family_id": family["_id"]})]


@router.patch("/babies/{baby_id}", response_model=BabyOut)
async def update_baby(
    baby_id: str,
    body: BabyUpdate,
    family: dict = Depends(get_current_family),
) -> BabyOut:
    baby = await get_db().babies.find_one({"_id": baby_id, "family_id": family["_id"]})
    if baby is None:
        raise HTTPException(status_code=404, detail="Baby not found in this family")

    updates: dict = {}
    if body.name is not None:
        updates["name"] = body.name
    if body.nicknames is not None:
        updates["nicknames"] = body.nicknames
    if body.birthdate is not None:
        updates["birthdate"] = body.birthdate.isoformat()
    if body.sex is not None:
        updates["sex"] = body.sex

    if updates:
        await get_db().babies.update_one({"_id": baby_id}, {"$set": updates})
        baby.update(updates)
    return _baby_out(baby)
