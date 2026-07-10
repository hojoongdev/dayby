"""Dayby API entrypoint."""
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from .config import settings
from .db import close_client, ping
from .routers import families, ingest

logger = logging.getLogger("dayby")


@asynccontextmanager
async def lifespan(app: FastAPI):
    if await ping():
        logger.info("Connected to MongoDB.")
    else:
        logger.warning("MongoDB not reachable yet; check MONGODB_URI.")
    yield
    await close_client()


app = FastAPI(title="Dayby API", version="0.1.0", lifespan=lifespan)
app.include_router(families.router)
app.include_router(ingest.router)


@app.get("/")
async def root():
    return {"name": "Dayby API", "status": "ok", "env": settings.app_env}


@app.get("/health")
async def health():
    """Liveness plus MongoDB connectivity."""
    return {"status": "ok", "mongo": await ping()}
