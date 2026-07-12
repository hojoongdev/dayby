"""Small shared helpers."""
import secrets
from datetime import datetime, timedelta, timezone
from uuid import uuid4


def now() -> datetime:
    """Current time in UTC (stored everywhere; display converts to local tz)."""
    return datetime.now(timezone.utc)


def as_utc(dt: datetime) -> datetime:
    """Everything here is UTC, so a datetime with no offset already is one."""
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def tz_offset(dt: datetime) -> str:
    """"+09:00" — the caller's offset in the form MongoDB's date operators accept.

    Aggregations that bucket by day or by hour have to do it in the caregiver's
    timezone; a 2am feed is a night feed where they live, not in UTC.
    """
    offset = dt.utcoffset() or timedelta(0)
    seconds = int(offset.total_seconds())
    sign = "-" if seconds < 0 else "+"
    seconds = abs(seconds)
    return f"{sign}{seconds // 3600:02d}:{(seconds % 3600) // 60:02d}"


def new_id() -> str:
    return uuid4().hex


def invite_code() -> str:
    return secrets.token_hex(3)  # 6 hex characters
