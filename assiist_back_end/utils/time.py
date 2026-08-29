from datetime import datetime, timezone
from zoneinfo import ZoneInfo, available_timezones


def to_user_tz(dt: datetime, tz: str) -> datetime:
    """Convert an aware/naïve datetime to the given IANA zone, defaulting to UTC.

    Args:
        dt: datetime – may be naïve (assumed UTC) or aware.
        tz: IANA zone, e.g. "America/Denver".
    Returns:
        datetime aware in the requested zone.
    """
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    try:
        if tz in available_timezones():
            zone = ZoneInfo(tz)
        else:
            zone = timezone.utc
    except Exception:
        zone = timezone.utc
    return dt.astimezone(zone)

def utc_now() -> datetime:
    """Return timezone-aware current UTC time.

    Replaces scattered calls to ``datetime.utcnow()`` which produce *naïve* datetimes.
    Use this helper whenever a value will be persisted to Firestore or compared in
    range filters so that tz-aware / tz-naïve mismatches cannot occur.
    """
    return datetime.now(timezone.utc) 