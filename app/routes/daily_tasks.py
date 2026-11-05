from datetime import date, datetime, timedelta
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
    case,
    func,
    or_,
    select,
    text,
)
from sqlalchemy.exc import (
    IntegrityError,
    SQLAlchemyError,
)
from sqlalchemy.orm import Session

from app.environments import (
    ASPEN_ENVIRONMENTS,
    is_valid_environment,
    normalize_environment,
)

from app.display_time import (
    format_toronto_datetime,
)

from app.audit_history import (
    AUDIT_TARGET_DAILY_TASK,
    describe_changes,
    get_audit_history,
)
from app.database import get_db
from app.models import DailyTask
from app.security import write_audit
from app.return_urls import daily_task_return_url


router = APIRouter(
    prefix="/web",
    tags=[
        "Daily Tasks",
        "Production Control",
    ],
)

templates = Jinja2Templates(
    directory="app/templates"
)
templates.env.filters[
    "toronto_time"
] = format_toronto_datetime

# ============================================================
# SCHEDULE OPTIONS
#
# 0 = Every Day
# 1 = Monday
# 2 = Tuesday
# 3 = Wednesday
# 4 = Thursday
# 5 = Friday
# 6 = Saturday
# 7 = Sunday
# ============================================================

WEEKDAYS = [
    {
        "number": "0",
        "name": "Every Day",
    },
    {
        "number": "1",
        "name": "Monday",
    },
    {
        "number": "2",
        "name": "Tuesday",
    },
    {
        "number": "3",
        "name": "Wednesday",
    },
    {
        "number": "4",
        "name": "Thursday",
    },
    {
        "number": "5",
        "name": "Friday",
    },
    {
        "number": "6",
        "name": "Saturday",
    },
    {
        "number": "7",
        "name": "Sunday",
    },
]


VALID_SCHEDULE_VALUES = {
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
}


# ============================================================
# SECURITY HELPERS
# ============================================================

def get_current_user(
    request: Request,
):
    user = getattr(
        request.state,
        "user",
        None,
    )

    if user is None:
        raise HTTPException(
            status_code=401,
            detail="Authentication required",
        )

    return user


def require_admin(
    request: Request,
):
    user = get_current_user(request)

    if not user.is_admin:
        raise HTTPException(
            status_code=403,
            detail=(
                "ASPEN Admin access "
                "is required."
            ),
        )

    return user


# ============================================================
# GENERAL HELPERS
# ============================================================

def get_environments(
    db: Session,
):
    return ASPEN_ENVIRONMENTS


def get_daily_task_or_404(
    db: Session,
    serial: int,
):
    task = db.get(
        DailyTask,
        serial,
    )

    if task is None:
        raise HTTPException(
            status_code=404,
            detail="Daily Task not found",
        )

    return task


def derive_schedule_from_taskno(
    taskno: int,
):
    """
    Daily Task numbers from 0 through 99 are
    shared recurring templates that are evaluated
    every day.

    Values 1 through 6 remain reserved for the
    migrated legacy EOX behavior.

    Numbers above 99 use the first digit as the
    weekday identifier.
    """

    if 0 <= taskno <= 99:
        return "0"

    task_text = str(taskno)

    if not task_text:
        return None

    first_character = task_text[0]

    if first_character in {
        "1",
        "2",
        "3",
        "4",
        "5",
        "6",
        "7",
    }:
        return first_character

    return None


def get_schedule_name(
    schedule_number: Optional[str],
):
    for schedule in WEEKDAYS:
        if (
            schedule["number"]
            == schedule_number
        ):
            return schedule["name"]

    return "Unknown"


def get_task_schedule_status(
    task: DailyTask,
):
    today = date.today()

    if task.deleted:
        return "Deleted"

    if task.effective_from > today:
        return "Future"

    if (
        task.effective_to is not None
        and task.effective_to < today
    ):
        return "Expired"

    return "Active"

