"""Serve a stored photo back to the app."""
from fastapi import APIRouter, Depends, Response

from ..deps import get_current_family
from ..photos import load_photo

router = APIRouter(prefix="/photos", tags=["photos"])


@router.get("/{photo_id}")
async def get_photo(
    photo_id: str,
    family: dict = Depends(get_current_family),
) -> Response:
    data, content_type = await load_photo(photo_id, family["_id"])
    # A photo never changes once written, so let the client keep it.
    return Response(
        content=data,
        media_type=content_type,
        headers={"Cache-Control": "private, max-age=31536000, immutable"},
    )
