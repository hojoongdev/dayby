"""Ingest an utterance (typed or spoken) and structure it into a record.

Both endpoints return a confirmation payload; nothing is saved until the user
confirms and posts to /events.
"""
from datetime import datetime
from typing import Optional

from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    HTTPException,
    Query,
    Request,
    UploadFile,
)

from ..context import build_llm_context
from ..db import get_db
from ..deps import get_current_family, require_baby
from ..models.events import (
    Action,
    IngestPhotoResponse,
    IngestTextRequest,
    IngestVoiceResponse,
    LlmContext,
    StructuredResult,
)
from ..photos import store_photo
from ..providers import get_llm_provider, get_stt_provider
from ..util import now
from .events import event_out

router = APIRouter(prefix="/ingest", tags=["ingest"])

# How far back to look for the record a correction refers to.
TARGET_CANDIDATES = 30

# A sentence, not a podcast. Gemini takes audio inline up to about this much.
MAX_AUDIO_BYTES = 16 * 1024 * 1024


async def _recent_events(family: dict, limit: int = 200) -> list[dict]:
    """Compact recent events for grounding a query answer (newest first)."""
    out: list[dict] = []
    cursor = get_db().events.find({"family_id": family["_id"]}).sort("time", -1).limit(limit)
    async for e in cursor:
        t = e.get("time")
        out.append({
            "type": e.get("type"),
            "subtype": e.get("subtype"),
            "fields": e.get("fields", {}),
            "time": t.isoformat() if hasattr(t, "isoformat") else str(t),
            "note": e.get("note"),
        })
    return out


async def _answer_if_query(
    result: StructuredResult, family: dict, ctx: LlmContext, question: str
) -> StructuredResult:
    """For a question, answer it from the logged events (grounded) into `reply`."""
    if result.action == Action.query:
        events = await _recent_events(family)
        result.reply = await get_llm_provider().answer_query(question, events, ctx)
    return result


async def _find_target(
    result: StructuredResult, family: dict, ctx: LlmContext, said: str
) -> StructuredResult:
    """For a correction or a removal, work out which record they meant.

    The model is shown real records and picks one by position; it never sees an id,
    so it cannot name a record that does not exist. Whatever it picks comes back in
    `target` for the caregiver to confirm before anything happens to it.
    """
    if result.action not in (Action.update, Action.delete):
        return result

    cursor = (
        get_db().events
        .find({"family_id": family["_id"]})
        .sort("time", -1)
        .limit(TARGET_CANDIDATES)
    )
    docs = [doc async for doc in cursor]
    if not docs:
        return result

    candidates = [
        {
            "type": doc["type"],
            "subtype": doc.get("subtype"),
            "fields": doc.get("fields", {}),
            # Local time, like everywhere else the model is shown a clock.
            "time": doc["time"].astimezone(ctx.now.tzinfo).isoformat(),
            "note": doc.get("note"),
        }
        for doc in docs
    ]
    index = await get_llm_provider().resolve_target(
        result.target_hint or said, candidates, ctx
    )
    if index is not None:
        result.target = event_out(docs[index])
    return result


@router.post("/text", response_model=StructuredResult)
async def ingest_text(
    req: IngestTextRequest,
    family: dict = Depends(get_current_family),
) -> StructuredResult:
    ctx = await build_llm_context(family, req.now or now(), req.lang)
    result = await get_llm_provider().structure_log(req.text, ctx)
    result = await _answer_if_query(result, family, ctx, result.query_text or req.text)
    return await _find_target(result, family, ctx, req.text)


@router.post("/voice", response_model=IngestVoiceResponse)
async def ingest_voice(
    request: Request,
    family: dict = Depends(get_current_family),
    lang: Optional[str] = None,
    at: Optional[datetime] = Query(None, alias="now"),
) -> IngestVoiceResponse:
    """Transcribe raw audio (the request body) then structure it, like /text.

    The audio is the raw request body (Content-Type e.g. audio/wav); this keeps the
    endpoint dependency-free. `lang` is only a hint — the real transcriber returns
    whatever language was actually spoken. `now` is the caller's local time, without
    which "at eight this morning" lands eight hours into a UTC morning nobody lives in.
    """
    audio = await request.body()
    if not audio:
        raise HTTPException(status_code=400, detail="Empty audio body")
    if len(audio) > MAX_AUDIO_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"Recording is too long (max {MAX_AUDIO_BYTES // (1024 * 1024)} MB)",
        )

    mime_type = (request.headers.get("content-type") or "").split(";")[0].strip()
    if not mime_type.startswith("audio/"):
        raise HTTPException(
            status_code=415, detail=f"Not an audio recording: {mime_type or 'unknown'}"
        )

    transcript = await get_stt_provider().transcribe(audio, mime_type, lang)
    if not transcript.strip():
        raise HTTPException(
            status_code=422, detail="I couldn't make that out — say it again?"
        )

    ctx = await build_llm_context(family, at or now(), lang)
    result = await get_llm_provider().structure_log(transcript, ctx)
    result = await _answer_if_query(result, family, ctx, result.query_text or transcript)
    result = await _find_target(result, family, ctx, transcript)
    return IngestVoiceResponse(transcript=transcript, result=result)


@router.post("/photo", response_model=IngestPhotoResponse)
async def ingest_photo(
    file: UploadFile = File(...),
    baby_id: str = Form(...),
    text: str = Form(""),
    lang: Optional[str] = Form(None),
    at: Optional[datetime] = Form(None, alias="now"),
    family: dict = Depends(get_current_family),
) -> IngestPhotoResponse:
    """A picture, with or without words: "is this rash normal?", or just a first smile.

    The photo is stored before the model sees it and its id is stitched into every
    event that comes back, so confirming the result saves the picture along with it.
    The model is told not to diagnose — it describes what it can see and points at a
    pediatrician.
    """
    await require_baby(family, baby_id)

    data = await file.read()
    content_type = file.content_type or ""
    photo_id = await store_photo(data, content_type, family["_id"], baby_id)

    ctx = await build_llm_context(family, at or now(), lang)
    result = await get_llm_provider().structure_photo(data, content_type, text, ctx)
    for event in result.events:
        event.fields["photo_id"] = photo_id

    return IngestPhotoResponse(photo_id=photo_id, result=result)
