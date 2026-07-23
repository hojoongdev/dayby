"""Ingest an utterance (typed, spoken or photographed) and structure it into a record.

Each endpoint also takes the chat history. Nothing is saved until the user confirms and
posts to /events.
"""
import json
import logging
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile

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
    Turn,
)
from ..photos import store_photo
from ..providers import get_llm_provider, get_stt_provider
from ..query import run_plan
from ..ratelimit import rate_limit_ingest
from ..util import now
from .events import event_out

logger = logging.getLogger("dayby.ingest")

router = APIRouter(prefix="/ingest", tags=["ingest"])

# How far back to look for the record a correction refers to.
TARGET_CANDIDATES = 30

# A sentence, not a podcast. Gemini takes audio inline up to about this much.
MAX_AUDIO_BYTES = 16 * 1024 * 1024


def _turns(raw: str) -> list[Turn]:
    """Parse the chat history, which the multipart endpoints carry as a JSON string.

    A bad one is logged and dropped rather than failing the request: losing the history is
    better than losing the log entry.
    """
    try:
        return [Turn.model_validate(turn) for turn in json.loads(raw)]
    except (ValueError, TypeError) as exc:
        logger.warning("Ignoring malformed history: %s", exc)
        return []


def _languages(raw: str) -> list[str]:
    """The caregiver's languages, which ride the multipart endpoints as "ko,en"."""
    return [code.strip() for code in raw.split(",") if code.strip()]


def _held_to_language(result: StructuredResult, ctx: LlmContext) -> StructuredResult:
    """`lang` is what the app speaks the reply out loud in.

    Naming the caregiver's languages in the prompt is a strong prior, but only a prior: a
    quiet sentence over a crying baby can still come back believed to be Chinese. It is
    not this server's place to overwrite the words — but it will not hand the phone a
    voice its owner cannot understand.
    """
    if result.lang not in ctx.languages:
        logger.warning("Model answered in %s, which they do not speak", result.lang)
        result.lang = ctx.languages[0]
    return result


def _found_nothing(records: list[dict]) -> bool:
    """Whether a query came back empty, aggregate or not."""
    if not records:
        return True
    row = records[0]
    if "aggregate" in row:
        return row.get("value") in (None, 0) and row.get("count", 0) == 0
    return False


async def _answer_if_query(
    result: StructuredResult, family: dict, ctx: LlmContext, question: str
) -> StructuredResult:
    """Answer a question over the whole history, grounded, into `reply`.

    Two passes: the model turns the question into a query the server runs (so a record
    logged months ago is still reachable), then writes the answer from what came back.
    A record logged in one language and asked about in another can make the first query
    too tight, so an empty result is retried with the wording filters dropped.
    """
    if result.action == Action.query:
        provider = get_llm_provider()
        plan = await provider.plan_query(question, ctx)
        records = await run_plan(plan, family["_id"], None, ctx.now.tzinfo)
        if _found_nothing(records) and (plan.contains or plan.subtype):
            broader = plan.model_copy(update={"contains": None, "subtype": None})
            records = await run_plan(broader, family["_id"], None, ctx.now.tzinfo)
        result.reply = await provider.answer_query(question, records, ctx)
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


@router.post(
    "/text", response_model=StructuredResult, dependencies=[Depends(rate_limit_ingest)]
)
async def ingest_text(
    req: IngestTextRequest,
    family: dict = Depends(get_current_family),
) -> StructuredResult:
    ctx = await build_llm_context(
        family, req.now or now(), req.lang, req.history, req.languages
    )
    result = _held_to_language(await get_llm_provider().structure_log(req.text, ctx), ctx)
    result = await _answer_if_query(result, family, ctx, result.query_text or req.text)
    return await _find_target(result, family, ctx, req.text)


@router.post(
    "/voice",
    response_model=IngestVoiceResponse,
    dependencies=[Depends(rate_limit_ingest)],
)
async def ingest_voice(
    file: UploadFile = File(...),
    lang: Optional[str] = Form(None),
    languages: str = Form(""),
    at: Optional[datetime] = Form(None, alias="now"),
    history: str = Form("[]"),
    family: dict = Depends(get_current_family),
) -> IngestVoiceResponse:
    """Transcribe a recording, then structure it like a typed sentence.

    The audio is a multipart field rather than the raw request body, so the chat history
    can travel with it. `languages` is what this caregiver says they speak, and the
    transcriber is held to it. `now` is the caller's local time, without which "at eight
    this morning" resolves in UTC.
    """
    audio = await file.read()
    if not audio:
        raise HTTPException(status_code=400, detail="Empty audio body")
    if len(audio) > MAX_AUDIO_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"Recording is too long (max {MAX_AUDIO_BYTES // (1024 * 1024)} MB)",
        )

    mime_type = (file.content_type or "").split(";")[0].strip()
    if not mime_type.startswith("audio/"):
        raise HTTPException(
            status_code=415, detail=f"Not an audio recording: {mime_type or 'unknown'}"
        )

    spoken = _languages(languages)
    transcript = await get_stt_provider().transcribe(audio, mime_type, spoken)
    if not transcript.strip():
        raise HTTPException(
            status_code=422, detail="I couldn't make that out — say it again?"
        )

    ctx = await build_llm_context(family, at or now(), lang, _turns(history), spoken)
    result = _held_to_language(await get_llm_provider().structure_log(transcript, ctx), ctx)
    result = await _answer_if_query(result, family, ctx, result.query_text or transcript)
    result = await _find_target(result, family, ctx, transcript)
    return IngestVoiceResponse(transcript=transcript, result=result)


@router.post(
    "/photo",
    response_model=IngestPhotoResponse,
    dependencies=[Depends(rate_limit_ingest)],
)
async def ingest_photo(
    file: UploadFile = File(...),
    baby_id: str = Form(...),
    text: str = Form(""),
    lang: Optional[str] = Form(None),
    languages: str = Form(""),
    at: Optional[datetime] = Form(None, alias="now"),
    history: str = Form("[]"),
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

    ctx = await build_llm_context(
        family, at or now(), lang, _turns(history), _languages(languages)
    )
    result = _held_to_language(
        await get_llm_provider().structure_photo(data, content_type, text, ctx), ctx
    )
    for event in result.events:
        event.fields["photo_id"] = photo_id

    return IngestPhotoResponse(photo_id=photo_id, result=result)
