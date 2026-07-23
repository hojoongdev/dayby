"""Notes between the caregivers in a family.

Small and family-scoped: "tell mum to buy diapers" leaves a note the other parent
sees, with an unread badge, whether or not they were looking at the app.
"""
from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class MessageDraft(BaseModel):
    """A message the model drafted from an utterance ("tell mum to buy diapers").

    The app confirms it and posts it, the same way a spoken reminder rule is confirmed.
    """

    # A name the caregiver used, kept for display. The message goes to the family either
    # way -- in a two-parent family that is the other parent.
    to: Optional[str] = None
    text: str


class MessageCreate(BaseModel):
    text: str


class MessageOut(BaseModel):
    id: str
    text: str
    from_user: Optional[str] = None
    from_name: Optional[str] = None
    # True when the caller sent it, so the app can put it on the right side.
    mine: bool = False
    read: bool = False
    created_at: datetime
