import csv
import io

from datetime import date, datetime, time, timedelta
from typing import Optional

from fastapi import (
    APIRouter,
    Depends,
    Query,
    Request,
)
from fastapi.responses import (
    HTMLResponse,
    StreamingResponse,
)
from fastapi.templating import Jinja2Templates
from sqlalchemy import (
    String,
    or_,
    select,
    text,
)
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.database import get_db
from app.environments import (
    ASPEN_ENVIRONMENTS,
    is_valid_environment,
    normalize_environment,
)
from app.models import Activity

router = APIRouter(
    prefix="/web/reports",
    tags=["Reports"],
)

templates = Jinja2Templates(
    directory="app/templates"
)


# ============================================================
# HELPERS
# ============================================================

def get_environments(
    db,
):
    return ASPEN_ENVIRONMENTS

def start_of_day(value):
    if value is None:
        return None

    return datetime.combine(
        value,
        time.min,
    )


def next_day_start(
    value,
):
    if value is None:
        return None

    return datetime.combine(
        value + timedelta(days=1),
        time.min,
    )


def build_rocc_report_statement(
    environment,
    date_from,
    date_to,
    search,
):
    from_value = start_of_day(
        date_from
    )

    to_exclusive = next_day_start(
        date_to
    )

    statement = (
        select(
            Activity.id.label(
                "activity_id"
            ),
            Activity.taskno.label(
                "task"
            ),
            Activity.est_time.label(
                "activity_time"
            ),
            Activity.title.label(
                "activity_title"
            ),
            Activity.details.label(
                "activity_details"
            ),
            Activity.note.label(
                "note"
            ),
            Activity.dependency.label(
                "dependency"
            ),
            Activity.resource.label(
                "resource"
            ),
        )
        .where(
            Activity.deleted.is_(False),
            Activity.est_time >= from_value,
            Activity.est_time < to_exclusive,
        )
    )

    if environment:
        statement = statement.where(
            Activity.environment
            == environment
        )

    search_value = (
        search.strip()
        if search
        else ""
    )

    if search_value:
        pattern = "%{}%".format(
            search_value
        )

        statement = statement.where(
            or_(
                Activity.taskno.cast(
                    String
                ).ilike(
                    pattern
                ),
                Activity.title.ilike(
                    pattern
                ),
                Activity.details.ilike(
                    pattern
                ),
                Activity.note.ilike(
                    pattern
                ),
                Activity.dependency.ilike(
                    pattern
                ),
                Activity.resource.ilike(
                    pattern
                ),
            )
        )

    return statement.order_by(
        Activity.est_time.asc(),
        Activity.taskno.asc(),
        Activity.id.asc(),
    )


def create_rocc_csv(
    rows,
):
    output = io.StringIO(
        newline=""
    )

    writer = csv.writer(
        output,
        quoting=csv.QUOTE_MINIMAL,
        lineterminator="\r\n",
    )

    writer.writerow(
        [
            "Task",
            "Time",
            "Activity Title",
            "Activity Details",
            "Note",
            "Dependency",
            "Resource",
        ]
    )

    for row in rows:
        writer.writerow(
            [
                row.task,

                (
                    row.activity_time.strftime(
                        "%Y-%m-%d %H:%M"
                    )
                    if row.activity_time
                    else ""
                ),

                row.activity_title or "",
                row.activity_details or "",
                row.note or "",
                row.dependency or "",
                row.resource or "",
            ]
        )

    # UTF-8 BOM helps Microsoft Excel identify UTF-8 CSV
    # files without showing special characters incorrectly.
    return "\ufeff{}".format(
        output.getvalue()
    )

# ============================================================
# REPORT HOME
# ============================================================

@router.get(
    "",
    response_class=HTMLResponse,
)
def reports_home(
    request: Request,
):
    return templates.TemplateResponse(
        request=request,
        name="reports_home.html",
        context={},
    )


# ============================================================
# ============================================================
# ROCC OPERATIONS REPORT
#
# Uses activities directly instead of the legacy reporting
# functions.
#
# Date behavior:
#
#   date_from >= 00:00:00
#   date_to   <  next day 00:00:00
#
# This includes every Activity on the selected end date.
# ============================================================

