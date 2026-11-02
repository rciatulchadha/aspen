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
from sqlalchemy import text
from sqlalchemy.exc import (
    IntegrityError,
    SQLAlchemyError,
)
from sqlalchemy.orm import Session

from app.database import get_db
from app.security import write_audit


router = APIRouter(
    prefix="/web/admin",
    tags=["Administration"],
)

templates = Jinja2Templates(
    directory="app/templates"
)


# ============================================================
# HELPERS
# ============================================================

def require_admin(request):
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

    if not user.is_admin:
        raise HTTPException(
            status_code=403,
            detail="Admin access required",
        )

    return user


def next_id(
    db,
    table_name,
    column_name,
):
    allowed = {
        ("environment", "id"),
        ("environment_sub", "id"),
        ("statutoryholidays", "serial"),
        ("emailsubscriptions", "serial"),
        (
            "emailfromaddressandsignature",
            "serial",
        ),
        ("templatedactivities", "id"),
        ("infotaskno", "serial"),
        ("opsreportstatuscolour", "id"),
    }

    if (
        table_name,
        column_name,
    ) not in allowed:
        raise ValueError(
            "Unsupported identity target"
        )

    sql = """
        SELECT
            COALESCE(
                MAX({}),
                0
            ) + 1
        FROM {}
    """.format(
        column_name,
        table_name,
    )

    return db.scalar(
        text(sql)
    )


# ============================================================
# ADMIN HOME
# ============================================================

@router.get(
    "",
    response_class=HTMLResponse,
)
def admin_home(
    request: Request,
):
    require_admin(request)

    return templates.TemplateResponse(
        request=request,
        name="admin_home.html",
        context={},
    )


# ============================================================
# ENVIRONMENTS
# ============================================================

@router.get(
    "/environments",
    response_class=HTMLResponse,
)
def environments_page(
    request: Request,
    message: str = "",
    db: Session = Depends(get_db),
):
    require_admin(request)

    environments = db.execute(
        text(
            """
            SELECT
                e.id,
                e.description,
                e.dbkey,
                e.commandline,
                e.tasklength,

                pc.timeend,
                pc.fromdatediff
                    AS pc_fromdatediff,
                pc.todatediff
                    AS pc_todatediff,
                pc.reporttitle,
                pc.reporttimefrom,
                pc.reporttimeto,
                pc.reportdrafttime,
                pc.reportfinaltime,

                ops.sortorder
                    AS ops_sortorder,
                ops.billenabled,
                ops.colourstart,
                ops.colourend,
                ops.fromdatediff
                    AS ops_fromdatediff,
                ops.fromtime,
                ops.todatediff
                    AS ops_todatediff,
                ops.totime,
                ops.activitiestable

            FROM environment e

            LEFT JOIN environment_pc pc
              ON pc.environmentid = e.id

            LEFT JOIN environment_ops ops
              ON ops.environmentid = e.id

            ORDER BY
                e.description
            """
        )
    ).mappings().all()

    subenvironments = db.execute(
        text(
            """
            SELECT
                s.id,
                s.envid,
                e.description
                    AS environment,
                s.description,
                s.sortorder
            FROM environment_sub s
            JOIN environment e
              ON e.id = s.envid
            ORDER BY
                e.description,
                s.sortorder,
                s.description
            """
        )
    ).mappings().all()

    return templates.TemplateResponse(
        request=request,
        name="admin_environments.html",
        context={
            "environments":
                environments,
            "subenvironments":
                subenvironments,
            "message":
                message,
        },
    )


