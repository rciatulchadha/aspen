import io
from datetime import date, datetime, time
from typing import Optional

import xlsxwriter
from fastapi import APIRouter, Depends, Query, Request
from fastapi.responses import HTMLResponse, StreamingResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy import String, or_, select, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.database import get_db
from app.environments import (
    ASPEN_ENVIRONMENTS,
    is_valid_environment,
    normalize_environment,
)
from app.models import Activity

router = APIRouter(prefix="/web/reports", tags=["Reports"])
templates = Jinja2Templates(directory="app/templates")


def get_environments(db):
    return ASPEN_ENVIRONMENTS


def start_of_day(value):
    return datetime.combine(value, time.min) if value else None


def end_of_day(value):
    return datetime.combine(value, time.max) if value else None


def clean_report_text(value):
    return "" if value is None else str(value).rstrip()


def build_rocc_report_statement(environment, date_from, date_to, search):
    statement = select(
        Activity.id.label("activity_id"),
        Activity.taskno.label("task"),
        Activity.est_time.label("activity_time"),
        Activity.title.label("activity_title"),
        Activity.details.label("activity_details"),
        Activity.note.label("note"),
        Activity.dependency.label("dependency"),
        Activity.resource.label("resource"),
    ).where(
        Activity.deleted.is_(False),
        Activity.est_time >= date_from,
        Activity.est_time <= date_to,
    )
    if environment:
        statement = statement.where(Activity.environment == environment)
    search_value = search.strip() if search else ""
    if search_value:
        pattern = f"%{search_value}%"
        statement = statement.where(
            or_(
                Activity.taskno.cast(String).ilike(pattern),
                Activity.title.ilike(pattern),
                Activity.details.ilike(pattern),
                Activity.note.ilike(pattern),
                Activity.dependency.ilike(pattern),
                Activity.resource.ilike(pattern),
            )
        )
    return statement.order_by(
        Activity.est_time.asc(),
        Activity.taskno.asc(),
        Activity.id.asc(),
    )


def normalize_rocc_report_rows(rows):
    return [
        {
            "activity_id": row.activity_id,
            "task": row.task,
            "activity_time": row.activity_time,
            "activity_title": clean_report_text(row.activity_title),
            "activity_details": clean_report_text(row.activity_details),
            "note": clean_report_text(row.note),
            "dependency": clean_report_text(row.dependency),
            "resource": clean_report_text(row.resource),
        }
        for row in rows
    ]


def create_rocc_excel(rows, environment, date_from, date_to):
    output = io.BytesIO()
    workbook = xlsxwriter.Workbook(output, {"in_memory": True})
    worksheet = workbook.add_worksheet("Operations Report")
    title_format = workbook.add_format({
        "bold": True, "font_size": 16, "font_color": "#FFFFFF",
        "bg_color": "#1F4E78", "align": "left", "valign": "vcenter",
    })
    subtitle_format = workbook.add_format({
        "font_color": "#404040", "bg_color": "#D9EAF7",
        "align": "left", "valign": "vcenter",
    })
    header_format = workbook.add_format({
        "bold": True, "font_color": "#FFFFFF", "bg_color": "#2F75B5",
        "border": 1, "align": "center", "valign": "vcenter",
        "text_wrap": True,
    })
    text_format = workbook.add_format({"border": 1, "valign": "top"})
    wrapped_format = workbook.add_format({
        "border": 1, "valign": "top", "text_wrap": True,
    })
    datetime_format = workbook.add_format({
        "border": 1, "valign": "top", "num_format": "yyyy-mm-dd hh:mm",
    })
    worksheet.merge_range("A1:G1", "ASPEN Operations Report", title_format)
    worksheet.merge_range(
        "A2:G2",
        "Environment: {} | Date/time range: {} through {}".format(
            environment or "All",
            date_from.strftime("%Y-%m-%d %H:%M"),
            date_to.strftime("%Y-%m-%d %H:%M"),
        ),
        subtitle_format,
    )
    headers = [
        "Task", "Time", "Activity Title", "Activity Details",
        "Note", "Dependency", "Resource",
    ]
    header_row = 3
    for column, header in enumerate(headers):
        worksheet.write(header_row, column, header, header_format)
    for row_number, row in enumerate(rows, start=header_row + 1):
        worksheet.write(row_number, 0, row["task"], text_format)
        if row["activity_time"]:
            worksheet.write_datetime(
                row_number, 1, row["activity_time"], datetime_format
            )
        else:
            worksheet.write(row_number, 1, "", datetime_format)
        worksheet.write(row_number, 2, row["activity_title"], wrapped_format)
        worksheet.write(row_number, 3, row["activity_details"], wrapped_format)
        worksheet.write(row_number, 4, row["note"], wrapped_format)
        worksheet.write(row_number, 5, row["dependency"], text_format)
        worksheet.write(row_number, 6, row["resource"], text_format)
    last_row = max(header_row, header_row + len(rows))
    worksheet.autofilter(header_row, 0, last_row, len(headers) - 1)
    worksheet.freeze_panes(header_row + 1, 0)
    worksheet.set_column("A:A", 10)
    worksheet.set_column("B:B", 18)
    worksheet.set_column("C:C", 32)
    worksheet.set_column("D:D", 50)
    worksheet.set_column("E:E", 36)
    worksheet.set_column("F:F", 20)
    worksheet.set_column("G:G", 20)
    worksheet.set_row(0, 26)
    worksheet.set_row(3, 30)
    workbook.close()
    output.seek(0)
    return output


