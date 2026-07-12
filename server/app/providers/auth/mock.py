"""Offline identity provider: sign in as anyone, with no keys.

Exists so the whole auth flow — sign in, session, refresh, family membership — can
be run and demoed without a Google project. It trusts the token completely, which
is why it refuses to load anywhere but development.
"""
import hashlib

from fastapi import HTTPException

from ...config import settings
from ...models.auth import AuthIdentity
from .base import AuthProvider

DEFAULT_EMAIL = "demo@dayby.app"


class MockAuthProvider(AuthProvider):
    name = "mock"

    def __init__(self) -> None:
        if not settings.is_development:
            raise RuntimeError(
                "AUTH_PROVIDER=mock signs in anyone who asks; it is development-only"
            )

    async def verify(self, token: str) -> AuthIdentity:
        email = token.strip() or DEFAULT_EMAIL
        if "@" not in email:
            raise HTTPException(status_code=401, detail="Sign in with an email address")
        # A stable subject per email, so signing in twice is the same person.
        subject = hashlib.sha256(email.encode()).hexdigest()[:24]
        return AuthIdentity(
            provider=self.name,
            subject=subject,
            email=email,
            name=email.split("@")[0],
        )