def daily_task_schedule_order():
    return case(
        (
            DailyTask.taskno.between(
                0,
                99,
            ),
            0,
        ),
        (
            DailyTask.taskno.cast(
                String
            ).like(
                "1%"
            ),
            1,
        ),
        (
            DailyTask.taskno.cast(
                String
            ).like(
                "2%"
            ),
            2,
        ),
        (
            DailyTask.taskno.cast(
                String
            ).like(
                "3%"
            ),
            3,
        ),
        (
            DailyTask.taskno.cast(
                String
            ).like(
                "4%"
            ),
            4,
        ),
        (
            DailyTask.taskno.cast(
                String
            ).like(
                "5%"
            ),
            5,
        ),
        (
            DailyTask.taskno.cast(
                String
            ).like(
                "6%"
            ),
            6,
        ),
        (
            DailyTask.taskno.cast(
                String
            ).like(
                "7%"
            ),
            7,
        ),
        else_=8,
    )

def validate_time_value(
    value: str,
):
    try:
        datetime.strptime(
            value,
            "%H:%M",
        )

    except ValueError:
        return False

    return True


def validate_daily_task_values(
    title: str,
    details: str,
    environment: str,
    subenvironment: str,
    dependency: str,
    resource: str,
    time_value: str,
    effective_from: date,
    effective_to: Optional[date],
):
    if not title:
        return "Title is required."

    if not details:
        return (
            "Daily Task details "
            "are required."
        )

    if not environment:
        return "Environment is required."

    if not time_value:
        return "Time is required."

    if not validate_time_value(
        time_value
    ):
        return (
            "Time must be a valid "
            "24-hour HH:MM value."
        )

    if len(title) > 255:
        return (
            "Title cannot exceed "
            "255 characters."
        )

    if len(environment) > 10:
        return (
            "Environment cannot exceed "
            "10 characters."
        )

    if len(subenvironment) > 25:
        return (
            "Sub-environment cannot exceed "
            "25 characters."
        )

    if len(dependency) > 100:
        return (
            "Dependency cannot exceed "
            "100 characters."
        )

    if len(resource) > 20:
        return (
            "Resource cannot exceed "
            "20 characters."
        )

    if (
        effective_to is not None
        and effective_to < effective_from
    ):
        return (
            "Effective To cannot be "
            "earlier than Effective From."
        )

    return None


# ============================================================
# AUTOMATIC TASK-NUMBER ALLOCATION
#
# Every Day:
#     Allocate from 7 through 99.
#     Values 1 through 6 remain reserved for
#     migrated legacy EOX behavior.
#
# Specific weekday:
#     Use uf_availabletasknumbers().
#
# An advisory transaction lock prevents two concurrent
# Admin requests from receiving the same Task Number.
# ============================================================

def allocate_task_number(
    db: Session,
    environment: str,
    schedule: str,
):
    environment = normalize_environment(
        environment
    )

    if not is_valid_environment(
        environment
    ):
        raise HTTPException(
            status_code=400,
            detail=(
                "Environment must be Maestro, "
                "V21, or SDM."
            ),
        )
    if schedule not in VALID_SCHEDULE_VALUES:
        raise HTTPException(
            status_code=400,
            detail=(
                "Schedule must be Every Day "
                "or Monday through Sunday."
            ),
        )

    lock_key = "{}:{}".format(
        environment,
        schedule,
    )

    db.execute(
        text(
            """
            SELECT pg_advisory_xact_lock(
                hashtext(:lock_key)
            )
            """
        ),
        {
            "lock_key": lock_key,
        },
    )

    if schedule == "0":
        task_number = db.scalar(
            text(
                """
                SELECT candidate.taskno

                FROM generate_series(
                    7,
                    99
                ) AS candidate(taskno)

                WHERE NOT EXISTS (
                    SELECT 1

                    FROM dailytasks existing

                    WHERE existing.environment =
                          :environment

                      AND existing.taskno =
                          candidate.taskno
                )

                ORDER BY candidate.taskno

                LIMIT 1
                """
            ),
            {
                "environment":
                    environment,
            },
        )

    else:
        task_number = db.scalar(
            text(
                """
                SELECT taskno

                FROM uf_availabletasknumbers(
                    CAST(
                        :weekday
                        AS char(1)
                    ),
                    CAST(
                        :environment
                        AS varchar
                    )
                )

                ORDER BY taskno

                LIMIT 1
                """
            ),
            {
                "weekday": schedule,
                "environment": environment,
            },
        )

    if task_number is None:
        raise HTTPException(
            status_code=409,
            detail=(
                "No available Task Number "
                "was found for the selected "
                "environment and schedule."
            ),
        )

    return task_number


