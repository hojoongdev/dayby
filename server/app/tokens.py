"""Dayby's own session tokens.

The identity provider proves who you are, once. After that the app carries our
tokens, not Google's: a short-lived access token, and a long-lived refresh token so
a parent is never signed out at 3am with a crying baby in one arm.
"""
from datetime import timedelta

import jwt
from fastapi import HTTPException

from .config import settings
from .util import now

ALGORITHM = "HS256"
ACCESS = "access"
REFRESH = "refresh"


def _issue(user_id: str, kind: str, lifetime: timedelta) -> str:
    return jwt.encode(
        {"sub": user_id, "typ": kind, "iat": now(), "exp": now() + lifetime},
        settings.jwt_secret,
        algorithm=ALGORITHM,
    )


def issue_access(user_id: str) -> str:
    return _issue(user_id, ACCESS, timedelta(minutes=settings.access_token_ttl_minutes))


def issue_refresh(user_id: str) -> str:
    return _issue(user_id, REFRESH, timedelta(days=settings.refresh_token_ttl_days))


def read_token(token: str, expected: str) -> str:
    """The user id inside a valid token of the expected kind, or 401."""
    try:
        claims = jwt.decode(token, settings.jwt_secret, algorithms=[ALGORITHM])
    except jwt.PyJWTError as error:
        raise HTTPException(status_code=401, detail="Invalid or expired token") from error

    # A refresh token lives for months; it must never be usable as an access token.
    if claims.get("typ") != expected:
        raise HTTPException(status_code=401, detail="Wrong kind of token")
    return claims["sub"]
