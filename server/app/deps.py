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
