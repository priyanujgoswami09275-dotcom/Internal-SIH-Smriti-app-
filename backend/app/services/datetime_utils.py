"""Shared UTC serialization for API and service response timestamps."""

from datetime import datetime, timezone
from typing import Optional


def iso_utc(value: Optional[datetime]) -> Optional[str]:
    """Serialize a possibly-naive UTC database value as ISO-8601 with ``Z``."""
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
