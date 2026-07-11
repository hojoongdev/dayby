"""Ingest an utterance (typed or spoken) and structure it into a record.

Both endpoints return a confirmation payload; nothing is saved until the user
confirms and posts to /events.
"""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request

from ..db import get_db
from ..deps import get_current_family
from ..models.events import (
    Action,
    IngestTextRequest,
    IngestVoiceResponse,
    LlmContext,
    StructuredResult,
)
from ..providers import get_llm_provider, get_stt_provider
from ..util import now

router = APIRouter(prefix="/ingest", tags=["ingest"])


async def _baby_names(family: dict) -> list[str]:
    """The family's baby names + nicknames, so the model can resolve "who"."""
    names: list[str] = []
    async for baby in get_db().babies.find({"family_id": family["_id"]}):
        names.append(baby["name"])
        names.extend(baby.get("nicknames", []))
    return names


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


@router.post("/text", response_model=StructuredResult)
async def ingest_text(
    req: IngestTextRequest,
    family: dict = Depends(get_current_family),
) -> StructuredResult:
    ctx = LlmContext(
        now=req.now or now(),
        baby_names=await _baby_names(family),
        lang=req.lang,
    )
    result = await get_llm_provider().structure_log(req.text, ctx)
    return await _answer_if_query(result, family, ctx, result.query_text or req.text)


@router.post("/voice", response_model=IngestVoiceResponse)
async def ingest_voice(
    request: Request,
    family: dict = Depends(get_current_family),
    lang: Optional[str] = None,
) -> IngestVoiceResponse:
    """Transcribe raw audio (the request body) then structure it, like /text.

    The audio is the raw request body (Content-Type e.g. audio/wav); this keeps
    the endpoint dependency-free. STT sits behind the provider interface, so the
    mock runs offline and a real cloud/Gemini transcriber drops in later.
    """
    audio = await request.body()
    if not audio:
        raise HTTPException(status_code=400, detail="Empty audio body")
    transcript = await get_stt_provider().transcribe(audio, lang)
    ctx = LlmContext(now=now(), baby_names=await _baby_names(family), lang=lang)
    result = await get_llm_provider().structure_log(transcript, ctx)
    result = await _answer_if_query(result, family, ctx, result.query_text or transcript)
    return IngestVoiceResponse(transcript=transcript, result=result)