@router.get(
    "/rocc",
    response_class=HTMLResponse,
)
def rocc_report(
    request: Request,

    environment: Optional[str] = None,

    date_from: Optional[date] = None,

    date_to: Optional[date] = None,

    search: Optional[str] = None,

    output_format: str = Query(
        default="html",
        alias="format",
    ),

    db: Session = Depends(
        get_db
    ),
):
    rows = []
    error = None

    selected_environment = (
        normalize_environment(
            environment
        )
        if environment
        else ""
    )

    search_value = (
        search.strip()
        if search
        else ""
    )

    report_requested = (
        date_from is not None
        and date_to is not None
    )

    if (
        selected_environment
        and not is_valid_environment(
            selected_environment
        )
    ):
        error = (
            "Environment must be All, "
            "Maestro, V21, or SDM."
        )

    elif (
        report_requested
        and date_from > date_to
    ):
        error = (
            "The From date cannot be "
            "later than the To date."
        )

    elif report_requested:
        try:
            statement = (
                build_rocc_report_statement(
                    environment=(
                        selected_environment
                        or None
                    ),
                    date_from=date_from,
                    date_to=date_to,
                    search=search_value,
                )
            )

            rows = db.execute(
                statement
            ).mappings().all()

        except SQLAlchemyError:
            db.rollback()

            error = (
                "Unable to generate "
                "the Operations report."
            )

    if (
        output_format.lower()
        == "csv"
    ):
        if error:
            return templates.TemplateResponse(
                request=request,
                name="report_rocc.html",
                status_code=400,
                context={
                    "environments":
                        get_environments(db),

                    "environment":
                        selected_environment,

                    "date_from":
                        (
                            date_from.isoformat()
                            if date_from
                            else ""
                        ),

                    "date_to":
                        (
                            date_to.isoformat()
                            if date_to
                            else ""
                        ),

                    "search":
                        search_value,

                    "rows":
                        rows,

                    "error":
                        error,

                    "report_requested":
                        report_requested,
                },
            )

        if not report_requested:
            return templates.TemplateResponse(
                request=request,
                name="report_rocc.html",
                status_code=400,
                context={
                    "environments":
                        get_environments(db),

                    "environment":
                        selected_environment,

                    "date_from":
                        "",

                    "date_to":
                        "",

                    "search":
                        search_value,

                    "rows":
                        [],

                    "error": (
                        "Select a From date and "
                        "To date before downloading "
                        "the CSV report."
                    ),

                    "report_requested":
                        False,
                },
            )

        csv_content = create_rocc_csv(
            rows
        )

        filename = (
            "aspen-activities-"
            "{}-to-{}.csv"
        ).format(
            date_from.isoformat(),
            date_to.isoformat(),
        )

        return StreamingResponse(
            iter(
                [
                    csv_content
                ]
            ),
            media_type=(
                "text/csv; "
                "charset=utf-8"
            ),
            headers={
                "Content-Disposition": (
                    'attachment; filename="{}"'
                ).format(
                    filename
                ),
            },
        )

    return templates.TemplateResponse(
        request=request,
        name="report_rocc.html",
        context={
            "environments":
                get_environments(db),

            "environment":
                selected_environment,

            "date_from":
                (
                    date_from.isoformat()
                    if date_from
                    else ""
                ),

            "date_to":
                (
                    date_to.isoformat()
                    if date_to
                    else ""
                ),

            "search":
                search_value,

            "rows":
                rows,

            "error":
                error,

            "report_requested":
                report_requested,
        },
    )

# ============================================================
# ARCHIVE REPORT
# ============================================================

@router.get(
    "/archive",
    response_class=HTMLResponse,
)
def archive_report(
    request: Request,
    environment: Optional[str] = None,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    db: Session = Depends(get_db),
):
    rows = []
    error = None

    if (
        environment
        and date_from
        and date_to
    ):
        try:
            rows = db.execute(
                text(
                    """
                    SELECT *
                    FROM uf_roccarchivereport(
                        CAST(
                            :environment
                            AS varchar(10)
                        ),
                        CAST(
                            :date_from
                            AS timestamp
                        ),
                        CAST(
                            :date_to
                            AS timestamp
                        )
                    )
                    ORDER BY
                        est_time,
                        taskno,
                        time_started
                    """
                ),
                {
                    "environment":
                        environment,
                    "date_from":
                        start_of_day(
                            date_from
                        ),
                    "date_to":
                        end_of_day(
                            date_to
                        ),
                },
            ).mappings().all()

        except SQLAlchemyError:
            db.rollback()

            error = (
                "Unable to generate "
                "the Archive report."
            )

    return templates.TemplateResponse(
        request=request,
        name="report_archive.html",
        context={
            "environments":
                get_environments(db),
            "environment":
                environment or "",
            "date_from":
                date_from.isoformat()
                if date_from
                else "",
            "date_to":
                date_to.isoformat()
                if date_to
                else "",
            "rows":
                rows,
            "error":
                error,
        },
    )


# ============================================================
# SREQ REPORT
# ============================================================

