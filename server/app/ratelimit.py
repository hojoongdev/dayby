"""A small in-process rate limiter for the Gemini-backed endpoints.

One utterance is two model calls, so an unbounded /ingest is a way to run up a bill. This
caps how often one caller can hit those endpoints. It lives in memory, which is fine for a
single process; a multi-worker deployment would need a shared store (Redis).
"""
import time

from fastapi import HTTPException, Request

from .config import settings

WINDOW_SECONDS = 60


class FixedWindow:
    """A per-key counter that resets every window. No background sweep: a key is only
    looked at when it is hit, and stale keys cost one tuple until then."""

    def __init__(self) -> None:
        self._hits: dict[str, tuple[float, int]] = {}

    def hit(self, key: str, at: float, window: float) -> tuple[int, int]:
        """Count this hit. Returns (count in the current window, seconds until it resets)."""
        start, count = self._hits.get(key, (at, 0))
        if at - start >= window:
            start, count = at, 0
        count += 1
        self._hits[key] = (start, count)
        return count, int(start + window - at)


_ingest = FixedWindow()


def _caller_key(request: Request) -> str:
    """Who to count against: the family in dev, the session when signed in, the socket as
    a last resort."""
    return (
        request.headers.get("x-family-id")
        or request.headers.get("authorization")
        or (request.client.host if request.client else "anon")
    )


async def rate_limit_ingest(request: Request) -> None:
    count, reset_in = _ingest.hit(_caller_key(request), time.monotonic(), WINDOW_SECONDS)
    if count > settings.ingest_rate_per_minute:
        raise HTTPException(
            status_code=429,
            detail="That is a lot of logging at once. Give it a moment.",
            headers={"Retry-After": str(max(1, reset_in))},
        )
