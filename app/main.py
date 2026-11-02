from fastapi import (
    FastAPI,
    Request,
)
from fastapi.responses import (
    HTMLResponse,
    RedirectResponse,
)
from fastapi.staticfiles import (
    StaticFiles,
)
from fastapi.templating import (
    Jinja2Templates,
)
from sqlalchemy import text
from starlette.middleware.base import (
    BaseHTTPMiddleware,
)
from starlette.middleware.sessions import (
    SessionMiddleware,
)

from app.api.activities import (
    router as activities_api_router,
)

from app.config import settings

from app.database import (
    SessionLocal,
    engine,
)

from app.rbac import (
    allowed_roles_for_request,
    is_public_path,
)

from app.routes.admin_config import (
    router as admin_config_router,
)

from app.routes.admin_security import (
    router as admin_security_router,
)

from app.routes.auth import (
    router as auth_router,
)

from app.routes.daily_tasks import (
    router as daily_tasks_router,
)

from app.routes.reports import (
    router as reports_router,
)

from app.routes.turnover import (
    router as turnover_router,
)

from app.routes.web import (
    router as web_router,
)

from app.security import (
    load_session_user,
    write_audit,
)

from app.routes.admin_users import (
    router as admin_users_router,
)
# ============================================================
# APPLICATION
# ============================================================

app = FastAPI(
    title="ASPEN",
    description=(
        "Modern web replacement for "
        "the legacy ASPEN/VSR application"
    ),
    version="0.7.0",
)


# ============================================================
# STATIC FILES
# ============================================================

app.mount(
    "/static",
    StaticFiles(
        directory="app/static"
    ),
    name="static",
)


templates = Jinja2Templates(
    directory="app/templates"
)


# ============================================================
# AUTHENTICATION / AUTHORIZATION MIDDLEWARE
# ============================================================

async def authentication_and_rbac(
    request: Request,
    call_next,
):
    path = request.url.path


    # --------------------------------------------------------
    # PUBLIC PATHS
    #
    # Login, logout, health, change-password and static files.
    #
    # change-password performs its own session validation.
    # --------------------------------------------------------

    if is_public_path(
        path
    ):
        return await call_next(
            request
        )


    # --------------------------------------------------------
    # LOAD SIGNED ASPEN SESSION
    # --------------------------------------------------------

    user = load_session_user(
        request
    )


    request.state.user = user


    # --------------------------------------------------------
    # NOT AUTHENTICATED
    # --------------------------------------------------------

    if user is None:

        return RedirectResponse(
            url="/login",
            status_code=303,
        )


    # --------------------------------------------------------
    # MANDATORY PASSWORD CHANGE
    #
    # A newly created local user or a user whose password
    # was reset by Admin receives no application access until
    # the temporary password has been replaced.
    # --------------------------------------------------------

    if (
        user.must_change_password
        and path not in {
            "/change-password",
            "/logout",
        }
    ):

        return RedirectResponse(
            url="/change-password",
            status_code=303,
        )


    # --------------------------------------------------------
    # ROLE AUTHORIZATION
    # --------------------------------------------------------

    allowed_roles = (
        allowed_roles_for_request(
            request.method,
            path,
        )
    )


    if user.role not in allowed_roles:

        try:

            with SessionLocal() as db:

                write_audit(
                    db=db,
                    request=request,
                    action="ACCESS_DENIED",
                    result="DENIED",
                    user=user,
                    target_type="ROUTE",
                    target_id=path,
                    details=request.method,
                )

                db.commit()

        except Exception:
            # An audit failure must not accidentally
            # grant access to the protected route.
            pass


        return templates.TemplateResponse(
            request=request,
            name="forbidden.html",
            status_code=403,
            context={},
        )


    # --------------------------------------------------------
    # AUTHORIZED REQUEST
    # --------------------------------------------------------

    return await call_next(
        request
    )


# ============================================================
# MIDDLEWARE ORDER
#
# Starlette middleware wraps in reverse registration order.
#
# RBAC is registered first.
# SessionMiddleware is registered second.
#
# Therefore SessionMiddleware wraps RBAC and request.session
# exists before authentication_and_rbac() executes.
# ============================================================

app.add_middleware(
    BaseHTTPMiddleware,
    dispatch=authentication_and_rbac,
)


app.add_middleware(
    SessionMiddleware,

    secret_key=(
        settings.session_secret
    ),

    session_cookie=(
        "aspen_session"
    ),

    max_age=(
        settings
        .session_max_age_seconds
    ),

    same_site="lax",

    https_only=(
        settings
        .session_https_only
    ),
)


# ============================================================
# DASHBOARD
# ============================================================

@app.get(
    "/",
    response_class=HTMLResponse,
)
def dashboard(
    request: Request,
):
    return templates.TemplateResponse(
        request=request,
        name="dashboard.html",
        context={},
    )


# ============================================================
# HEALTH
#
# Remains unauthenticated so this can later be used by
# OpenShift liveness/readiness monitoring.
# ============================================================

@app.get(
    "/health"
)
def health():

    with engine.connect() as connection:

        result = connection.execute(
            text(
                """
                SELECT
                    current_database()
                        AS database,

                    current_user
                        AS username,

                    COUNT(*)
                        AS activity_count

                FROM activities
                """
            )
        ).one()


    return {

        "status":
            "healthy",

        "database":
            result.database,

        "database_user":
            result.username,

        "activity_count":
            result.activity_count,
    }


# ============================================================
# ROUTERS
# ============================================================

app.include_router(
    auth_router
)


app.include_router(
    activities_api_router
)


app.include_router(
    web_router
)


app.include_router(
    daily_tasks_router
)


app.include_router(
    turnover_router
)


app.include_router(
    reports_router
)


app.include_router(
    admin_security_router
)


app.include_router(
    admin_config_router
)

app.include_router(
    admin_users_router
)
