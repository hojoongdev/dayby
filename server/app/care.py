"""What counts as a gap worth mentioning.

Shared by the assistant (which decides when the phone should buzz) and the offline
LLM stand-in (which has to agree with it), so there is one set of numbers and not two.
"""
from datetime import timedelta

OVERDUE_AFTER = {
    "feeding": timedelta(hours=4),
    "diaper": timedelta(hours=3),
    "sleep": timedelta(hours=6),
}
