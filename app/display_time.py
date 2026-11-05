from datetime import timezone
from zoneinfo import ZoneInfo

TORONTO_TIMEZONE = ZoneInfo("America/Toronto")


def format_toronto_datetime(value):
    if value is None:
        return "—"
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(TORONTO_TIMEZONE).strftime(
        "%Y-%m-%d %H:%M:%S %Z"
    )
