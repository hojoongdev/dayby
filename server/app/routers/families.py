"""Family and baby management. All baby routes are scoped to the caller's family."""
from datetime import timedelta
from typing import Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Response

from ..config import settings
from ..db import get_db
from ..deps import get_current_family, get_current_user
from ..models.auth import UserOut
from ..models.family import (
    BabyCreate,
    BabyOut,
    BabyUpdate,
    FamilyCreate,
    FamilyJoin,
    FamilyOut,
)
from ..util import as_utc, invite_code, new_id, now

router = APIRouter(tags=["families"])


def _fresh_invite() -> dict:
    """A new code and the moment it stops working. Creating a family and rotating its
    code both need exactly this."""
    return {
        "invite_code": invite_code(),
        "invite_expires_at": now() + timedelta(hours=settings.invite_ttl_hours),
    }


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
    return FamilyOut(
        id=doc["_id"],
        name=doc["name"],
        invite_code=doc["invite_code"],
        invite_expires_at=doc.get("invite_expires_at"),
    )


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
        "members": members,
        "created_at": now(),
        **_fresh_invite(),
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

    expires = family.get("invite_expires_at")
    if expires is not None and as_utc(expires) < now():
        raise HTTPException(
            status_code=410, detail="This invite code has expired. Ask for a new one."
        )

    await get_db().families.update_one(
        {"_id": family["_id"]}, {"$addToSet": {"members": user["_id"]}}
    )
    return _family_out(family)


@router.post("/families/invite/rotate", response_model=FamilyOut)
async def rotate_invite(family: dict = Depends(get_current_family)) -> FamilyOut:
    """Replace the invite code with a new one, so a code that got out stops working. Any
    member can do it; the old code is dead the moment this returns."""
    invite = _fresh_invite()
    await get_db().families.update_one({"_id": family["_id"]}, {"$set": invite})
    return _family_out({**family, **invite})


@router.get("/families/members", response_model=list[UserOut])
async def family_members(family: dict = Depends(get_current_family)) -> list[UserOut]:
    """Who else is in here. The timeline stamps each record with a user id; this is the
    only way the app can turn one into a name, and answer "did you feed her or did I?"."""
    cursor = get_db().users.find({"_id": {"$in": family.get("members", [])}})
    return [
        UserOut(id=user["_id"], email=user.get("email"), name=user.get("name"))
        async for user in cursor
    ]


@router.post("/families/leave", status_code=204)
async def leave_family(
    user: dict = Depends(get_current_user),
    family: dict = Depends(get_current_family),
) -> Response:
    """Take yourself out of the family. The last member cannot: leaving would strand the
    babies and the timeline with nobody able to reach them."""
    members = family.get("members", [])
    if len(members) <= 1:
        raise HTTPException(
            status_code=409,
            detail="You are the only member; there is no one to leave it to.",
        )
    await get_db().families.update_one(
        {"_id": family["_id"]}, {"$pull": {"members": user["_id"]}}
    )
    return Response(status_code=204)


@router.delete("/families/members/{user_id}", response_model=list[UserOut])
async def remove_member(
    user_id: str,
    family: dict = Depends(get_current_family),
) -> list[UserOut]:
    """Remove someone else from the family. Any member can; the model is a flat set of
    peers, not an owner and guests. The last member cannot be removed."""
    members = family.get("members", [])
    if user_id not in members:
        raise HTTPException(status_code=404, detail="No such member in this family")
    if len(members) <= 1:
        raise HTTPException(status_code=409, detail="A family cannot be left with no members.")

    await get_db().families.update_one(
        {"_id": family["_id"]}, {"$pull": {"members": user_id}}
    )
    remaining = [m for m in members if m != user_id]
    cursor = get_db().users.find({"_id": {"$in": remaining}})
    return [
        UserOut(id=user["_id"], email=user.get("email"), name=user.get("name"))
        async for user in cursor
    ]


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
