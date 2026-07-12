"""Auth provider factory. Swap implementations via AUTH_PROVIDER."""
from ...config import settings
from .base import AuthProvider
from .mock import MockAuthProvider


def get_auth_provider() -> AuthProvider:
    name = settings.auth_provider
    if name == "mock":
        return MockAuthProvider()
    if name == "google":
        # Lazy import so google-auth is only touched when actually used.
        from .google import GoogleAuthProvider

        return GoogleAuthProvider()
    raise ValueError(f"Unknown AUTH_PROVIDER: {name!r}")
