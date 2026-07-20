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
    SignUpRequest,
    UserOut,
)
from ..passwords import hash_password, verify_password
from ..providers.auth import get_auth_provider
from ..tokens import REFRESH, issue_access, issue_refresh, read_token
from ..util import new_id, now

router = APIRouter(prefix="/auth", tags=["auth"])

# Local email+password accounts. Unlike mock and google there is no external token to
# verify -- the credential lives here, so signin and signup are handled inline rather
# than through an AuthProvider.
PASSWORD = "password"
MIN_PASSWORD_LENGTH = 8


def _clean_email(email: Optional[str]) -> str:
    email = (email or "").strip().lower()
    if "@" not in email or email.startswith("@") or email.endswith("@"):
        raise HTTPException(status_code=422, detail="Enter a valid email address")
    return email


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


@router.post("/signup", response_model=Session, status_code=201)
async def signup(body: SignUpRequest) -> Session:
    """Make a local account. The other half of it is signin below; a second parent
    makes one of these, then joins the family with the invite code."""
    if settings.auth_provider != PASSWORD:
        raise HTTPException(status_code=404, detail="This server does not use passwords")
    email = _clean_email(body.email)
    if len(body.password) < MIN_PASSWORD_LENGTH:
        raise HTTPException(
            status_code=422,
            detail=f"Password must be at least {MIN_PASSWORD_LENGTH} characters",
        )
    # Local accounts key on the email: it is the subject, so the unique (provider,
    # subject) index is what stops a second account on the same address.
    if await get_db().users.find_one({"provider": PASSWORD, "subject": email}, {"_id": 1}):
        raise HTTPException(status_code=409, detail="An account with that email exists")

    user = {
        "_id": new_id(),
        "provider": PASSWORD,
        "subject": email,
        "email": email,
        "name": (body.name or "").strip() or email.split("@")[0],
        "password_hash": hash_password(body.password),
        "created_at": now(),
    }
    await get_db().users.insert_one(user)
    return await _session(user)


@router.post("/signin", response_model=Session)
async def signin(body: SignInRequest) -> Session:
    if not settings.auth_enabled:
        raise HTTPException(status_code=404, detail="No auth provider configured")

    if settings.auth_provider == PASSWORD:
        email = _clean_email(body.email)
        user = await get_db().users.find_one({"provider": PASSWORD, "subject": email})
        # One message for a missing account and a wrong password, so neither can be
        # used to find out which emails have an account.
        if user is None or not verify_password(body.password or "", user.get("password_hash", "")):
            raise HTTPException(status_code=401, detail="Wrong email or password")
        return await _session(user)

    if not body.token:
        raise HTTPException(status_code=422, detail="Missing token")
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
