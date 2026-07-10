"""Text ingest: turn a natural-language utterance into a structured record.

The response is a confirmation payload (nothing is saved yet). Saving happens
after the user confirms, via the events endpoints (added in a later step).
"""
from datetime import datetime, timezone

from fastapi import APIRouter

from ..models.events import IngestTextRequest, LlmContext, StructuredResult
from ..providers import get_llm_provider

router = APIRouter(prefix="/ingest", tags=["ingest"])


@router.post("/text", response_model=StructuredResult)
async def ingest_text(req: IngestTextRequest) -> StructuredResult:
    llm = get_llm_provider()
    ctx = LlmContext(
        now=req.now or datetime.now(timezone.utc),
        baby_names=[],  # populated once babies exist (next step)
        lang=req.lang,
    )
    return await llm.structure_log(req.text, ctx)
