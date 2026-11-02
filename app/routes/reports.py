from datetime import date, datetime, time, timedelta
from typing import Optional

from fastapi import (
    APIRouter,
    Depends,
    Request,
)
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy import select, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.database import get_db
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

def get_environments(db):
    return db.scalars(
        select(Activity.environment)
        .distinct()
        .order_by(Activity.environment)
    ).all()


def start_of_day(value):
    if value is None:
        return None

    return datetime.combine(
        value,
        time.min,
    )


def end_of_day(value):
    if value is None:
        return None

    return datetime.combine(
        value,
        time.max,
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
# ROCC REPORT
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
    db: Session = Depends(get_db),
):
    rows = []
    error = None

    if (
        environment
        and date_from
        and date_to
    ):
        from_value = start_of_day(
            date_from
        )

        to_value = end_of_day(
            date_to
        )

        try:
            if search and search.strip():

                rows = db.execute(
                    text(
                        """
                        SELECT *
                        FROM uf_roccreportsearch(
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
                            ),
                            CAST(
                                :search
                                AS varchar(50)
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
                            from_value,
                        "date_to":
                            to_value,
                        "search":
                            search.strip(),
                    },
                ).mappings().all()

            else:

                rows = db.execute(
                    text(
                        """
                        SELECT *
                        FROM uf_roccreport(
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
                            from_value,
                        "date_to":
                            to_value,
                    },
                ).mappings().all()

        except SQLAlchemyError:
            db.rollback()

            error = (
                "Unable to generate "
                "the ROCC report."
            )

    return templates.TemplateResponse(
        request=request,
        name="report_rocc.html",
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
            "search":
                search or "",
            "rows":
                rows,
            "error":
                error,
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
