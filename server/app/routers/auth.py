"""Sign in, stay signed in.

The identity provider (Google, or the offline mock) proves who someone is exactly
once. Everything after that runs on Dayby's own tokens.
"""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException

from ..config import settings
from ..db import get_db
from ..deps import get_current_user
from ..models.auth import (
    AuthConfig,
    AuthIdentity,
    RefreshRequest,
    Session,
    SignInRequest,
    UserOut,
)
from ..providers.auth import get_auth_provider
from ..tokens import REFRESH, issue_access, issue_refresh, read_token
from ..util import new_id, now

router = APIRouter(prefix="/auth", tags=["auth"])


async def _upsert_user(identity: AuthIdentity) -> dict:
    """The person behind the identity, created on their first sign-in."""
    key = {"provider": identity.provider, "subject": identity.subject}
    user = await get_db().users.find_one(key)
    if user is not None:
        return user

    user = {
        "_id": new_id(),
        **key,
        "email": identity.email,
        "name": identity.name,
        "created_at": now(),
    }
    await get_db().users.insert_one(user)
    return user


async def _family_id_of(user_id: str) -> Optional[str]:
    family = await get_db().families.find_one({"members": user_id}, {"_id": 1})
    return family["_id"] if family else None


async def _session(user: dict) -> Session:
    return Session(
        access_token=issue_access(user["_id"]),
        refresh_token=issue_refresh(user["_id"]),
        user=UserOut(id=user["_id"], email=user.get("email"), name=user.get("name")),
        family_id=await _family_id_of(user["_id"]),
    )


@router.get("/config", response_model=AuthConfig)
async def auth_config() -> AuthConfig:
    """Whether to show a sign-in screen at all, and which provider it is for."""
    return AuthConfig(enabled=settings.auth_enabled, provider=settings.auth_provider)


@router.post("/signin", response_model=Session)
async def signin(body: SignInRequest) -> Session:
    if not settings.auth_enabled:
        raise HTTPException(status_code=404, detail="No auth provider configured")
    identity = await get_auth_provider().verify(body.token)
    return await _session(await _upsert_user(identity))


@router.post("/refresh", response_model=Session)
async def refresh(body: RefreshRequest) -> Session:
    """A new pair, so a signed-in parent stays signed in."""
    user = await get_db().users.find_one({"_id": read_token(body.refresh_token, REFRESH)})
    if user is None:
        raise HTTPException(status_code=401, detail="Unknown user")
    return await _session(user)


@router.get("/me", response_model=Session)
async def me(user: dict = Depends(get_current_user)) -> Session:
    return await _session(user)