@router.post(
    "/environments/{environment_id}/update",
    response_class=RedirectResponse,
)
def update_environment(
    request: Request,
    environment_id: int,

    description: str = Form(...),
    dbkey: str = Form(...),
    commandline: str = Form(""),
    tasklength: int = Form(...),

    db: Session = Depends(get_db),
):
    admin = require_admin(request)

    description_value = (
        description.strip()
    )

    dbkey_value = (
        dbkey.strip()
    )

    if not description_value:
        raise HTTPException(
            status_code=400,
            detail="Description is required",
        )

    if not dbkey_value:
        raise HTTPException(
            status_code=400,
            detail="Database key is required",
        )

    if len(description_value) > 50:
        raise HTTPException(
            status_code=400,
            detail=(
                "Description cannot exceed "
                "50 characters"
            ),
        )

    if len(dbkey_value) > 10:
        raise HTTPException(
            status_code=400,
            detail=(
                "Database key cannot exceed "
                "10 characters"
            ),
        )

    if tasklength <= 0:
        raise HTTPException(
            status_code=400,
            detail=(
                "Task length must be greater "
                "than zero"
            ),
        )

    try:
        result = db.execute(
            text(
                """
                UPDATE environment
                SET
                    description =
                        :description,
                    dbkey =
                        :dbkey,
                    commandline =
                        NULLIF(
                            :commandline,
                            ''
                        ),
                    tasklength =
                        :tasklength
                WHERE id =
                    :environment_id
                """
            ),
            {
                "environment_id":
                    environment_id,
                "description":
                    description_value,
                "dbkey":
                    dbkey_value,
                "commandline":
                    commandline.strip(),
                "tasklength":
                    tasklength,
            },
        )

        if result.rowcount == 0:
            raise HTTPException(
                status_code=404,
                detail=(
                    "Environment not found"
                ),
            )

        write_audit(
            db=db,
            request=request,
            action=(
                "ENVIRONMENT_UPDATE"
            ),
            result="SUCCESS",
            user=admin,
            target_type="ENVIRONMENT",
            target_id=environment_id,
            details=dbkey_value,
        )

        db.commit()

    except IntegrityError as exception:
        db.rollback()

        raise HTTPException(
            status_code=409,
            detail=(
                "Environment update "
                "conflicts with existing data"
            ),
        ) from exception

    return RedirectResponse(
        url=(
            "/web/admin/environments"
            "?message=Environment+updated"
        ),
        status_code=303,
    )


# ============================================================
# SUB-ENVIRONMENTS
# ============================================================

@router.post(
    "/subenvironments/add",
    response_class=RedirectResponse,
)
def add_subenvironment(
    request: Request,
    environment_id: int = Form(...),
    description: str = Form(...),
    sortorder: int = Form(...),
    db: Session = Depends(get_db),
):
    admin = require_admin(request)

    value = description.strip()

    if not value:
        raise HTTPException(
            status_code=400,
            detail=(
                "Sub-environment description "
                "is required"
            ),
        )

    if len(value) > 25:
        raise HTTPException(
            status_code=400,
            detail=(
                "Sub-environment cannot "
                "exceed 25 characters"
            ),
        )

    new_id = next_id(
        db,
        "environment_sub",
        "id",
    )

    db.execute(
        text(
            """
            INSERT INTO environment_sub (
                id,
                envid,
                description,
                sortorder
            )
            VALUES (
                :id,
                :envid,
                :description,
                :sortorder
            )
            """
        ),
        {
            "id": new_id,
            "envid": environment_id,
            "description": value,
            "sortorder": sortorder,
        },
    )

    write_audit(
        db=db,
        request=request,
        action="SUBENVIRONMENT_CREATE",
        result="SUCCESS",
        user=admin,
        target_type="SUBENVIRONMENT",
        target_id=new_id,
        details=value,
    )

    db.commit()

    return RedirectResponse(
        url=(
            "/web/admin/environments"
            "?message=Sub-environment+added"
        ),
        status_code=303,
    )


# ============================================================
# HOLIDAYS
# ============================================================

@router.get(
    "/holidays",
    response_class=HTMLResponse,
)
def holidays_page(
    request: Request,
    message: str = "",
    db: Session = Depends(get_db),
):
    require_admin(request)

    rows = db.execute(
        text(
            """
            SELECT
                serial,
                holiday,
                reason
            FROM statutoryholidays
            ORDER BY holiday
            """
        )
    ).mappings().all()

    return templates.TemplateResponse(
        request=request,
        name="admin_holidays.html",
        context={
            "rows": rows,
            "message": message,
        },
    )


