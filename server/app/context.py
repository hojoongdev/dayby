"""The family context every LLM call gets: who the babies are and how old they are."""
from datetime import date, datetime
from typing import Optional

from .db import get_db
from .models.events import LlmContext


def age_label(birthdate_iso: Optional[str], ref: date) -> Optional[str]:
    """"5 months old" / "2 years old", or None if the birthdate is missing or unparsable."""
    try:
        bd = date.fromisoformat(birthdate_iso)  # type: ignore[arg-type]
    except (ValueError, TypeError):
        return None
    months = (ref.year - bd.year) * 12 + (ref.month - bd.month)
    if ref.day < bd.day:
        months -= 1
    if months < 1:
        return f"{(ref - bd).days} days old"
    if months < 24:
        return f"{months} months old"
    return f"{months // 12} years old"


async def build_llm_context(
    family: dict, now_dt: datetime, lang: Optional[str] = None
) -> LlmContext:
    """Names (for "who") plus name/age/sex profiles (for age-aware answers and tips)."""
    names: list[str] = []
    profiles: list[str] = []
    ref = now_dt.date()
    async for baby in get_db().babies.find({"family_id": family["_id"]}):
        names.append(baby["name"])
        names.extend(baby.get("nicknames", []))

        details = [d for d in (age_label(baby.get("birthdate"), ref), baby.get("sex")) if d]
        profiles.append(baby["name"] + (f" ({', '.join(details)})" if details else ""))

    return LlmContext(now=now_dt, baby_names=names, baby_profiles=profiles, lang=lang)
