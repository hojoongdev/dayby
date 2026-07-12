"""Shared FastAPI dependencies.

get_current_family is the seam every route already depends on, so switching from
"the caller names its family" to "the caller proves who it is" changes nothing
above this file.
"""
from typing import Optional

from fastapi import Header, HTTPException

from .config import settings
from .db import get_db
from .tokens import ACCESS, read_token


def _bearer(authorization: Optional[str]) -> str:
    scheme, _, token = (authorization or "").partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="Sign in to continue")
    return token


async def get_current_user(authorization: Optional[str] = Header(None)) -> dict:
    user = await get_db().users.find_one({"_id": read_token(_bearer(authorization), ACCESS)})
    if user is None:
        raise HTTPException(status_code=401, detail="Unknown user")
    return user


async def get_current_family(
    authorization: Optional[str] = Header(None),
    x_family_id: Optional[str] = Header(None, alias="X-Family-Id"),
) -> dict:
    """The caller's family: derived from their session, or named outright in dev."""
    if settings.auth_enabled:
        user = await get_current_user(authorization)
        family = await get_db().families.find_one({"members": user["_id"]})
        if family is None:
            raise HTTPException(
                status_code=404, detail="Create a family or join one with an invite code"
            )
        return family

    # No identity provider configured. The header names the family outright, which is
    # a bypass, not a login -- so it exists in development and nowhere else.
    if not settings.is_development:
        raise HTTPException(
            status_code=503, detail="No auth provider configured (set AUTH_PROVIDER)"
        )
    if not x_family_id:
        raise HTTPException(status_code=401, detail="Missing X-Family-Id")

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
