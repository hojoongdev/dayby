"""MongoDB connection (async PyMongo).

The client is created lazily and reset on shutdown so it always binds to the
running event loop. This keeps it correct both under the app's lifespan and under
tests that spin up a fresh event loop per TestClient.
"""
from datetime import timezone

from pymongo import AsyncMongoClient

from .config import settings

_client: AsyncMongoClient | None = None


def get_client() -> AsyncMongoClient:
    global _client
    if _client is None:
        # serverSelectionTimeoutMS keeps health checks and startup from hanging
        # when the database is unreachable (default is 30s). tz_aware makes reads
        # return timezone-aware UTC datetimes, so the API always serializes times
        # with an offset (clients store UTC, display local).
        _client = AsyncMongoClient(
            settings.mongodb_uri,
            serverSelectionTimeoutMS=3000,
            tz_aware=True,
            tzinfo=timezone.utc,
        )
    return _client


def get_db():
    return get_client()[settings.db_name]


async def ping() -> bool:
    """Return True if the database answers a ping, False otherwise."""
    try:
        await get_client().admin.command("ping")
        return True
    except Exception:
        return False


async def ensure_indexes() -> None:
    """Create indexes for the timeline and family-scoped lookups (idempotent)."""
    db = get_db()
    await db.events.create_index([("family_id", 1), ("baby_id", 1), ("time", -1)])
    await db.babies.create_index([("family_id", 1)])


async def close_client() -> None:
    global _client
    if _client is not None:
        await _client.close()
        _client = None