# ============================================================
# DAILY TASK LIST
# ============================================================

@router.get(
    "/daily-tasks",
    response_class=HTMLResponse,
)
def daily_tasks_page(
    request: Request,
    environment: Optional[str] = None,
    search: Optional[str] = None,
    schedule_status: Optional[str] = None,
    include_deleted: bool = False,
    page: int = 1,
    page_size: int = 50,
    task_added: bool = False,
    task_updated: bool = False,
    task_deleted: bool = False,
    task_restored: bool = False,
    db: Session = Depends(get_db),
):
    require_admin(request)

    page = max(
        page,
        1,
    )

    page_size = min(
        max(
            page_size,
            10,
        ),
        100,
    )

    filters = []

    if not include_deleted:
        filters.append(
            DailyTask.deleted.is_(False)
        )

    if environment:
        filters.append(
            DailyTask.environment
            == environment
        )

    if search:
        pattern = "%{}%".format(
            search.strip()
        )

        filters.append(
            or_(
                DailyTask.title.ilike(
                    pattern
                ),
                DailyTask.details.ilike(
                    pattern
                ),
                DailyTask.note.ilike(
                    pattern
                ),
                DailyTask.resource.ilike(
                    pattern
                ),
                DailyTask.dependency.ilike(
                    pattern
                ),
                DailyTask.taskno.cast(
                    String
                ).ilike(
                    pattern
                ),
            )
        )

    today = date.today()

    if schedule_status == "active":
        filters.extend(
            [
                DailyTask.deleted.is_(
                    False
                ),
                DailyTask.effective_from
                <= today,
                or_(
                    DailyTask.effective_to
                    .is_(None),

                    DailyTask.effective_to
                    >= today,
                ),
            ]
        )

    elif schedule_status == "future":
        filters.extend(
            [
                DailyTask.deleted.is_(
                    False
                ),
                DailyTask.effective_from
                > today,
            ]
        )

    elif schedule_status == "expired":
        filters.extend(
            [
                DailyTask.deleted.is_(
                    False
                ),
                DailyTask.effective_to
                .is_not(None),
                DailyTask.effective_to
                < today,
            ]
        )

    elif schedule_status == "deleted":
        filters.append(
            DailyTask.deleted.is_(
                True
            )
        )

    total_rows = db.scalar(
        select(
            func.count(
                DailyTask.serial
            )
        )
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

    tasks = db.scalars(
        select(DailyTask)
        .where(*filters)
        .order_by(
            daily_task_schedule_order().asc(),
            DailyTask.environment.asc(),
            DailyTask.time.asc(),
            DailyTask.taskno.asc(),
        )
        .offset(offset)
        .limit(page_size)
    ).all()

    task_rows = []

    for task in tasks:
        schedule_number = (
            derive_schedule_from_taskno(
                task.taskno
            )
        )

        task_rows.append(
            {
                "task": task,
                "schedule_number":
                    schedule_number,
                "weekday_number":
                    schedule_number,
                "schedule_name":
                    get_schedule_name(
                        schedule_number
                    ),
                "weekday_name":
                    get_schedule_name(
                        schedule_number
                    ),
                "schedule_status":
                    get_task_schedule_status(
                        task
                    ),
            }
        )

    current_list_url = request.url.path
    if request.url.query:
        current_list_url = f"{request.url.path}?{request.url.query}"

    return templates.TemplateResponse(
        request=request,
        name="daily_tasks.html",
        context={
            "current_list_url": current_list_url,
            "task_rows": task_rows,
            "tasks": tasks,
            "environments":
                get_environments(db),
            "selected_environment":
                environment or "",
            "selected_status":
                schedule_status or "",
            "search":
                search or "",
            "include_deleted":
                include_deleted,
            "page":
                page,
            "page_size":
                page_size,
            "total_rows":
                total_rows,
            "total_pages":
                total_pages,
            "task_added":
                task_added,
            "task_updated":
                task_updated,
            "task_deleted":
                task_deleted,
            "task_restored":
                task_restored,
        },
    )


# ============================================================
# ADD DAILY TASK FORM
# ============================================================

@router.get(
    "/daily-tasks/new",
    response_class=HTMLResponse,
)
def new_daily_task_page(
    request: Request,
    db: Session = Depends(get_db),
):
    require_admin(request)

    return templates.TemplateResponse(
        request=request,
        name="daily_task_new.html",
        context={
            "environments":
                get_environments(db),
            "weekdays":
                WEEKDAYS,
            "today":
                date.today().isoformat(),
            "error":
                None,
            "form":
                None,
        },
    )


# ============================================================
# CREATE DAILY TASK
#
# Task Number is automatically allocated based on:
#
# Environment + Schedule
#
# schedule = 0:
#     Every Day, using range 7 through 99.
#
# schedule = 1 through 7:
#     Specific weekday, using
#     uf_availabletasknumbers().
# ============================================================

@router.post(
    "/daily-tasks/new",
    response_class=HTMLResponse,
)
def create_daily_task(
    request: Request,

    environment: str = Form(...),
    weekday: str = Form(...),

    effective_from: date = Form(...),
    effective_to: Optional[date] = Form(
        None
    ),

    time: str = Form(...),
    title: str = Form(...),
    details: str = Form(...),

    note: str = Form(""),
    dependency: str = Form(""),
    subenvironment: str = Form(""),
    resource: str = Form(""),

    criticalact: Optional[str] = Form(
        None
    ),

    db: Session = Depends(get_db),
):
    admin = require_admin(request)

    environment_value = (
      normalize_environment(
        environment
      )
    )
    title_value = title.strip()
    details_value = details.strip()
    note_value = note.strip()

    subenvironment_value = (
        subenvironment.strip()
    )

    dependency_value = (
        dependency.strip()
    )

    resource_value = (
        resource.strip()
    )

    time_value = time.strip()

    form_values = {
        "environment":
            environment,
        "weekday":
            weekday,
        "effective_from":
            effective_from.isoformat(),
        "effective_to":
            (
                effective_to.isoformat()
                if effective_to
                else ""
            ),
        "time":
            time,
        "title":
            title,
        "details":
            details,
        "note":
            note,
        "dependency":
            dependency,
        "subenvironment":
            subenvironment,
        "resource":
            resource,
        "criticalact":
            criticalact == "true",
    }

    if not is_valid_environment(
        environment_value
    ):
        error = (
            "Environment must be Maestro, "
            "V21, or SDM."
        )
    else:
        error = validate_daily_task_values(
                title=title_value,
            details=details_value,
            environment=(
                environment_value
            ),
            subenvironment=(
                subenvironment_value
            ),
            dependency=(
                dependency_value
            ),
            resource=resource_value,
            time_value=time_value,
            effective_from=effective_from,
            effective_to=effective_to,
        )

    if weekday not in VALID_SCHEDULE_VALUES:
        error = (
            "A valid schedule is required."
        )

    if error:
        return templates.TemplateResponse(
            request=request,
            name="daily_task_new.html",
            status_code=400,
            context={
                "environments":
                    get_environments(db),
                "weekdays":
                    WEEKDAYS,
                "today":
                    date.today()
                    .isoformat(),
                "error":
                    error,
                "form":
                    form_values,
            },
        )

    try:
        task_number = allocate_task_number(
            db=db,
            environment=(
                environment_value
            ),
            schedule=weekday,
        )

        task = DailyTask(
            taskno=task_number,
            title=title_value,
            details=details_value,
            note=(
                note_value
                if note_value
                else None
            ),
            dependency=(
                dependency_value
                if dependency_value
                else None
            ),
            environment=(
                environment_value
            ),
            subenvironment=(
                subenvironment_value
            ),
            resource=(
                resource_value
                if resource_value
                else None
            ),
            time=time_value,
            criticalact=(
                criticalact == "true"
            ),
            deleted=False,
            effective_from=(
                effective_from
            ),
            effective_to=(
                effective_to
            ),
        )

        db.add(task)
        db.flush()

        write_audit(
            db=db,
            request=request,
            action="DAILY_TASK_CREATE",
            result="SUCCESS",
            user=admin,
            target_type="DAILY_TASK",
            target_id=task.serial,
            details=(
                "Task {}; environment {}; "
                "schedule {}; effective {} "
                "through {}".format(
                    task_number,
                    environment_value,
                    get_schedule_name(
                        weekday
                    ),
                    effective_from,
                    (
                        effective_to
                        if effective_to
                        else "open-ended"
                    ),
                )
            ),
        )

        db.commit()

    except IntegrityError:
        db.rollback()

        return templates.TemplateResponse(
            request=request,
            name="daily_task_new.html",
            status_code=409,
            context={
                "environments":
                    get_environments(db),
                "weekdays":
                    WEEKDAYS,
                "today":
                    date.today()
                    .isoformat(),
                "error": (
                    "The automatically allocated "
                    "Task Number conflicted with "
                    "an existing Daily Task. "
                    "Submit the form again to "
                    "allocate the next available "
                    "number."
                ),
                "form":
                    form_values,
            },
        )

    except SQLAlchemyError as exception:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail=(
                "Unable to create "
                "Daily Task."
            ),
        ) from exception

    return RedirectResponse(
        url=(
            "/web/daily-tasks"
            "?task_added=true"
            "&environment={}"
        ).format(
            environment_value
        ),
        status_code=303,
    )


