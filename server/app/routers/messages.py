"""Notes between caregivers. Family-scoped; needs a signed-in caller (there has to be
a sender and someone to send to)."""
from fastapi import APIRouter, Depends, HTTPException, Response

from ..db import get_db
from ..deps import get_current_family, get_current_user
from ..models.message import MessageCreate, MessageOut
from ..util import new_id, now

router = APIRouter(prefix="/messages", tags=["messages"])


def _out(doc: dict, me: str) -> MessageOut:
    mine = doc.get("from_user") == me
    return MessageOut(
        id=doc["_id"],
        text=doc["text"],
        from_user=doc.get("from_user"),
        from_name=doc.get("from_name"),
        mine=mine,
        # Your own message is read by definition; otherwise it is read once you have opened
        # the thread and been added to read_by.
        read=mine or me in doc.get("read_by", []),
        created_at=doc["created_at"],
    )


@router.post("", response_model=MessageOut, status_code=201)
async def send(
    body: MessageCreate,
    user: dict = Depends(get_current_user),
    family: dict = Depends(get_current_family),
) -> MessageOut:
    text = body.text.strip()
    if not text:
        raise HTTPException(status_code=422, detail="A message needs some text")
    doc = {
        "_id": new_id(),
        "family_id": family["_id"],
        "from_user": user["_id"],
        "from_name": user.get("name"),
        "text": text,
        # The sender has, of course, read their own message.
        "read_by": [user["_id"]],
        "created_at": now(),
    }
    await get_db().messages.insert_one(doc)
    return _out(doc, user["_id"])


@router.get("", response_model=list[MessageOut])
async def inbox(
    user: dict = Depends(get_current_user),
    family: dict = Depends(get_current_family),
) -> list[MessageOut]:
    """The family's recent notes, newest first, marked read/mine for the caller."""
    cursor = (
        get_db().messages
        .find({"family_id": family["_id"]})
        .sort("created_at", -1)
        .limit(50)
    )
    return [_out(doc, user["_id"]) async for doc in cursor]


@router.post("/read", status_code=204)
async def mark_read(
    user: dict = Depends(get_current_user),
    family: dict = Depends(get_current_family),
) -> Response:
    """Mark everything in this family as read by the caller (opening the thread)."""
    await get_db().messages.update_many(
        {"family_id": family["_id"]}, {"$addToSet": {"read_by": user["_id"]}}
    )
    return Response(status_code=204)
