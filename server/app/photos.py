"""Photo storage, in MongoDB's GridFS.

Photos are family-scoped like everything else: the owning family is stamped into
the file metadata on the way in, and checked on the way out.
"""
from io import BytesIO

from fastapi import HTTPException

from .db import PHOTO_BUCKET, get_db, get_photo_bucket
from .util import new_id, now

MAX_BYTES = 8 * 1024 * 1024
ALLOWED_TYPES = ("image/jpeg", "image/png", "image/webp", "image/heic")


async def store_photo(
    data: bytes, content_type: str, family_id: str, baby_id: str
) -> str:
    if not data:
        raise HTTPException(status_code=400, detail="Empty photo")
    if len(data) > MAX_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"Photo is too large (max {MAX_BYTES // (1024 * 1024)} MB)",
        )
    if content_type not in ALLOWED_TYPES:
        raise HTTPException(
            status_code=415, detail=f"Unsupported image type: {content_type}"
        )

    photo_id = new_id()
    await get_photo_bucket().upload_from_stream_with_id(
        photo_id,
        f"{photo_id}.img",
        BytesIO(data),
        metadata={
            "family_id": family_id,
            "baby_id": baby_id,
            "content_type": content_type,
            "uploaded_at": now(),
        },
    )
    return photo_id


async def load_photo(photo_id: str, family_id: str) -> tuple[bytes, str]:
    """The bytes and their content type, or 404 for another family's photo."""
    doc = await get_db()[f"{PHOTO_BUCKET}.files"].find_one({"_id": photo_id})
    metadata = (doc or {}).get("metadata") or {}
    if not doc or metadata.get("family_id") != family_id:
        raise HTTPException(status_code=404, detail="Photo not found")

    stream = await get_photo_bucket().open_download_stream(photo_id)
    return await stream.read(), metadata["content_type"]