@router.get("", response_class=HTMLResponse)
def reports_home(request: Request):
    return templates.TemplateResponse(
        request=request, name="reports_home.html", context={}
    )


@router.get("/rocc", response_class=HTMLResponse)
def rocc_report(
    request: Request,
    environment: Optional[str] = None,
    date_from: Optional[datetime] = None,
    date_to: Optional[datetime] = None,
    search: Optional[str] = None,
    output_format: str = Query(default="html", alias="format"),
    db: Session = Depends(get_db),
):
    rows = []
    error = None
    selected_environment = (
        normalize_environment(environment) if environment else ""
    )
    search_value = search.strip() if search else ""
    report_requested = date_from is not None and date_to is not None
    if selected_environment and not is_valid_environment(selected_environment):
        error = "Environment must be All, Maestro, V21, or SDM."
    elif report_requested and date_from > date_to:
        error = "The From date/time cannot be later than the To date/time."
    elif report_requested:
        try:
            statement = build_rocc_report_statement(
                selected_environment or None,
                date_from,
                date_to,
                search_value,
            )
            database_rows = db.execute(statement).mappings().all()
            rows = normalize_rocc_report_rows(database_rows)
        except SQLAlchemyError:
            db.rollback()
            error = "Unable to generate the Operations report."
    context = {
        "environments": get_environments(db),
        "environment": selected_environment,
        "date_from": date_from.strftime("%Y-%m-%dT%H:%M") if date_from else "",
        "date_to": date_to.strftime("%Y-%m-%dT%H:%M") if date_to else "",
        "search": search_value,
        "rows": rows,
        "error": error,
        "report_requested": report_requested,
    }
    if output_format.lower() == "xlsx":
        if error:
            return templates.TemplateResponse(
                request=request,
                name="report_rocc.html",
                status_code=400,
                context=context,
            )
        if not report_requested:
            context["error"] = (
                "Select a From date/time and To date/time before downloading Excel."
            )
            return templates.TemplateResponse(
                request=request,
                name="report_rocc.html",
                status_code=400,
                context=context,
            )
        excel_file = create_rocc_excel(
            rows, selected_environment or None, date_from, date_to
        )
        filename = "aspen-activities-{}-to-{}.xlsx".format(
            date_from.strftime("%Y%m%d-%H%M"),
            date_to.strftime("%Y%m%d-%H%M"),
        )
        return StreamingResponse(
            excel_file,
            media_type=(
                "application/vnd.openxmlformats-officedocument."
                "spreadsheetml.sheet"
            ),
            headers={
                "Content-Disposition": f'attachment; filename="{filename}"'
            },
        )
    return templates.TemplateResponse(
        request=request,
        name="report_rocc.html",
        context=context,
    )


