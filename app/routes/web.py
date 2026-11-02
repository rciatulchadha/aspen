from datetime import datetime
from typing import Optional

from fastapi import (
    APIRouter,
    Depends,
    Form,
    HTTPException,
    Request,
)
from fastapi.responses import (
    HTMLResponse,
    RedirectResponse,
)
from fastapi.templating import Jinja2Templates
from sqlalchemy import (
    String,
    func,
    or_,
    select,
    text,
)
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session, selectinload

from app.database import get_db
from app.models import Activity


router = APIRouter(
    prefix="/web",
    tags=["Web"],
)

templates = Jinja2Templates(
    directory="app/templates"
)


# ============================================================
# Helper
# ============================================================

def get_environment_values(db):
    return db.scalars(
        select(Activity.environment)
        .distinct()
        .order_by(Activity.environment)
    ).all()


# ============================================================
# ACTIVITY LIST
# ============================================================

@router.get(
    "/activities",
    response_class=HTMLResponse,
)
def activities_page(
    request: Request,
    environment: Optional[str] = None,
    subenvironment: Optional[str] = None,
    status: Optional[str] = None,
    search: Optional[str] = None,
    include_deleted: bool = False,
    page: int = 1,
    page_size: int = 50,
    db: Session = Depends(get_db),
):
    page = max(page, 1)

    page_size = min(
        max(page_size, 10),
        100,
    )

    filters = []

    if not include_deleted:
        filters.append(
            Activity.deleted.is_(False)
        )

    if environment:
        filters.append(
            Activity.environment == environment
        )

    if subenvironment:
        filters.append(
            Activity.subenvironment == subenvironment
        )

    if status:
        filters.append(
            Activity.status == status
        )

    if search:
        pattern = "%{}%".format(
            search.strip()
        )

        filters.append(
            or_(
                Activity.title.ilike(pattern),
                Activity.details.ilike(pattern),
                Activity.note.ilike(pattern),
                Activity.resource.ilike(pattern),
                Activity.dependency.ilike(pattern),
                Activity.taskno.cast(
                    String
                ).ilike(pattern),
            )
        )

    total_rows = db.scalar(
        select(func.count(Activity.id))
        .where(*filters)
    ) or 0

    total_pages = max(
        1,
        (
            total_rows
            + page_size
            - 1
        )
        // page_size,
    )

    if page > total_pages:
        page = total_pages

    offset = (
        page - 1
    ) * page_size

    activities = db.scalars(
        select(Activity)
        .where(*filters)
        .order_by(
            Activity.est_time.asc(),
            Activity.taskno.asc(),
        )
        .offset(offset)
        .limit(page_size)
    ).all()

    environments = get_environment_values(db)

    statuses = db.scalars(
        select(Activity.status)
        .where(
            Activity.status.is_not(None)
        )
        .distinct()
        .order_by(Activity.status)
    ).all()

    subenvironments = []

    if environment:
        subenvironments = db.scalars(
            select(Activity.subenvironment)
            .where(
                Activity.environment
                == environment
            )
            .distinct()
            .order_by(
                Activity.subenvironment
            )
        ).all()

    return templates.TemplateResponse(
        request=request,
        name="activities.html",
        context={
            "activities": activities,
            "environments": environments,
            "statuses": statuses,
            "subenvironments": subenvironments,
            "selected_environment": (
                environment or ""
            ),
            "selected_subenvironment": (
                subenvironment or ""
            ),
            "selected_status": (
                status or ""
            ),
            "search": search or "",
            "include_deleted": include_deleted,
            "page": page,
            "page_size": page_size,
            "total_rows": total_rows,
            "total_pages": total_pages,
        },
    )


# ============================================================
# NEW ACTIVITY FORM
#
# Must appear before /activities/{activity_id}
# ============================================================

@router.get(
    "/activities/new",
    response_class=HTMLResponse,
)
def new_activity_page(
    request: Request,
    db: Session = Depends(get_db),
):
    return templates.TemplateResponse(
        request=request,
        name="activity_new.html",
        context={
            "environments": get_environment_values(
                db
            ),
            "error": None,
            "form": None,
        },
    )


# ============================================================
# CREATE ACTIVITY
# ============================================================

