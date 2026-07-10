"""Small shared helpers."""
import secrets
from datetime import datetime, timezone
from uuid import uuid4


def now() -> datetime:
    """Current time in UTC (stored everywhere; display converts to local tz)."""
    return datetime.now(timezone.utc)


def new_id() -> str:
    return uuid4().hex


def invite_code() -> str:
    return secrets.token_hex(3)  # 6 hex characters