# ============================================================
# DAILY TASK DETAIL / AUDIT HISTORY
# ============================================================

@router.get(
    "/daily-tasks/{serial}",
    response_class=HTMLResponse,
)
def daily_task_detail_page(
    request: Request,
    serial: int,
    return_url: Optional[str] = None,
    db: Session = Depends(get_db),
):
    get_current_user(request)
    return_url_value = daily_task_return_url(return_url)
    task = get_daily_task_or_404(db, serial)
    schedule_number = derive_schedule_from_taskno(task.taskno)
    audit_history = get_audit_history(
        db,
        AUDIT_TARGET_DAILY_TASK,
        task.serial,
    )
    return templates.TemplateResponse(
        request=request,
        name="daily_task_detail.html",
        context={
            "task": task,
            "return_url": return_url_value,
            "schedule_number": schedule_number,
            "weekday_name": get_schedule_name(schedule_number),
            "schedule_status": get_task_schedule_status(task),
            "audit_history": audit_history,
        },
    )


# ============================================================
# EDIT DAILY TASK FORM
# ============================================================

@router.get(
    "/daily-tasks/{serial}/edit",
    response_class=HTMLResponse,
)
def edit_daily_task_page(
    request: Request,
    serial: int,
    return_url: Optional[str] = None,
    db: Session = Depends(get_db),
):
    require_admin(request)
    return_url_value = daily_task_return_url(return_url)

    task = get_daily_task_or_404(
        db,
        serial,
    )

    schedule_number = (
        derive_schedule_from_taskno(
            task.taskno
        )
    )

    audit_history = get_audit_history(
        db,
        AUDIT_TARGET_DAILY_TASK,
        task.serial,
    )

    return templates.TemplateResponse(
        request=request,
        name="daily_task_edit.html",
        context={
            "audit_history": audit_history,
            "return_url": return_url_value,
            "task":
                task,
            "environments":
                get_environments(db),
            "schedule_number":
                schedule_number,
            "weekday_number":
                schedule_number,
            "schedule_name":
                get_schedule_name(
                    schedule_number
                ),
            "weekday_name":
                get_schedule_name(
                    schedule_number
                ),
            "schedule_status":
                get_task_schedule_status(
                    task
                ),
            "error":
                None,
        },
    )


