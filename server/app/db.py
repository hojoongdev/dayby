"""MongoDB connection (async PyMongo)."""
from pymongo import AsyncMongoClient

from .config import settings

# serverSelectionTimeoutMS keeps health checks and startup from hanging when the
# database is unreachable (default is 30s).
client: AsyncMongoClient = AsyncMongoClient(
    settings.mongodb_uri, serverSelectionTimeoutMS=3000
)
db = client[settings.db_name]


async def ping() -> bool:
    """Return True if the database answers a ping, False otherwise."""
    try:
        await client.admin.command("ping")
        return True
    except Exception:
        return False