@router.get(
    "/sreq",
    response_class=HTMLResponse,
)
def sreq_report(
    request: Request,
    environment: Optional[str] = None,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    archive: bool = False,
    db: Session = Depends(get_db),
):
    rows = []
    error = None

    if (
        environment
        and date_from
        and date_to
    ):
        function_name = (
            "uf_roccsreqarchivereport"
            if archive
            else "uf_roccsreqreport"
        )

        statement = """
            SELECT *
            FROM {}(
                CAST(
                    :environment
                    AS varchar(10)
                ),
                CAST(
                    :date_from
                    AS timestamp
                ),
                CAST(
                    :date_to
                    AS timestamp
                )
            )
            ORDER BY
                est_time,
                taskno,
                time_started
        """.format(
            function_name
        )

        try:
            rows = db.execute(
                text(statement),
                {
                    "environment":
                        environment,
                    "date_from":
                        start_of_day(
                            date_from
                        ),
                    "date_to":
                        end_of_day(
                            date_to
                        ),
                },
            ).mappings().all()

        except SQLAlchemyError:
            db.rollback()

            error = (
                "Unable to generate "
                "the SREQ report."
            )

    return templates.TemplateResponse(
        request=request,
        name="report_sreq.html",
        context={
            "environments":
                get_environments(db),
            "environment":
                environment or "",
            "date_from":
                date_from.isoformat()
                if date_from
                else "",
            "date_to":
                date_to.isoformat()
                if date_to
                else "",
            "archive":
                archive,
            "rows":
                rows,
            "error":
                error,
        },
    )


# ============================================================
# BILLING FYI
# ============================================================

@router.get(
    "/billing",
    response_class=HTMLResponse,
)
def billing_report(
    request: Request,
    report_date: Optional[
        datetime
    ] = None,
    hour_range: int = 24,
    db: Session = Depends(get_db),
):
    rows = []
    error = None

    if hour_range < 1:
        hour_range = 1

    if hour_range > 168:
        hour_range = 168

    if report_date:
        try:
            rows = db.execute(
                text(
                    """
                    SELECT *
                    FROM uf_roccbillingfyireport(
                        CAST(
                            :report_date
                            AS timestamp
                        ),
                        :hour_range
                    )
                    ORDER BY
                        systimeentered,
                        title
                    """
                ),
                {
                    "report_date":
                        report_date,
                    "hour_range":
                        hour_range,
                },
            ).mappings().all()

        except SQLAlchemyError:
            db.rollback()

            error = (
                "Unable to generate "
                "the Billing FYI report."
            )

    return templates.TemplateResponse(
        request=request,
        name="report_billing.html",
        context={
            "report_date":
                (
                    report_date.strftime(
                        "%Y-%m-%dT%H:%M"
                    )
                    if report_date
                    else ""
                ),
            "hour_range":
                hour_range,
            "rows":
                rows,
            "error":
                error,
        },
    )


# ============================================================
# SLA EXCEPTIONS
# ============================================================

@router.get(
    "/sla",
    response_class=HTMLResponse,
)
def sla_report(
    request: Request,
    environment: Optional[str] = None,
    report_date: Optional[date] = None,
    task_prefix: str = "1",
    difference: int = 0,
    db: Session = Depends(get_db),
):
    rows = []
    error = None

    task_prefix = (
        task_prefix.strip()
        if task_prefix
        else "1"
    )

    if len(task_prefix) > 1:
        task_prefix = (
            task_prefix[0]
        )

    if difference < 0:
        difference = 0

    if (
        environment
        and report_date
    ):
        try:
            rows = db.execute(
                text(
                    """
                    SELECT *
                    FROM uf_slaexceptionreport(
                        CAST(
                            :task_prefix
                            AS char(1)
                        ),
                        CAST(
                            :report_date
                            AS timestamp
                        ),
                        CAST(
                            :environment
                            AS varchar(10)
                        ),
                        :difference
                    )
                    ORDER BY
                        difference DESC,
                        est_time,
                        taskno
                    """
                ),
                {
                    "task_prefix":
                        task_prefix,
                    "report_date":
                        datetime.combine(
                            report_date,
                            time.min,
                        ),
                    "environment":
                        environment,
                    "difference":
                        difference,
                },
            ).mappings().all()

        except SQLAlchemyError:
            db.rollback()

            error = (
                "Unable to generate "
                "the SLA Exception report."
            )

    return templates.TemplateResponse(
        request=request,
        name="report_sla.html",
        context={
            "environments":
                get_environments(db),
            "environment":
                environment or "",
            "report_date":
                report_date.isoformat()
                if report_date
                else "",
            "task_prefix":
                task_prefix,
            "difference":
                difference,
            "rows":
                rows,
            "error":
                error,
        },
    )