# ============================================================
# UPDATE DAILY TASK
#
# Task Number, environment and schedule remain read-only.
# Moving a task to another schedule could change its legacy
# Task Number range, so a new task should be created instead.
# ============================================================

@router.post(
    "/daily-tasks/{serial}/edit",
    response_class=HTMLResponse,
)
def update_daily_task(
    request: Request,
    serial: int,

    return_url: str = Form("/web/daily-tasks"),
    effective_from: date = Form(...),
    effective_to: Optional[date] = Form(
        None
    ),

    time: str = Form(...),
    title: str = Form(...),
    details: str = Form(...),

    note: str = Form(""),
    dependency: str = Form(""),
    subenvironment: str = Form(""),
    resource: str = Form(""),

    criticalact: Optional[str] = Form(
        None
    ),

    db: Session = Depends(get_db),
):
    admin = require_admin(request)
    return_url_value = daily_task_return_url(return_url)

    task = get_daily_task_or_404(
        db,
        serial,
    )

    title_value = title.strip()
    details_value = details.strip()
    note_value = note.strip()

    subenvironment_value = (
        subenvironment.strip()
    )

    dependency_value = (
        dependency.strip()
    )

    resource_value = (
        resource.strip()
    )

    time_value = time.strip()

    error = validate_daily_task_values(
        title=title_value,
        details=details_value,
        environment=(
            task.environment
        ),
        subenvironment=(
            subenvironment_value
        ),
        dependency=(
            dependency_value
        ),
        resource=resource_value,
        time_value=time_value,
        effective_from=effective_from,
        effective_to=effective_to,
    )

    if error:
        db.rollback()

        task = get_daily_task_or_404(
            db,
            serial,
        )

        schedule_number = (
            derive_schedule_from_taskno(
                task.taskno
            )
        )

        return templates.TemplateResponse(
            request=request,
            name="daily_task_edit.html",
            status_code=400,
            context={
                "return_url": return_url_value,
                "task":
                    task,
                "environments":
                    get_environments(db),
                "schedule_number":
                    schedule_number,
                "weekday_number":
                    schedule_number,
                "schedule_name":
                    get_schedule_name(
                        schedule_number
                    ),
                "weekday_name":
                    get_schedule_name(
                        schedule_number
                    ),
                "schedule_status":
                    get_task_schedule_status(
                        task
                    ),
                "error":
                    error,
            },
        )

    changes = [
        ("Effective From", task.effective_from, effective_from),
        ("Effective To", task.effective_to, effective_to),
        ("Time", task.time, time_value),
        ("Title", task.title, title_value),
        ("Details", task.details, details_value),
        ("Notes", task.note, note_value or None),
        ("Dependency", task.dependency, dependency_value or None),
        ("Sub-environment", task.subenvironment, subenvironment_value),
        ("Resource", task.resource, resource_value or None),
        ("Critical", task.criticalact, criticalact == "true"),
    ]

    try:
        task.effective_from = (
            effective_from
        )

        task.effective_to = (
            effective_to
        )

        task.time = time_value
        task.title = title_value
        task.details = details_value

        task.note = (
            note_value
            if note_value
            else None
        )

        task.dependency = (
            dependency_value
            if dependency_value
            else None
        )

        task.subenvironment = (
            subenvironment_value
        )

        task.resource = (
            resource_value
            if resource_value
            else None
        )

        task.criticalact = (
            criticalact == "true"
        )

        write_audit(
            db=db,
            request=request,
            action="DAILY_TASK_UPDATE",
            result="SUCCESS",
            user=admin,
            target_type="DAILY_TASK",
            target_id=task.serial,
            details=(
                "Task {}; effective {} "
                "through {}".format(
                    task.taskno,
                    effective_from,
                    (
                        effective_to
                        if effective_to
                        else "open-ended"
                    ),
                )
            ),
        )

        db.commit()

    except IntegrityError:
        db.rollback()

        raise HTTPException(
            status_code=409,
            detail=(
                "The Daily Task update "
                "conflicts with existing data."
            ),
        )

    except SQLAlchemyError as exception:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail=(
                "Unable to update "
                "Daily Task."
            ),
        ) from exception

    separator = "&" if "?" in return_url_value else "?"
    return RedirectResponse(
        url=f"{return_url_value}{separator}task_updated=true",
        status_code=303,
    )


