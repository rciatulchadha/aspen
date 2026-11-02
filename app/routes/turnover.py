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
from sqlalchemy import select, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Activity


router = APIRouter(
    prefix="/web/turnover",
    tags=["Turnover"],
)

templates = Jinja2Templates(
    directory="app/templates"
)


# ============================================================
# HELPERS
# ============================================================

def get_turnover_environments(db):
    return db.execute(
        text(
            """
            SELECT
                id,
                sortorder,
                description
            FROM turnoverenvironment
            ORDER BY sortorder, description
            """
        )
    ).mappings().all()


def get_turnover_subenvironments(db):
    return db.execute(
        text(
            """
            SELECT
                id,
                environmentid,
                sortorder,
                description
            FROM turnoversubenvironment
            ORDER BY
                environmentid,
                sortorder,
                description
            """
        )
    ).mappings().all()


# ============================================================
# TURNOVER ACTIVITY LIST
# ============================================================

@router.get(
    "",
    response_class=HTMLResponse,
)
def turnover_page(
    request: Request,
    environment: Optional[str] = None,
    activity_added: bool = False,
    db: Session = Depends(get_db),
):
    sql = """
        SELECT
            ta.serial,
            ta.activityid,
            a.taskno,
            a.est_time,
            a.title,
            a.status,
            te.description
                AS environment,
            tse.description
                AS subenvironment,
            ta.comments,
            ta.eoxdate

        FROM turnoveractivities ta

        JOIN activities a
          ON a.id = ta.activityid

        JOIN turnoverenvironment te
          ON te.id = ta.environmentid

        LEFT JOIN turnoversubenvironment tse
          ON tse.id = ta.subenvid

        WHERE
            (
                CAST(:environment AS varchar)
                IS NULL

                OR te.description
                   = CAST(
                       :environment
                       AS varchar
                     )
            )

        ORDER BY
            te.sortorder,
            a.est_time,
            a.taskno
    """

    environment_value = (
        environment
        if environment
        else None
    )

    rows = db.execute(
        text(sql),
        {
            "environment":
                environment_value,
        },
    ).mappings().all()

    return templates.TemplateResponse(
        request=request,
        name="turnover.html",
        context={
            "rows": rows,
            "environments": (
                get_turnover_environments(db)
            ),
            "selected_environment": (
                environment or ""
            ),
            "activity_added":
                activity_added,
        },
    )


# ============================================================
# ADD ACTIVITY TO TURNOVER
# ============================================================

@router.get(
    "/add",
    response_class=HTMLResponse,
)
def add_turnover_page(
    request: Request,
    activity_id: Optional[int] = None,
    db: Session = Depends(get_db),
):
    activity = None

    if activity_id is not None:
        activity = db.get(
            Activity,
            activity_id,
        )

        if activity is None:
            raise HTTPException(
                status_code=404,
                detail=(
                    "Activity not found"
                ),
            )

    recent_activities = db.scalars(
        select(Activity)
        .where(
            Activity.deleted.is_(False)
        )
        .order_by(
            Activity.est_time.desc()
        )
        .limit(100)
    ).all()

    return templates.TemplateResponse(
        request=request,
        name="turnover_add.html",
        context={
            "activity": activity,
            "activities":
                recent_activities,
            "environments": (
                get_turnover_environments(
                    db
                )
            ),
            "subenvironments": (
                get_turnover_subenvironments(
                    db
                )
            ),
            "error": None,
        },
    )