@router.post(
    "/activities/new",
    response_class=HTMLResponse,
)
def create_activity(
    request: Request,
    taskno: int = Form(...),
    est_time: datetime = Form(...),
    title: str = Form(...),
    details: str = Form(...),
    note: str = Form(""),
    environment: str = Form(...),
    subenvironment: str = Form(""),
    dependency: str = Form(""),
    resource: str = Form(""),
    username: str = Form(...),
    db: Session = Depends(get_db),
):
    clean_title = title.strip()
    clean_details = details.strip()
    clean_environment = environment.strip()
    clean_subenvironment = (
        subenvironment.strip()
    )
    clean_note = note.strip()
    clean_dependency = dependency.strip()
    clean_resource = resource.strip()
    clean_username = username.strip()

    environments = get_environment_values(db)

    form_values = {
        "taskno": taskno,
        "est_time": est_time.strftime(
            "%Y-%m-%dT%H:%M"
        ),
        "title": title,
        "details": details,
        "note": note,
        "environment": environment,
        "subenvironment": subenvironment,
        "dependency": dependency,
        "resource": resource,
        "username": username,
    }

    error = None

    if not clean_title:
        error = "Title is required."

    elif not clean_details:
        error = (
            "Activity details are required."
        )

    elif not clean_environment:
        error = "Environment is required."

    elif not clean_username:
        error = "Operator is required."

    elif len(clean_title) > 500:
        error = (
            "Title cannot exceed "
            "500 characters."
        )

    elif len(clean_environment) > 10:
        error = (
            "Environment cannot exceed "
            "10 characters."
        )

    elif len(clean_subenvironment) > 25:
        error = (
            "Sub-environment cannot exceed "
            "25 characters."
        )

    elif len(clean_dependency) > 50:
        error = (
            "Dependency cannot exceed "
            "50 characters."
        )

    elif len(clean_resource) > 50:
        error = (
            "Resource cannot exceed "
            "50 characters."
        )

    elif len(clean_username) > 50:
        error = (
            "Operator cannot exceed "
            "50 characters."
        )

    if error:
        return templates.TemplateResponse(
            request=request,
            name="activity_new.html",
            status_code=400,
            context={
                "environments": environments,
                "error": error,
                "form": form_values,
            },
        )

    try:
        db.execute(
            text(
                """
                CALL sp_rocc_insert_newactivity(
                    :taskno,
                    :est_time,
                    :title,
                    :details,
                    :note,
                    :environment,
                    :subenvironment,
                    :dependency,
                    :resource,
                    :username
                )
                """
            ),
            {
                "taskno": taskno,
                "est_time": est_time,
                "title": clean_title,
                "details": clean_details,
                "note": clean_note,
                "environment": clean_environment,
                "subenvironment": (
                    clean_subenvironment
                ),
                "dependency": clean_dependency,
                "resource": clean_resource,
                "username": clean_username,
            },
        )

        db.commit()

        new_activity_id = db.scalar(
            select(Activity.id)
            .where(
                Activity.taskno == taskno,
                Activity.est_time == est_time,
                Activity.environment
                == clean_environment,
            )
            .order_by(Activity.id.desc())
            .limit(1)
        )

        if new_activity_id is None:
            raise RuntimeError(
                "Created Activity could not "
                "be located."
            )

    except IntegrityError:
        db.rollback()

        return templates.TemplateResponse(
            request=request,
            name="activity_new.html",
            status_code=409,
            context={
                "environments": environments,
                "error": (
                    "An Activity already exists "
                    "with this Task Number, "
                    "estimated time, and "
                    "environment."
                ),
                "form": form_values,
            },
        )

    except SQLAlchemyError as exception:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail=(
                "Unable to create Activity. "
                "The database transaction "
                "was rolled back."
            ),
        ) from exception

    return RedirectResponse(
        url=(
            "/web/activities/"
            "{}?activity_added=true"
        ).format(new_activity_id),
        status_code=303,
    )


# ============================================================
# EDIT ACTIVITY FORM
#
# Must also appear before /activities/{activity_id}
# ============================================================

