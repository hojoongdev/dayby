"""Identity provider interface."""
from abc import ABC, abstractmethod

from ...models.auth import AuthIdentity


class AuthProvider(ABC):
    """Turns a provider's ID token into the person it belongs to."""

    name: str = "base"

    @abstractmethod
    async def verify(self, token: str) -> AuthIdentity:
        """The verified identity, or 401. Never trust the token's contents unchecked."""
        ...
