"""Live family sync: what one parent logs, the other's phone shows.

The whole mechanism is MongoDB's change stream. The server tails the oplog for
this family's inserts and forwards them down a WebSocket — no polling loop, no
message broker, and no second copy of the truth.
"""
import asyncio
import logging
from typing import Optional

from fastapi import APIRouter, HTTPException, WebSocket

from ..config import settings
from ..db import get_db
from ..tokens import ACCESS, read_token
from .events import event_out

logger = logging.getLogger("dayby.live")

router = APIRouter(tags=["live"])


async def _authorize(family_id: str, token: Optional[str]) -> Optional[dict]:
    """The family, if this caller is really in it. Same rules as get_current_family,
    except the credentials arrive as query parameters: a browser cannot put headers
    on a WebSocket."""
    if settings.auth_enabled:
        if not token:
            return None
        try:
            user_id = read_token(token, ACCESS)
        except HTTPException:
            return None
        return await get_db().families.find_one({"_id": family_id, "members": user_id})

    if not settings.is_development:
        return None
    return await get_db().families.find_one({"_id": family_id})


async def _forward(websocket: WebSocket, family_id: str) -> None:
    """Tail everything that happens to this family's timeline, and push it out as it lands.

    Not only what is added. One parent saying "actually 200", or taking back a feed they
    logged twice, has to reach the other's phone as well — otherwise the two of them are
    looking at different truths and neither has any reason to doubt their own.
    """
    pipeline = [{
        "$match": {
            "$or": [
                # Added or corrected: the record as it now stands.
                {
                    "operationType": {"$in": ["insert", "update", "replace"]},
                    "fullDocument.family_id": family_id,
                },
                # Taken back. A delete carries nothing but an id, so without the document
                # it removed there is no family to match on and no baby whose timeline we
                # could say had changed. Mongo keeps it for us (see db.py).
                {
                    "operationType": "delete",
                    "fullDocumentBeforeChange.family_id": family_id,
                },
            ]
        }
    }]
    async with await get_db().events.watch(
        pipeline,
        full_document="updateLookup",
        full_document_before_change="whenAvailable",
    ) as stream:
        async for change in stream:
            # A record updated and then deleted before the lookup ran leaves neither.
            doc = change.get("fullDocument") or change.get("fullDocumentBeforeChange")
            if doc is None:
                continue
            await websocket.send_json({
                "type": "event",
                "change": change["operationType"],
                "event": event_out(doc).model_dump(mode="json"),
            })


@router.websocket("/ws/events")
async def live_events(
    websocket: WebSocket,
    family_id: str,
    token: Optional[str] = None,
) -> None:
    """Every event this family logs, as it is logged."""
    if await _authorize(family_id, token) is None:
        await websocket.close(code=4401, reason="Not your family")
        return

    await websocket.accept()

    # Whichever finishes first ends the session: the client going away, or the
    # stream falling over. Nothing is ever expected *from* the client.
    forwarding = asyncio.create_task(_forward(websocket, family_id))
    disconnected = asyncio.create_task(websocket.receive())
    done, pending = await asyncio.wait(
        {forwarding, disconnected}, return_when=asyncio.FIRST_COMPLETED
    )
    for task in pending:
        task.cancel()

    if forwarding in done and (error := forwarding.exception()) is not None:
        logger.error("Change stream ended for family %s", family_id, exc_info=error)