@router.post(
    "/add",
    response_class=HTMLResponse,
)
def add_turnover_activity(
    request: Request,
    activity_id: int = Form(...),
    environment: str = Form(...),
    subenvironment: str = Form(""),
    comments: str = Form(""),
    eoxdate: Optional[datetime] = Form(
        None
    ),
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

    environment_value = (
        environment.strip()
    )

    subenvironment_value = (
        subenvironment.strip()
    )

    comments_value = comments.strip()

    if not environment_value:
        raise HTTPException(
            status_code=400,
            detail=(
                "Turnover Environment "
                "is required."
            ),
        )

    duplicate = db.scalar(
        text(
            """
            SELECT COUNT(*)
            FROM turnoveractivities
            WHERE activityid =
                  :activity_id
            """
        ),
        {
            "activity_id":
                activity_id,
        },
    )

    if duplicate:
        return templates.TemplateResponse(
            request=request,
            name="turnover_add.html",
            status_code=409,
            context={
                "activity": activity,
                "activities": [],
                "environments": (
                    get_turnover_environments(
                        db
                    )
                ),
                "subenvironments": (
                    get_turnover_subenvironments(
                        db
                    )
                ),
                "error": (
                    "This Activity is "
                    "already part of "
                    "Turnover."
                ),
            },
        )

    try:
        db.execute(
            text(
                """
                CALL sp_addtoturnover(
                    :activity_id,
                    CAST(
                        :environment
                        AS varchar(50)
                    ),
                    CAST(
                        NULLIF(
                            :subenvironment,
                            ''
                        )
                        AS varchar(50)
                    ),
                    CAST(
                        NULLIF(
                            :comments,
                            ''
                        )
                        AS text
                    ),
                    CAST(
                        :eoxdate
                        AS timestamp
                    )
                )
                """
            ),
            {
                "activity_id":
                    activity_id,
                "environment":
                    environment_value,
                "subenvironment":
                    subenvironment_value,
                "comments":
                    comments_value,
                "eoxdate":
                    eoxdate,
            },
        )

        db.commit()

    except SQLAlchemyError as exception:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail=(
                "Unable to add "
                "Activity to Turnover."
            ),
        ) from exception

    return RedirectResponse(
        url=(
            "/web/turnover"
            "?activity_added=true"
        ),
        status_code=303,
    )


# ============================================================
# MPS
# ============================================================

@router.get(
    "/mps",
    response_class=HTMLResponse,
)
def turnover_mps_page(
    request: Request,
    mps_added: bool = False,
    db: Session = Depends(get_db),
):
    current_mps = db.execute(
        text(
            """
            SELECT *
            FROM vw_turnovermps
            """
        )
    ).mappings().first()

    current_cycles = db.execute(
        text(
            """
            SELECT *
            FROM vw_turnovermpscurrentcycles
            """
        )
    ).mappings().all()

    history = db.execute(
        text(
            """
            SELECT
                m.id,
                m.collections,
                m.maindrivers,
                m.guiders,
                m.mpupappgdtime,
                m.premaf1date,
                m.premaf1status,
                m.premaf4date,
                m.premaf4status,
                m.cibervolser1,
                m.cibervolser2,
                m.cibervolser3,
                COUNT(c.id)
                    AS cycle_count

            FROM turnovermps m

            LEFT JOIN
                turnovermpscycles c
              ON c.mpsid = m.id

            GROUP BY
                m.id,
                m.collections,
                m.maindrivers,
                m.guiders,
                m.mpupappgdtime,
                m.premaf1date,
                m.premaf1status,
                m.premaf4date,
                m.premaf4status,
                m.cibervolser1,
                m.cibervolser2,
                m.cibervolser3

            ORDER BY
                m.id DESC

            LIMIT 25
            """
        )
    ).mappings().all()

    return templates.TemplateResponse(
        request=request,
        name="turnover_mps.html",
        context={
            "current_mps":
                current_mps,
            "current_cycles":
                current_cycles,
            "history": history,
            "mps_added":
                mps_added,
        },
    )


# ============================================================
# NEW MPS
# ============================================================

@router.get(
    "/mps/new",
    response_class=HTMLResponse,
)
def new_turnover_mps_page(
    request: Request,
):
    return templates.TemplateResponse(
        request=request,
        name="turnover_mps_new.html",
        context={
            "error": None,
        },
    )


