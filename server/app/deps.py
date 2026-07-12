"""Shared FastAPI dependencies."""
from fastapi import Header, HTTPException

from .db import get_db


async def get_current_family(x_family_id: str = Header(..., alias="X-Family-Id")) -> dict:
    """Resolve the caller's family.

    For now the family id comes from the X-Family-Id header. When auth lands (P4),
    this dependency will derive the family from the session / JWT instead — every
    route that depends on it stays unchanged.
    """
    family = await get_db().families.find_one({"_id": x_family_id})
    if family is None:
        raise HTTPException(status_code=404, detail="Unknown family")
    return family


async def require_baby(family: dict, baby_id: str) -> dict:
    """The baby, or 404 if it does not belong to this family."""
    baby = await get_db().babies.find_one({"_id": baby_id, "family_id": family["_id"]})
    if baby is None:
        raise HTTPException(status_code=404, detail="Baby not found in this family")
    return baby
