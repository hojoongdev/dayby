"""Family and baby schemas."""
from datetime import date
from typing import Optional

from pydantic import BaseModel, Field


class FamilyCreate(BaseModel):
    name: str


class FamilyJoin(BaseModel):
    invite_code: str


class FamilyOut(BaseModel):
    id: str
    name: str
    invite_code: str


class BabyCreate(BaseModel):
    name: str
    nicknames: list[str] = Field(default_factory=list)
    birthdate: Optional[date] = None
    sex: Optional[str] = None


class BabyUpdate(BaseModel):
    """Partial update; only the provided fields change."""

    name: Optional[str] = None
    nicknames: Optional[list[str]] = None
    birthdate: Optional[date] = None
    sex: Optional[str] = None


class BabyOut(BaseModel):
    id: str
    family_id: str
    name: str
    nicknames: list[str] = Field(default_factory=list)
    birthdate: Optional[date] = None
    sex: Optional[str] = None