@router.get("/archive", response_class=HTMLResponse)
def archive_report(
    request: Request,
    environment: Optional[str] = None,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    db: Session = Depends(get_db),
):
    rows = []
    error = None
    if environment and date_from and date_to:
        try:
            rows = db.execute(
                text("""
                    SELECT * FROM uf_roccarchivereport(
                        CAST(:environment AS varchar(10)),
                        CAST(:date_from AS timestamp),
                        CAST(:date_to AS timestamp)
                    )
                    ORDER BY est_time, taskno, time_started
                """),
                {
                    "environment": environment,
                    "date_from": start_of_day(date_from),
                    "date_to": end_of_day(date_to),
                },
            ).mappings().all()
        except SQLAlchemyError:
            db.rollback()
            error = "Unable to generate the Archive report."
    return templates.TemplateResponse(
        request=request,
        name="report_archive.html",
        context={
            "environments": get_environments(db),
            "environment": environment or "",
            "date_from": date_from.isoformat() if date_from else "",
            "date_to": date_to.isoformat() if date_to else "",
            "rows": rows,
            "error": error,
        },
    )


@router.get("/sreq", response_class=HTMLResponse)
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
    if environment and date_from and date_to:
        function_name = (
            "uf_roccsreqarchivereport" if archive else "uf_roccsreqreport"
        )
        statement = """
            SELECT * FROM {}(
                CAST(:environment AS varchar(10)),
                CAST(:date_from AS timestamp),
                CAST(:date_to AS timestamp)
            )
            ORDER BY est_time, taskno, time_started
        """.format(function_name)
        try:
            rows = db.execute(
                text(statement),
                {
                    "environment": environment,
                    "date_from": start_of_day(date_from),
                    "date_to": end_of_day(date_to),
                },
            ).mappings().all()
        except SQLAlchemyError:
            db.rollback()
            error = "Unable to generate the SREQ report."
    return templates.TemplateResponse(
        request=request,
        name="report_sreq.html",
        context={
            "environments": get_environments(db),
            "environment": environment or "",
            "date_from": date_from.isoformat() if date_from else "",
            "date_to": date_to.isoformat() if date_to else "",
            "archive": archive,
            "rows": rows,
            "error": error,
        },
    )


@router.get("/billing", response_class=HTMLResponse)
def billing_report(
    request: Request,
    report_date: Optional[datetime] = None,
    hour_range: int = 24,
    db: Session = Depends(get_db),
):
    rows = []
    error = None
    hour_range = min(max(hour_range, 1), 168)
    if report_date:
        try:
            rows = db.execute(
                text("""
                    SELECT * FROM uf_roccbillingfyireport(
                        CAST(:report_date AS timestamp), :hour_range
                    )
                    ORDER BY systimeentered, title
                """),
                {"report_date": report_date, "hour_range": hour_range},
            ).mappings().all()
        except SQLAlchemyError:
            db.rollback()
            error = "Unable to generate the Billing FYI report."
    return templates.TemplateResponse(
        request=request,
        name="report_billing.html",
        context={
            "report_date": (
                report_date.strftime("%Y-%m-%dT%H:%M") if report_date else ""
            ),
            "hour_range": hour_range,
            "rows": rows,
            "error": error,
        },
    )


@router.get("/sla", response_class=HTMLResponse)
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
    task_prefix = task_prefix.strip() if task_prefix else "1"
    if len(task_prefix) > 1:
        task_prefix = task_prefix[0]
    difference = max(difference, 0)
    if environment and report_date:
        try:
            rows = db.execute(
                text("""
                    SELECT * FROM uf_slaexceptionreport(
                        CAST(:task_prefix AS char(1)),
                        CAST(:report_date AS timestamp),
                        CAST(:environment AS varchar(10)),
                        :difference
                    )
                    ORDER BY difference DESC, est_time, taskno
                """),
                {
                    "task_prefix": task_prefix,
                    "report_date": datetime.combine(report_date, time.min),
                    "environment": environment,
                    "difference": difference,
                },
            ).mappings().all()
        except SQLAlchemyError:
            db.rollback()
            error = "Unable to generate the SLA Exception report."
    return templates.TemplateResponse(
        request=request,
        name="report_sla.html",
        context={
            "environments": get_environments(db),
            "environment": environment or "",
            "report_date": report_date.isoformat() if report_date else "",
            "task_prefix": task_prefix,
            "difference": difference,
            "rows": rows,
            "error": error,
        },
    )
