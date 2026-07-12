"""Live family sync: what one parent logs, the other's phone shows.

The whole mechanism is MongoDB's change stream. The server tails the oplog for
this family's inserts and forwards them down a WebSocket — no polling loop, no
message broker, and no second copy of the truth.
"""
import asyncio
import logging

from fastapi import APIRouter, WebSocket

from ..db import get_db
from .events import event_out

logger = logging.getLogger("dayby.live")

router = APIRouter(tags=["live"])


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
async def live_events(websocket: WebSocket, family_id: str) -> None:
    """Every event this family logs, as it is logged.

    The family comes in as a query parameter rather than the usual X-Family-Id:
    browsers cannot set headers on a WebSocket. It is the same secret either way,
    and it stops being one at all once auth lands.
    """
    if await get_db().families.find_one({"_id": family_id}) is None:
        await websocket.close(code=4404, reason="Unknown family")
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
