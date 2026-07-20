"""MongoDB connection (async PyMongo).

The client is created lazily and reset on shutdown so it always binds to the
running event loop. This keeps it correct both under the app's lifespan and under
tests that spin up a fresh event loop per TestClient.
"""
import logging
from datetime import timezone

from gridfs.asynchronous import AsyncGridFSBucket
from pymongo import AsyncMongoClient

from .config import settings

logger = logging.getLogger("dayby.db")

_client: AsyncMongoClient | None = None

# Photos live in GridFS rather than in the event documents: a few megabytes of
# JPEG has no business inside a record we read on every timeline load.
PHOTO_BUCKET = "photos"


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


def get_photo_bucket() -> AsyncGridFSBucket:
    return AsyncGridFSBucket(get_db(), bucket_name=PHOTO_BUCKET)


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
    await _keep_deleted_events_briefly(db)
    await db.babies.create_index([("family_id", 1)])
    await db.routines.create_index([("family_id", 1)])
    await db[f"{PHOTO_BUCKET}.files"].create_index([("metadata.family_id", 1)])
    # Identity: one account per person per provider, and "which family am I in?"
    # is asked on every authenticated request.
    await db.users.create_index([("provider", 1), ("subject", 1)], unique=True)
    await db.families.create_index([("members", 1)])
    await db.families.create_index([("invite_code", 1)])


async def _keep_deleted_events_briefly(db) -> None:
    """Ask Mongo to remember what a deleted event *was*.

    A delete arrives on the change stream carrying nothing but an id — not the family it
    belonged to, and not the baby whose timeline just changed. So the other parent's phone
    could never be told about it. With pre-images on, the removed document rides along, and
    a record one parent takes back disappears from the other's screen too.

    Mongo 6.0+. On anything older the server still runs; only deletes stop syncing.
    """
    try:
        await db.command(
            {"collMod": "events", "changeStreamPreAndPostImages": {"enabled": True}}
        )
    except Exception:
        logger.warning("No change-stream pre-images: deletes will not sync live")


async def close_client() -> None:
    global _client
    if _client is not None:
        await _client.close()
        _client = None
