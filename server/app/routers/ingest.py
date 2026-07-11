"""Ingest an utterance (typed or spoken) and structure it into a record.

Both endpoints return a confirmation payload; nothing is saved until the user
confirms and posts to /events.
"""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request

from ..db import get_db
from ..deps import get_current_family
from ..models.events import (
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
    return await get_llm_provider().structure_log(req.text, ctx)


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
    return IngestVoiceResponse(transcript=transcript, result=result)