# ============================================================
# SOFT DELETE DAILY TASK
# ============================================================

@router.post(
    "/daily-tasks/{serial}/delete",
    response_class=RedirectResponse,
)
def delete_daily_task(
    request: Request,
    serial: int,
    return_url: str = Form("/web/daily-tasks"),
    db: Session = Depends(get_db),
):
    admin = require_admin(request)

    return_url_value = daily_task_return_url(return_url)
    task = get_daily_task_or_404(
        db,
        serial,
    )

    try:
        task.deleted = True

        write_audit(
            db=db,
            request=request,
            action="DAILY_TASK_DELETE",
            result="SUCCESS",
            user=admin,
            target_type="DAILY_TASK",
            target_id=task.serial,
            details=(
                "Task {}".format(
                    task.taskno
                )
            ),
        )

        db.commit()

    except SQLAlchemyError as exception:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail=(
                "Unable to delete "
                "Daily Task."
            ),
        ) from exception

    separator = "&" if "?" in return_url_value else "?"
    return RedirectResponse(
        url=f"{return_url_value}{separator}task_deleted=true",
        status_code=303,
    )


# ============================================================
# RESTORE DAILY TASK
# ============================================================

@router.post(
    "/daily-tasks/{serial}/restore",
    response_class=RedirectResponse,
)
def restore_daily_task(
    request: Request,
    serial: int,
    return_url: str = Form("/web/daily-tasks"),
    db: Session = Depends(get_db),
):
    admin = require_admin(request)

    return_url_value = daily_task_return_url(return_url)
    task = get_daily_task_or_404(
        db,
        serial,
    )

    try:
        task.deleted = False

        write_audit(
            db=db,
            request=request,
            action="DAILY_TASK_RESTORE",
            result="SUCCESS",
            user=admin,
            target_type="DAILY_TASK",
            target_id=task.serial,
            details=(
                "Task {}".format(
                    task.taskno
                )
            ),
        )

        db.commit()

    except SQLAlchemyError as exception:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail=(
                "Unable to restore "
                "Daily Task."
            ),
        ) from exception

    separator = "&" if "?" in return_url_value else "?"
    return RedirectResponse(
        url=f"{return_url_value}{separator}task_restored=true",
        status_code=303,
    )


