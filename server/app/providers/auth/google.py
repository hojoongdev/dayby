"""Google Sign-In: verify the ID token the app got from Google.

Verification (signature, expiry, issuer, and that the token was minted for *this*
app) is google-auth's job — it is already installed as a dependency of google-genai.
"""
import asyncio
import logging

from fastapi import HTTPException
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token

from ...config import settings
from ...models.auth import AuthIdentity
from .base import AuthProvider

logger = logging.getLogger("dayby.auth")


class GoogleAuthProvider(AuthProvider):
    name = "google"

    def __init__(self) -> None:
        if not settings.google_client_id:
            raise RuntimeError(
                "GOOGLE_CLIENT_ID is not set (required for AUTH_PROVIDER=google)"
            )
        self._request = google_requests.Request()

    async def verify(self, token: str) -> AuthIdentity:
        try:
            # Blocking (it fetches and caches Google's public keys), so keep it off
            # the event loop.
            claims = await asyncio.to_thread(
                google_id_token.verify_oauth2_token,
                token,
                self._request,
                settings.google_client_id,
            )
        except ValueError as error:
            # Wrong audience, expired, bad signature — all of them are just "no".
            logger.warning("Rejected a Google ID token: %s", error)
            raise HTTPException(status_code=401, detail="Invalid Google token") from error

        return AuthIdentity(
            provider=self.name,
            subject=claims["sub"],
            email=claims.get("email"),
            name=claims.get("name"),
        )