@router.get(
    "/activities/{activity_id}/edit",
    response_class=HTMLResponse,
)
def edit_activity_page(
    request: Request,
    activity_id: int,
    db: Session = Depends(get_db),
):
    activity = db.get(
        Activity,
        activity_id,
    )

    if activity is None:
        raise HTTPException(
            status_code=404,
            detail="Activity not found",
        )

    statuses = db.scalars(
        select(Activity.status)
        .where(
            Activity.status.is_not(None)
        )
        .distinct()
        .order_by(Activity.status)
    ).all()

    return templates.TemplateResponse(
        request=request,
        name="activity_edit.html",
        context={
            "activity": activity,
            "environments": (
                get_environment_values(db)
            ),
            "statuses": statuses,
            "error": None,
        },
    )


# ============================================================
# UPDATE ACTIVITY
# ============================================================

@router.post(
    "/activities/{activity_id}/edit",
    response_class=HTMLResponse,
)
def update_activity(
    request: Request,
    activity_id: int,
    taskno: int = Form(...),
    est_time: datetime = Form(...),
    title: str = Form(...),
    details: str = Form(...),
    status: str = Form("None"),
    closed: str = Form("No"),
    note: str = Form(""),
    environment: str = Form(...),
    subenvironment: str = Form(""),
    dependency: str = Form(""),
    resource: str = Form(""),
    approved: str = Form(""),
    criticalact: Optional[str] = Form(None),
    db: Session = Depends(get_db),
):
    activity = db.get(
        Activity,
        activity_id,
    )

    if activity is None:
        raise HTTPException(
            status_code=404,
            detail="Activity not found",
        )

    clean_title = title.strip()
    clean_details = details.strip()
    clean_status = status.strip()
    clean_closed = closed.strip()
    clean_environment = environment.strip()
    clean_subenvironment = (
        subenvironment.strip()
    )
    clean_dependency = dependency.strip()
    clean_resource = resource.strip()
    clean_approved = approved.strip()

    statuses = db.scalars(
        select(Activity.status)
        .where(
            Activity.status.is_not(None)
        )
        .distinct()
        .order_by(Activity.status)
    ).all()

    error = None

    if not clean_title:
        error = "Title is required."

    elif not clean_details:
        error = (
            "Activity details are required."
        )

    elif not clean_environment:
        error = "Environment is required."

    elif clean_closed not in (
        "Yes",
        "No",
    ):
        error = (
            "Closed must be Yes or No."
        )

    elif len(clean_title) > 500:
        error = (
            "Title cannot exceed "
            "500 characters."
        )

    elif len(clean_environment) > 10:
        error = (
            "Environment cannot exceed "
            "10 characters."
        )

    elif len(clean_subenvironment) > 25:
        error = (
            "Sub-environment cannot exceed "
            "25 characters."
        )

    elif len(clean_dependency) > 50:
        error = (
            "Dependency cannot exceed "
            "50 characters."
        )

    elif len(clean_resource) > 50:
        error = (
            "Resource cannot exceed "
            "50 characters."
        )

    elif len(clean_approved) > 50:
        error = (
            "Approved value cannot exceed "
            "50 characters."
        )

    if error:
        return templates.TemplateResponse(
            request=request,
            name="activity_edit.html",
            status_code=400,
            context={
                "activity": activity,
                "environments": (
                    get_environment_values(db)
                ),
                "statuses": statuses,
                "error": error,
            },
        )

    try:
        activity.taskno = taskno
        activity.est_time = est_time
        activity.title = clean_title
        activity.details = clean_details
        activity.status = clean_status
        activity.closed = clean_closed
        activity.note = note.strip()
        activity.environment = (
            clean_environment
        )
        activity.subenvironment = (
            clean_subenvironment
        )
        activity.dependency = (
            clean_dependency
        )
        activity.resource = clean_resource
        activity.approved = clean_approved

        activity.criticalact = (
            criticalact == "true"
        )

        db.commit()

    except IntegrityError:
        db.rollback()

        return templates.TemplateResponse(
            request=request,
            name="activity_edit.html",
            status_code=409,
            context={
                "activity": activity,
                "environments": (
                    get_environment_values(db)
                ),
                "statuses": statuses,
                "error": (
                    "Another Activity already "
                    "uses this Task Number, "
                    "estimated time, and "
                    "environment."
                ),
            },
        )

    except SQLAlchemyError as exception:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail=(
                "Unable to update Activity. "
                "The transaction was "
                "rolled back."
            ),
        ) from exception

    return RedirectResponse(
        url=(
            "/web/activities/"
            "{}?activity_updated=true"
        ).format(activity_id),
        status_code=303,
    )