# ============================================================
# PRODUCTION CONTROL PREVIEW
# ============================================================

@router.get(
    "/production-control",
    response_class=HTMLResponse,
)
def production_control_page(
    request: Request,
    environment: Optional[str] = None,
    schedule_date: Optional[date] = None,
    schedule_populated: bool = False,
    rolling_populated: bool = False,
    db: Session = Depends(get_db),
):
    get_current_user(request)

    preview_rows = []
    preview_error = None
    duplicate_count = 0
    weekday_number = None

    if environment and schedule_date:
        weekday_number = (
            schedule_date.isoweekday()
        )

        try:
            preview_rows = db.execute(
                text(
                    """
                    SELECT
                        taskno,
                        title,
                        details,
                        note,
                        dependency,
                        environment,
                        subenvironment,
                        resource,
                        est_time,
                        criticalact,
                        deleted

                    FROM
                        uf_autoeoxreplacedailylist(
                            CAST(
                                :environment
                                AS varchar
                            ),
                            CAST(
                                :schedule_date
                                AS timestamp
                            ),
                            CAST(
                                :weekday_number
                                AS char(1)
                            )
                        )

                    WHERE taskno IS NOT NULL
                      AND deleted = false

                    ORDER BY
                        est_time,
                        taskno
                    """
                ),
                {
                    "environment":
                        environment,
                    "schedule_date":
                        schedule_date,
                    "weekday_number":
                        str(
                            weekday_number
                        ),
                },
            ).mappings().all()

            duplicate_count = db.scalar(
                text(
                    """
                    SELECT COUNT(*)

                    FROM
                        uf_autoeoxreplacedailylist(
                            CAST(
                                :environment
                                AS varchar
                            ),
                            CAST(
                                :schedule_date
                                AS timestamp
                            ),
                            CAST(
                                :weekday_number
                                AS char(1)
                            )
                        ) generated

                    JOIN activities existing
                      ON existing.taskno =
                         generated.taskno

                     AND existing.est_time =
                         generated.est_time

                     AND existing.environment =
                         generated.environment

                    WHERE generated.taskno
                          IS NOT NULL

                      AND generated.deleted =
                          false
                    """
                ),
                {
                    "environment":
                        environment,
                    "schedule_date":
                        schedule_date,
                    "weekday_number":
                        str(
                            weekday_number
                        ),
                },
            ) or 0

        except SQLAlchemyError:
            db.rollback()

            preview_error = (
                "Unable to generate "
                "the schedule preview."
            )

    return templates.TemplateResponse(
        request=request,
        name="production_control.html",
        context={
            "environments":
                get_environments(db),
            "selected_environment":
                environment or "",
            "schedule_date":
                (
                    schedule_date.isoformat()
                    if schedule_date
                    else ""
                ),
            "weekday_number":
                weekday_number,
            "preview_rows":
                preview_rows,
            "preview_error":
                preview_error,
            "duplicate_count":
                duplicate_count,
            "schedule_populated":
                schedule_populated,
            "rolling_populated":
                rolling_populated,
        },
    )


