from datetime import datetime, timedelta

from fastapi import HTTPException

from app.models import Activity
from app.security import ROLE_ADMIN


# ============================================================
# ACTIVITY HISTORY ACCESS
#
# Reader / Operator:
#     Previous 24 hours
#
# Admin:
#     Previous 7 days
#
# Current and future Activities remain accessible.
# ============================================================

STANDARD_HISTORY_HOURS = 24
ADMIN_HISTORY_DAYS = 7


def activity_history_cutoff(
    user,
    now=None,
):
    if now is None:
        now = datetime.now()

    if user.role == ROLE_ADMIN:
        return now - timedelta(
            days=ADMIN_HISTORY_DAYS
        )

    return now - timedelta(
        hours=STANDARD_HISTORY_HOURS
    )


def activity_history_filter(
    user,
    now=None,
):
    cutoff = activity_history_cutoff(
        user=user,
        now=now,
    )

    return Activity.est_time >= cutoff


def require_activity_history_access(
    activity,
    user,
    now=None,
):
    cutoff = activity_history_cutoff(
        user=user,
        now=now,
    )

    if activity.est_time < cutoff:

        if user.role == ROLE_ADMIN:
            detail = (
                "Historical Activity access "
                "is limited to the previous "
                "7 days."
            )
        else:
            detail = (
                "Historical Activity access "
                "is limited to the previous "
                "24 hours."
            )

        raise HTTPException(
            status_code=403,
            detail=detail,
        )

    return activity


def require_activity_datetime_access(
    est_time,
    user,
    now=None,
):
    cutoff = activity_history_cutoff(
        user=user,
        now=now,
    )

    if est_time < cutoff:

        if user.role == ROLE_ADMIN:
            detail = (
                "Activity date cannot be "
                "older than 7 days."
            )
        else:
            detail = (
                "Activity date cannot be "
                "older than 24 hours."
            )

        raise HTTPException(
            status_code=403,
            detail=detail,
        )
