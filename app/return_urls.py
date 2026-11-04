from urllib.parse import urlsplit


def safe_return_url(value, allowed_prefix, default):
    if not value:
        return default
    value = value.strip()
    parts = urlsplit(value)
    if parts.scheme or parts.netloc or not parts.path.startswith(allowed_prefix):
        return default
    return value


def activity_return_url(value):
    return safe_return_url(value, "/web/activities", "/web/activities")


def daily_task_return_url(value):
    return safe_return_url(value, "/web/daily-tasks", "/web/daily-tasks")
