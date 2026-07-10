"""MongoDB connection (async PyMongo).

The client is created lazily and reset on shutdown so it always binds to the
running event loop. This keeps it correct both under the app's lifespan and under
tests that spin up a fresh event loop per TestClient.
"""
from pymongo import AsyncMongoClient

from .config import settings

_client: AsyncMongoClient | None = None


def get_client() -> AsyncMongoClient:
    global _client
    if _client is None:
        # serverSelectionTimeoutMS keeps health checks and startup from hanging
        # when the database is unreachable (default is 30s).
        _client = AsyncMongoClient(settings.mongodb_uri, serverSelectionTimeoutMS=3000)
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


async def close_client() -> None:
    global _client
    if _client is not None:
        await _client.close()
        _client = None
