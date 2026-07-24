"""Text to speech. Returns a WAV of the assistant's reply, or 204 when there is no
server voice configured -- in which case the app speaks it on-device."""
from typing import Optional

from fastapi import APIRouter, Depends, Response
from pydantic import BaseModel

from ..deps import get_current_family
from ..providers import get_tts_provider

router = APIRouter(prefix="/tts", tags=["tts"])


class TTSRequest(BaseModel):
    text: str
    lang: Optional[str] = None


@router.post("")
async def synthesize(
    body: TTSRequest,
    family: dict = Depends(get_current_family),
) -> Response:
    audio = await get_tts_provider().synthesize(body.text, body.lang)
    if not audio:
        return Response(status_code=204)
    return Response(content=audio, media_type="audio/wav")
