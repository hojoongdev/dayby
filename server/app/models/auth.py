"""Sign-in schemas."""
from typing import Optional

from pydantic import BaseModel


class AuthIdentity(BaseModel):
    """Who the identity provider says this is."""

    provider: str
    # The provider's stable id for this person. Unique with `provider`; an email is
    # not, because people change theirs.
    subject: str
    email: Optional[str] = None
    name: Optional[str] = None


class SignInRequest(BaseModel):
    # The provider's ID token. For the mock provider: whatever email you claim.
    token: str


class RefreshRequest(BaseModel):
    refresh_token: str


class UserOut(BaseModel):
    id: str
    email: Optional[str] = None
    name: Optional[str] = None


class Session(BaseModel):
    access_token: str
    refresh_token: str
    user: UserOut
    # Null until the user creates a family or joins one with an invite code.
    family_id: Optional[str] = None


class AuthConfig(BaseModel):
    """What the app needs to know before it can show a sign-in screen."""

    enabled: bool
    provider: str
