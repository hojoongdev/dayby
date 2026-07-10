"""Shared pytest fixtures."""
import pytest
from pymongo import MongoClient

from app.config import settings


@pytest.fixture
def clean_db():
    """Wipe collections before an integration test.

    Guarded: it refuses to run unless the target database name ends with "_test",
    so it can never wipe the real dev/prod database. Run integration tests with
    DB_NAME=dayby_test.
    """
    if not settings.db_name.endswith("_test"):
        pytest.skip("integration test requires a *_test database (set DB_NAME=..._test)")

    client = MongoClient(settings.mongodb_uri, serverSelectionTimeoutMS=3000)
    db = client[settings.db_name]
    for name in ("families", "babies", "events"):
        db[name].delete_many({})
    yield
    client.close()