# ============================================================
# SOFT DELETE ACTIVITY
# ============================================================

@router.post(
    "/activities/{activity_id}/delete",
    response_class=RedirectResponse,
)
def delete_activity(
    activity_id: int,
    db: Session = Depends(get_db),
):
    activity = db.get(
        Activity,
        activity_id,
    )

    if activity is None:
        raise HTTPException(
            status_code=404,
            detail="Activity not found",
        )

    try:
        activity.deleted = True
        db.commit()

    except SQLAlchemyError as exception:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail=(
                "Unable to delete Activity."
            ),
        ) from exception

    return RedirectResponse(
        url=(
            "/web/activities/"
            "{}?activity_deleted=true"
        ).format(activity_id),
        status_code=303,
    )


# ============================================================
# RESTORE ACTIVITY
# ============================================================

@router.post(
    "/activities/{activity_id}/restore",
    response_class=RedirectResponse,
)
def restore_activity(
    activity_id: int,
    db: Session = Depends(get_db),
):
    activity = db.get(
        Activity,
        activity_id,
    )

    if activity is None:
        raise HTTPException(
            status_code=404,
            detail="Activity not found",
        )

    try:
        activity.deleted = False
        db.commit()

    except SQLAlchemyError as exception:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail=(
                "Unable to restore Activity."
            ),
        ) from exception

    return RedirectResponse(
        url=(
            "/web/activities/"
            "{}?activity_restored=true"
        ).format(activity_id),
        status_code=303,
    )


# ============================================================
# ACTIVITY DETAILS
# ============================================================

@router.get(
    "/activities/{activity_id}",
    response_class=HTMLResponse,
)
def activity_detail_page(
    request: Request,
    activity_id: int,
    event_added: bool = False,
    activity_added: bool = False,
    activity_updated: bool = False,
    activity_deleted: bool = False,
    activity_restored: bool = False,
    db: Session = Depends(get_db),
):
    activity = db.scalar(
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

    if activity is None:
        raise HTTPException(
            status_code=404,
            detail="Activity not found",
        )

    return templates.TemplateResponse(
        request=request,
        name="activity_detail.html",
        context={
            "activity": activity,
            "event_added": event_added,
            "activity_added": activity_added,
            "activity_updated": (
                activity_updated
            ),
            "activity_deleted": (
                activity_deleted
            ),
            "activity_restored": (
                activity_restored
            ),
        },
    )


# ============================================================
# ADD EVENT
# ============================================================

@router.post(
    "/activities/{activity_id}/events",
    response_class=RedirectResponse,
)
def add_activity_event(
    activity_id: int,
    time_started: datetime = Form(...),
    details: str = Form(...),
    operator: str = Form(...),
    db: Session = Depends(get_db),
):
    activity = db.get(
        Activity,
        activity_id,
    )

    if activity is None:
        raise HTTPException(
            status_code=404,
            detail="Activity not found",
        )

    if activity.deleted:
        raise HTTPException(
            status_code=400,
            detail=(
                "Events cannot be added to "
                "a deleted Activity."
            ),
        )

    clean_details = details.strip()
    clean_operator = operator.strip()

    if not clean_details:
        raise HTTPException(
            status_code=400,
            detail=(
                "Event details are required."
            ),
        )

    if not clean_operator:
        raise HTTPException(
            status_code=400,
            detail="Operator is required.",
        )

    if len(clean_operator) > 50:
        raise HTTPException(
            status_code=400,
            detail=(
                "Operator cannot exceed "
                "50 characters."
            ),
        )

    try:
        db.execute(
            text(
                """
                CALL sp_rocc_insert_newevent(
                    :activity_id,
                    :time_started,
                    :details,
                    :operator
                )
                """
            ),
            {
                "activity_id": activity_id,
                "time_started": time_started,
                "details": clean_details,
                "operator": clean_operator,
            },
        )

        db.commit()

    except SQLAlchemyError as exception:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail=(
                "Unable to add Event. "
                "The database transaction "
                "was rolled back."
            ),
        ) from exception

    return RedirectResponse(
        url=(
            "/web/activities/"
            "{}?event_added=true"
        ).format(activity_id),
        status_code=303,
    )