# ============================================================
# POPULATE ONE SCHEDULE DATE
# ============================================================

@router.post(
    "/production-control/populate",
    response_class=RedirectResponse,
)
def populate_schedule(
    request: Request,
    environment: str = Form(...),
    schedule_date: date = Form(...),
    db: Session = Depends(get_db),
):
    admin = require_admin(request)

    environment_value = (
        normalize_environment(
            environment
        )
    )

    if not environment_value:
        raise HTTPException(
            status_code=400,
            detail="Environment is required.",
        )

    if not is_valid_environment(
        environment_value
    ):
        raise HTTPException(
            status_code=400,
            detail=(
                "Environment must be Maestro, "
                "V21, or SDM."
            ),
        )

    date_difference = (
        schedule_date
        - date.today()
    ).days

    if (
        date_difference < -32768
        or date_difference > 32767
    ):
        raise HTTPException(
            status_code=400,
            detail=(
                "Selected date is outside "
                "the supported range."
            ),
        )

    try:
        db.execute(
            text(
                """
                CALL
                    sp_automaticdailytaskpopulator(
                        CAST(
                            :environment
                            AS varchar
                        ),
                        CAST(
                            :date_difference
                            AS smallint
                        )
                    )
                """
            ),
            {
                "environment":
                    environment_value,
                "date_difference":
                    date_difference,
            },
        )

        write_audit(
            db=db,
            request=request,
            action="SCHEDULE_POPULATE",
            result="SUCCESS",
            user=admin,
            target_type="ENVIRONMENT",
            target_id=environment_value,
            details=(
                "Schedule date {}".format(
                    schedule_date
                )
            ),
        )

        db.commit()

    except SQLAlchemyError as exception:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail=(
                "Unable to populate "
                "the ASPEN schedule."
            ),
        ) from exception

    return RedirectResponse(
        url=(
            "/web/production-control"
            "?environment={}"
            "&schedule_date={}"
            "&schedule_populated=true"
        ).format(
            environment_value,
            schedule_date.isoformat(),
        ),
        status_code=303,
    )


# ============================================================
# POPULATE ROLLING SEVEN-DAY SCHEDULE
#
# Today through Today + 6.
#
# PostgreSQL handles:
# - Every Day and weekday-specific templates
# - effective-date filtering
# - EOX replacement
# - estimated-time calculation
# - duplicate protection
# ============================================================

@router.post(
    "/production-control/populate-seven-days",
    response_class=RedirectResponse,
)
def populate_seven_day_schedule(
    request: Request,
    environment: str = Form(...),
    db: Session = Depends(get_db),
):
    admin = require_admin(request)

    environment_value = (
        normalize_environment(
            environment
        )
    )

    if not environment_value:
        raise HTTPException(
            status_code=400,
            detail="Environment is required.",
        )

    if not is_valid_environment(
        environment_value
    ):
        raise HTTPException(
            status_code=400,
            detail=(
                "Environment must be Maestro, "
                "V21, or SDM."
            ),
        )

    try:
        for date_difference in range(
            0,
            7,
        ):
            db.execute(
                text(
                    """
                    CALL
                        sp_automaticdailytaskpopulator(
                            CAST(
                                :environment
                                AS varchar
                            ),
                            CAST(
                                :date_difference
                                AS smallint
                            )
                        )
                    """
                ),
                {
                    "environment":
                        environment_value,
                    "date_difference":
                        date_difference,
                },
            )

        write_audit(
            db=db,
            request=request,
            action=(
                "SEVEN_DAY_SCHEDULE_POPULATE"
            ),
            result="SUCCESS",
            user=admin,
            target_type="ENVIRONMENT",
            target_id=environment_value,
            details=(
                "{} through {}".format(
                    date.today(),
                    date.today()
                    + timedelta(days=6),
                )
            ),
        )

        db.commit()

    except SQLAlchemyError as exception:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail=(
                "Unable to populate the "
                "rolling seven-day schedule. "
                "The transaction was rolled "
                "back."
            ),
        ) from exception

    return RedirectResponse(
        url=(
            "/web/production-control"
            "?environment={}"
            "&schedule_date={}"
            "&rolling_populated=true"
        ).format(
            environment_value,
            date.today().isoformat(),
        ),
        status_code=303,
    )
