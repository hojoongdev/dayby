"""Family and baby management. All baby routes are scoped to the caller's family."""
from fastapi import APIRouter, Depends

from ..db import get_db
from ..deps import get_current_family
from ..models.family import BabyCreate, BabyOut, FamilyCreate, FamilyOut
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


@router.post("/families", response_model=FamilyOut, status_code=201)
async def create_family(body: FamilyCreate) -> FamilyOut:
    doc = {
        "_id": new_id(),
        "name": body.name,
        "invite_code": invite_code(),
        "created_at": now(),
    }
    await get_db().families.insert_one(doc)
    return FamilyOut(id=doc["_id"], name=doc["name"], invite_code=doc["invite_code"])


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
