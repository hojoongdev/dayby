"""Text ingest: turn a natural-language utterance into a structured record.

The response is a confirmation payload (nothing is saved yet). Saving happens
after the user confirms, via the events endpoints (added in a later step).
"""
from fastapi import APIRouter, Depends

from ..db import get_db
from ..deps import get_current_family
from ..models.events import IngestTextRequest, LlmContext, StructuredResult
from ..providers import get_llm_provider
from ..util import now

router = APIRouter(prefix="/ingest", tags=["ingest"])


@router.post("/text", response_model=StructuredResult)
async def ingest_text(
    req: IngestTextRequest,
    family: dict = Depends(get_current_family),
) -> StructuredResult:
    # Inject the family's baby names/nicknames so the model can resolve "who".
    baby_names: list[str] = []
    async for baby in get_db().babies.find({"family_id": family["_id"]}):
        baby_names.append(baby["name"])
        baby_names.extend(baby.get("nicknames", []))

    ctx = LlmContext(now=req.now or now(), baby_names=baby_names, lang=req.lang)
    return await get_llm_provider().structure_log(req.text, ctx)