@router.post(
    "/holidays/add",
    response_class=RedirectResponse,
)
def holiday_add(
    request: Request,
    holiday: datetime = Form(...),
    reason: str = Form(...),
    db: Session = Depends(get_db),
):
    admin = require_admin(request)

    reason_value = reason.strip()

    if not reason_value:
        raise HTTPException(
            status_code=400,
            detail="Reason is required",
        )

    if len(reason_value) > 50:
        raise HTTPException(
            status_code=400,
            detail=(
                "Reason cannot exceed "
                "50 characters"
            ),
        )

    serial = next_id(
        db,
        "statutoryholidays",
        "serial",
    )

    db.execute(
        text(
            """
            INSERT INTO statutoryholidays (
                serial,
                holiday,
                reason
            )
            VALUES (
                :serial,
                :holiday,
                :reason
            )
            """
        ),
        {
            "serial": serial,
            "holiday": holiday,
            "reason": reason_value,
        },
    )

    write_audit(
        db=db,
        request=request,
        action="HOLIDAY_CREATE",
        result="SUCCESS",
        user=admin,
        target_type="HOLIDAY",
        target_id=serial,
        details=reason_value,
    )

    db.commit()

    return RedirectResponse(
        url=(
            "/web/admin/holidays"
            "?message=Holiday+added"
        ),
        status_code=303,
    )


@router.post(
    "/holidays/{serial}/delete",
    response_class=RedirectResponse,
)
def holiday_delete(
    request: Request,
    serial: int,
    db: Session = Depends(get_db),
):
    admin = require_admin(request)

    db.execute(
        text(
            """
            DELETE FROM statutoryholidays
            WHERE serial = :serial
            """
        ),
        {
            "serial": serial,
        },
    )

    write_audit(
        db=db,
        request=request,
        action="HOLIDAY_DELETE",
        result="SUCCESS",
        user=admin,
        target_type="HOLIDAY",
        target_id=serial,
    )

    db.commit()

    return RedirectResponse(
        url=(
            "/web/admin/holidays"
            "?message=Holiday+deleted"
        ),
        status_code=303,
    )


# ============================================================
# EMAIL SUBSCRIPTIONS
# ============================================================

@router.get(
    "/email-subscriptions",
    response_class=HTMLResponse,
)
def email_subscriptions_page(
    request: Request,
    message: str = "",
    db: Session = Depends(get_db),
):
    require_admin(request)

    subscriptions = db.execute(
        text(
            """
            SELECT *
            FROM emailsubscriptions
            ORDER BY username
            """
        )
    ).mappings().all()

    email_config = db.execute(
        text(
            """
            SELECT *
            FROM emailfromaddressandsignature
            ORDER BY department
            """
        )
    ).mappings().all()

    return templates.TemplateResponse(
        request=request,
        name=(
            "admin_email_subscriptions.html"
        ),
        context={
            "subscriptions":
                subscriptions,
            "email_config":
                email_config,
            "message":
                message,
        },
    )


