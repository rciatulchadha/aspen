ACTIVITY_STATUSES = [
    "None",
    "Started",
    "Completed",
    "Failed",
    "On Hold",
    "Cancelled",
]
VALID_ACTIVITY_STATUSES = set(ACTIVITY_STATUSES)


def normalize_activity_status(value):
    normalized = value.strip() if value else "None"
    return normalized if normalized in VALID_ACTIVITY_STATUSES else None