@router.post(
    "/mps/new",
    response_class=HTMLResponse,
)
def create_turnover_mps(
    request: Request,
    collections: int = Form(...),
    maindrivers: int = Form(...),
    guiders: int = Form(...),
    mpupappgdtime: datetime = Form(...),

    cycle1: str = Form(...),
    cycle2: str = Form(""),
    cycle3: str = Form(""),
    cycle4: str = Form(""),
    cycle5: str = Form(""),
    cycle6: str = Form(""),

    premaf1date: Optional[
        datetime
    ] = Form(None),

    premaf1status: str = Form(""),

    premaf4date: Optional[
        datetime
    ] = Form(None),

    premaf4status: str = Form(""),

    volser1: str = Form(""),
    volser2: str = Form(""),
    volser3: str = Form(""),

    db: Session = Depends(get_db),
):
    cycle_values = [
        cycle1.strip(),
        cycle2.strip(),
        cycle3.strip(),
        cycle4.strip(),
        cycle5.strip(),
        cycle6.strip(),
    ]

    if collections < 0:
        error = (
            "Collections cannot "
            "be negative."
        )

    elif maindrivers < 0:
        error = (
            "Maindrivers cannot "
            "be negative."
        )

    elif guiders < 0:
        error = (
            "Guiders cannot "
            "be negative."
        )

    elif not cycle_values[0]:
        error = (
            "Cycle 1 is required."
        )

    elif any(
        len(value) > 150
        for value in cycle_values
    ):
        error = (
            "Cycle details cannot "
            "exceed 150 characters."
        )

    elif any(
        len(value.strip()) > 7
        for value in (
            volser1,
            volser2,
            volser3,
        )
    ):
        error = (
            "VOLSER values cannot "
            "exceed 7 characters."
        )

    else:
        error = None

    if error:
        return templates.TemplateResponse(
            request=request,
            name="turnover_mps_new.html",
            status_code=400,
            context={
                "error": error,
            },
        )

    try:
        db.execute(
            text(
                """
                CALL sp_addturnovermps(
                    :collections,
                    :maindrivers,
                    :guiders,

                    CAST(
                        :mpupappgdtime
                        AS timestamp
                    ),

                    CAST(
                        :cycle1
                        AS varchar(150)
                    ),
                    CAST(
                        :cycle2
                        AS varchar(150)
                    ),
                    CAST(
                        :cycle3
                        AS varchar(150)
                    ),
                    CAST(
                        :cycle4
                        AS varchar(150)
                    ),
                    CAST(
                        :cycle5
                        AS varchar(150)
                    ),
                    CAST(
                        :cycle6
                        AS varchar(150)
                    ),

                    CAST(
                        :premaf1date
                        AS timestamp
                    ),

                    CAST(
                        NULLIF(
                            :premaf1status,
                            ''
                        )
                        AS varchar(100)
                    ),

                    CAST(
                        :premaf4date
                        AS timestamp
                    ),

                    CAST(
                        NULLIF(
                            :premaf4status,
                            ''
                        )
                        AS varchar(100)
                    ),

                    CAST(
                        NULLIF(
                            :volser1,
                            ''
                        )
                        AS varchar(7)
                    ),

                    CAST(
                        NULLIF(
                            :volser2,
                            ''
                        )
                        AS varchar(7)
                    ),

                    CAST(
                        NULLIF(
                            :volser3,
                            ''
                        )
                        AS varchar(7)
                    )
                )
                """
            ),
            {
                "collections":
                    collections,
                "maindrivers":
                    maindrivers,
                "guiders":
                    guiders,
                "mpupappgdtime":
                    mpupappgdtime,

                "cycle1":
                    cycle_values[0],
                "cycle2":
                    cycle_values[1],
                "cycle3":
                    cycle_values[2],
                "cycle4":
                    cycle_values[3],
                "cycle5":
                    cycle_values[4],
                "cycle6":
                    cycle_values[5],

                "premaf1date":
                    premaf1date,
                "premaf1status":
                    premaf1status.strip(),

                "premaf4date":
                    premaf4date,
                "premaf4status":
                    premaf4status.strip(),

                "volser1":
                    volser1.strip(),
                "volser2":
                    volser2.strip(),
                "volser3":
                    volser3.strip(),
            },
        )

        db.commit()

    except SQLAlchemyError as exception:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail=(
                "Unable to create "
                "Turnover MPS record."
            ),
        ) from exception

    return RedirectResponse(
        url=(
            "/web/turnover/mps"
            "?mps_added=true"
        ),
        status_code=303,
    )
