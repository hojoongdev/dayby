"""Family and baby schemas."""
from datetime import date
from typing import Optional

from pydantic import BaseModel, Field


class FamilyCreate(BaseModel):
    name: str


class FamilyOut(BaseModel):
    id: str
    name: str
    invite_code: str


class BabyCreate(BaseModel):
    name: str
    nicknames: list[str] = Field(default_factory=list)
    birthdate: Optional[date] = None
    sex: Optional[str] = None


class BabyOut(BaseModel):
    id: str
    family_id: str
    name: str
    nicknames: list[str] = Field(default_factory=list)
    birthdate: Optional[date] = None
    sex: Optional[str] = None