@router.post(
    "/email-subscriptions/add",
    response_class=RedirectResponse,
)
def email_subscription_add(
    request: Request,

    username: str = Form(...),
    emailaddress: str = Form(...),

    v21billingfyi: Optional[str] = Form(
        None
    ),
    v21opsdaily: Optional[str] = Form(
        None
    ),
    v21opsweekend: Optional[str] = Form(
        None
    ),
    v21spooling: Optional[str] = Form(
        None
    ),
    cableops: Optional[str] = Form(
        None
    ),
    nbudrp: Optional[str] = Form(
        None
    ),

    db: Session = Depends(get_db),
):
    admin = require_admin(request)

    username_value = username.strip()
    email_value = (
        emailaddress.strip()
    )

    serial = next_id(
        db,
        "emailsubscriptions",
        "serial",
    )

    db.execute(
        text(
            """
            INSERT INTO emailsubscriptions (
                serial,
                username,
                emailaddress,
                v21billingfyi,
                v21opsdaily,
                v21opsweekend,
                v21spooling,
                cableops,
                nbudrp
            )
            VALUES (
                :serial,
                :username,
                :emailaddress,
                :v21billingfyi,
                :v21opsdaily,
                :v21opsweekend,
                :v21spooling,
                :cableops,
                :nbudrp
            )
            """
        ),
        {
            "serial": serial,
            "username":
                username_value,
            "emailaddress":
                email_value,
            "v21billingfyi":
                v21billingfyi
                == "true",
            "v21opsdaily":
                v21opsdaily
                == "true",
            "v21opsweekend":
                v21opsweekend
                == "true",
            "v21spooling":
                v21spooling
                == "true",
            "cableops":
                cableops == "true",
            "nbudrp":
                nbudrp == "true",
        },
    )

    write_audit(
        db=db,
        request=request,
        action=(
            "EMAIL_SUBSCRIPTION_CREATE"
        ),
        result="SUCCESS",
        user=admin,
        target_type=(
            "EMAIL_SUBSCRIPTION"
        ),
        target_id=serial,
        details=email_value,
    )

    db.commit()

    return RedirectResponse(
        url=(
            "/web/admin/"
            "email-subscriptions"
            "?message=Subscription+added"
        ),
        status_code=303,
    )


# ============================================================
# TEMPLATED ACTIVITIES
# ============================================================

@router.get(
    "/templates",
    response_class=HTMLResponse,
)
def templates_page(
    request: Request,
    message: str = "",
    db: Session = Depends(get_db),
):
    require_admin(request)

    rows = db.execute(
        text(
            """
            SELECT
                id,
                tasknumber,
                environment
            FROM templatedactivities
            ORDER BY
                environment,
                tasknumber
            """
        )
    ).mappings().all()

    environments = db.execute(
        text(
            """
            SELECT dbkey
            FROM environment
            ORDER BY dbkey
            """
        )
    ).scalars().all()

    return templates.TemplateResponse(
        request=request,
        name="admin_templates.html",
        context={
            "rows": rows,
            "environments":
                environments,
            "message":
                message,
        },
    )


@router.post(
    "/templates/add",
    response_class=RedirectResponse,
)
def template_add(
    request: Request,
    tasknumber: str = Form(...),
    environment: str = Form(...),
    db: Session = Depends(get_db),
):
    admin = require_admin(request)

    task_value = tasknumber.strip()
    env_value = environment.strip()

    if not task_value:
        raise HTTPException(
            status_code=400,
            detail="Task number is required",
        )

    if len(task_value) > 5:
        raise HTTPException(
            status_code=400,
            detail=(
                "Template task number "
                "cannot exceed 5 characters"
            ),
        )

    new_id = next_id(
        db,
        "templatedactivities",
        "id",
    )

    db.execute(
        text(
            """
            INSERT INTO templatedactivities (
                id,
                tasknumber,
                environment
            )
            VALUES (
                :id,
                :tasknumber,
                :environment
            )
            """
        ),
        {
            "id": new_id,
            "tasknumber": task_value,
            "environment": env_value,
        },
    )

    write_audit(
        db=db,
        request=request,
        action="TEMPLATE_CREATE",
        result="SUCCESS",
        user=admin,
        target_type=(
            "TEMPLATED_ACTIVITY"
        ),
        target_id=new_id,
        details=(
            "{} / {}".format(
                env_value,
                task_value,
            )
        ),
    )

    db.commit()

    return RedirectResponse(
        url=(
            "/web/admin/templates"
            "?message=Template+added"
        ),
        status_code=303,
    )


