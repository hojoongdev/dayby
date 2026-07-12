"""Dayby API entrypoint."""
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .db import close_client, ensure_indexes, ping
from .routers import assistant, events, families, ingest

logger = logging.getLogger("dayby")


@asynccontextmanager
async def lifespan(app: FastAPI):
    if await ping():
        logger.info("Connected to MongoDB.")
        await ensure_indexes()
    else:
        logger.warning("MongoDB not reachable yet; check MONGODB_URI.")
    yield
    await close_client()


app = FastAPI(title="Dayby API", version="0.1.0", lifespan=lifespan)

# Allow the Flutter web client (and any browser-based caller) to reach the API.
_cors_origins = [o.strip() for o in settings.cors_allow_origins.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(families.router)
app.include_router(ingest.router)
app.include_router(events.router)
app.include_router(assistant.router)


@app.get("/")
async def root():
    return {"name": "Dayby API", "status": "ok", "env": settings.app_env}


@app.get("/health")
async def health():
    """Liveness plus MongoDB connectivity."""
    return {"status": "ok", "mongo": await ping()}
