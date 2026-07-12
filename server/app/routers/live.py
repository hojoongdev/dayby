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
    """Tail this family's new events and push each one out as it lands."""
    pipeline = [{
        "$match": {
            "operationType": "insert",
            "fullDocument.family_id": family_id,
        }
    }]
    async with await get_db().events.watch(pipeline) as stream:
        async for change in stream:
            await websocket.send_json({
                "type": "event",
                "event": event_out(change["fullDocument"]).model_dump(mode="json"),
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
