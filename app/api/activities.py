from datetime import datetime
from typing import Optional

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Query,
    Request,
)
from sqlalchemy import or_, select
from sqlalchemy.orm import Session, selectinload

from app.activity_access import (
    activity_history_filter,
    require_activity_history_access,
)
from app.database import get_db
from app.models import Activity
from app.schemas import (
    ActivityListResponse,
    ActivityResponse,
    ActivitySummary,
)


router = APIRouter(
    prefix="/activities",
    tags=["Activities"],
)


@router.get(
    "",
    response_model=ActivityListResponse,
)
def list_activities(
    request: Request,
    environment: Optional[str] = None,
    subenvironment: Optional[str] = None,
    status: Optional[str] = None,
    resource: Optional[str] = None,
    taskno: Optional[int] = None,
    date_from: Optional[datetime] = None,
    date_to: Optional[datetime] = None,
    search: Optional[str] = None,
    include_deleted: bool = False,
    limit: int = Query(
        default=50,
        ge=1,
        le=500,
    ),
    offset: int = Query(
        default=0,
        ge=0,
    ),
    db: Session = Depends(get_db),
):
    user = request.state.user

    statement = (
        select(Activity)
        .where(
            activity_history_filter(
                user=user,
            )
        )
    )

    if not include_deleted:
        statement = statement.where(
            Activity.deleted.is_(False)
        )

    if environment:
        statement = statement.where(
            Activity.environment == environment
        )

    if subenvironment:
        statement = statement.where(
            Activity.subenvironment
            == subenvironment
        )

    if status:
        statement = statement.where(
            Activity.status == status
        )

    if resource:
        statement = statement.where(
            Activity.resource == resource
        )

    if taskno is not None:
        statement = statement.where(
            Activity.taskno == taskno
        )

    if date_from is not None:
        statement = statement.where(
            Activity.est_time >= date_from
        )

    if date_to is not None:
        statement = statement.where(
            Activity.est_time <= date_to
        )

    if search:
        search_pattern = "%{}%".format(
            search
        )

        statement = statement.where(
            or_(
                Activity.title.ilike(
                    search_pattern
                ),
                Activity.details.ilike(
                    search_pattern
                ),
                Activity.note.ilike(
                    search_pattern
                ),
                Activity.dependency.ilike(
                    search_pattern
                ),
                Activity.resource.ilike(
                    search_pattern
                ),
            )
        )

    statement = (
        statement
        .order_by(
            Activity.est_time.desc(),
            Activity.taskno,
        )
        .offset(offset)
        .limit(limit)
    )

    activities = db.scalars(
        statement
    ).all()

    items = [
        ActivitySummary.model_validate(
            activity
        )
        for activity in activities
    ]

    return ActivityListResponse(
        items=items,
        limit=limit,
        offset=offset,
        returned=len(items),
    )


@router.get(
    "/{activity_id}",
    response_model=ActivityResponse,
)
def get_activity(
    request: Request,
    activity_id: int,
    db: Session = Depends(get_db),
):
    statement = (
        select(Activity)
        .options(
            selectinload(
                Activity.events
            )
        )
        .where(
            Activity.id == activity_id
        )
    )

    activity = db.scalar(
        statement
    )

    if activity is None:
        raise HTTPException(
            status_code=404,
            detail="Activity not found",
        )

    require_activity_history_access(
        activity=activity,
        user=request.state.user,
    )

    return ActivityResponse.model_validate(
        activity
    )
