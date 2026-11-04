from sqlalchemy import text

AUDIT_TARGET_ACTIVITY = "ACTIVITY"
AUDIT_TARGET_DAILY_TASK = "DAILY_TASK"


def get_audit_history(db, target_type, target_id, limit=100):
    safe_limit = min(max(int(limit), 1), 500)
    return db.execute(
        text(
            """
            SELECT id, occurred_at, username, display_name,
                   authentication_type, role, action, target_type,
                   target_id, result, source_ip, reason, details
            FROM app_audit_log
            WHERE target_type = :target_type
              AND target_id = :target_id
            ORDER BY occurred_at DESC, id DESC
            LIMIT :limit
            """
        ),
        {
            "target_type": target_type,
            "target_id": str(target_id),
            "limit": safe_limit,
        },
    ).mappings().all()


def format_audit_value(value):
    if value is None:
        return "(blank)"
    if isinstance(value, bool):
        return "Yes" if value else "No"
    if hasattr(value, "strftime"):
        try:
            return value.strftime("%Y-%m-%d %H:%M:%S")
        except (ValueError, TypeError):
            pass
    text_value = str(value).strip()
    return text_value if text_value else "(blank)"


def describe_changes(changes):
    descriptions = []
    for label, old_value, new_value in changes:
        if old_value == new_value:
            continue
        descriptions.append(
            f"{label}: {format_audit_value(old_value)} -> "
            f"{format_audit_value(new_value)}"
        )
    return "; ".join(descriptions) if descriptions else "No field changes detected."