@router.post(
    "/templates/{template_id}/delete",
    response_class=RedirectResponse,
)
def delete_template(
    request: Request,
    template_id: int,
    db: Session = Depends(get_db),
):
    admin = require_admin(request)

    db.execute(
        text(
            """
            DELETE FROM templatedactivities
            WHERE id = :id
            """
        ),
        {
            "id": template_id,
        },
    )

    write_audit(
        db=db,
        request=request,
        action="TEMPLATE_DELETE",
        result="SUCCESS",
        user=admin,
        target_type=(
            "TEMPLATED_ACTIVITY"
        ),
        target_id=template_id,
    )

    db.commit()

    return RedirectResponse(
        url=(
            "/web/admin/templates"
            "?message=Template+deleted"
        ),
        status_code=303,
    )


# ============================================================
# TASK NUMBERS
# ============================================================

@router.get(
    "/task-numbers",
    response_class=HTMLResponse,
)
def task_numbers_page(
    request: Request,
    message: str = "",
    db: Session = Depends(get_db),
):
    require_admin(request)

    rows = db.execute(
        text(
            """
            SELECT
                serial,
                weekday,
                environment,
                taskno
            FROM infotaskno
            ORDER BY
                environment,
                weekday
            """
        )
    ).mappings().all()

    environments = db.execute(
        text(
            """
            SELECT dbkey
            FROM environment
            ORDER BY dbkey
            """
        )
    ).scalars().all()

    return templates.TemplateResponse(
        request=request,
        name="admin_task_numbers.html",
        context={
            "rows": rows,
            "environments":
                environments,
            "message":
                message,
        },
    )


@router.post(
    "/task-numbers/{serial}/update",
    response_class=RedirectResponse,
)
def task_number_update(
    request: Request,
    serial: int,
    taskno: int = Form(...),
    db: Session = Depends(get_db),
):
    admin = require_admin(request)

    db.execute(
        text(
            """
            UPDATE infotaskno
            SET taskno = :taskno
            WHERE serial = :serial
            """
        ),
        {
            "taskno": taskno,
            "serial": serial,
        },
    )

    write_audit(
        db=db,
        request=request,
        action=(
            "TASK_NUMBER_UPDATE"
        ),
        result="SUCCESS",
        user=admin,
        target_type="INFOTASKNO",
        target_id=serial,
        details=str(taskno),
    )

    db.commit()

    return RedirectResponse(
        url=(
            "/web/admin/task-numbers"
            "?message=Task+number+updated"
        ),
        status_code=303,
    )


# ============================================================
# STATUS COLOURS
# ============================================================

@router.get(
    "/status-colours",
    response_class=HTMLResponse,
)
def status_colours_page(
    request: Request,
    message: str = "",
    db: Session = Depends(get_db),
):
    require_admin(request)

    rows = db.execute(
        text(
            """
            SELECT
                id,
                status,
                colour
            FROM opsreportstatuscolour
            ORDER BY id
            """
        )
    ).mappings().all()

    return templates.TemplateResponse(
        request=request,
        name="admin_status_colours.html",
        context={
            "rows": rows,
            "message": message,
        },
    )


@router.post(
    "/status-colours/{status_id}/update",
    response_class=RedirectResponse,
)
def status_colour_update(
    request: Request,
    status_id: int,
    colour: str = Form(...),
    db: Session = Depends(get_db),
):
    admin = require_admin(request)

    colour_value = (
        colour.strip()
    )

    if len(colour_value) > 7:
        raise HTTPException(
            status_code=400,
            detail=(
                "Colour value cannot "
                "exceed 7 characters"
            ),
        )

    db.execute(
        text(
            """
            UPDATE opsreportstatuscolour
            SET colour = :colour
            WHERE id = :id
            """
        ),
        {
            "colour":
                colour_value,
            "id":
                status_id,
        },
    )

    write_audit(
        db=db,
        request=request,
        action="STATUS_COLOUR_UPDATE",
        result="SUCCESS",
        user=admin,
        target_type="STATUS_COLOUR",
        target_id=status_id,
        details=colour_value,
    )

    db.commit()

    return RedirectResponse(
        url=(
            "/web/admin/status-colours"
            "?message=Status+colour+updated"
        ),
        status_code=303,
    )
