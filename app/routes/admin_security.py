from datetime import datetime, timedelta

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
from app.security import (
    ROLE_OPERATOR,
    ROLE_READER,
    hash_password,
    normalize_username,
    write_audit,
)


router = APIRouter(
    prefix="/web/admin/security",
    tags=["Administration"],
)

templates = Jinja2Templates(
    directory="app/templates"
)


def get_current_user(request):
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


def load_emergency_mode(db):
    row = db.execute(
        text(
            """
            SELECT
                enabled,
                enabled_at,
                enabled_by,
                expires_at,
                reason,
                disabled_at,
                disabled_by
            FROM app_emergency_mode
            WHERE id = 1
            """
        )
    ).mappings().first()

    return row


def load_local_users(db):
    return db.execute(
        text(
            """
            SELECT
                id,
                username,
                display_name,
                role,
                enabled,
                emergency_admin,
                expires_at,
                failed_attempts,
                locked_until,
                last_login_at,
                created_at,
                created_by
            FROM app_local_users
            ORDER BY
                emergency_admin DESC,
                username
            """
        )
    ).mappings().all()


# ============================================================
# SECURITY ADMIN HOME
# ============================================================

@router.get(
    "",
    response_class=HTMLResponse,
)
def security_admin_page(
    request: Request,
    message: str = "",
    db: Session = Depends(get_db),
):
    get_current_user(request)

    return templates.TemplateResponse(
        request=request,
        name="admin_security.html",
        context={
            "emergency_mode":
                load_emergency_mode(db),
            "users":
                load_local_users(db),
            "message":
                message,
        },
    )


# ============================================================
# ENABLE EMERGENCY MODE
#
# Maximum duration: 24 hours.
# ============================================================

@router.post(
    "/emergency-mode/enable",
    response_class=RedirectResponse,
)
def enable_emergency_mode(
    request: Request,
    duration_hours: int = Form(...),
    reason: str = Form(...),
    db: Session = Depends(get_db),
):
    user = get_current_user(request)

    reason_value = reason.strip()

    if not reason_value:
        raise HTTPException(
            status_code=400,
            detail=(
                "An emergency access reason "
                "is required."
            ),
        )

    if duration_hours not in (
        2,
        4,
        8,
        12,
        24,
    ):
        raise HTTPException(
            status_code=400,
            detail=(
                "Emergency mode duration "
                "must be 2, 4, 8, 12 or "
                "24 hours."
            ),
        )

    expires_at = (
        datetime.now()
        + timedelta(
            hours=duration_hours
        )
    )

    try:
        db.execute(
            text(
                """
                UPDATE app_emergency_mode
                SET
                    enabled = true,
                    enabled_at =
                        CURRENT_TIMESTAMP,
                    enabled_by =
                        :enabled_by,
                    expires_at =
                        :expires_at,
                    reason =
                        :reason,
                    disabled_at = NULL,
                    disabled_by = NULL
                WHERE id = 1
                """
            ),
            {
                "enabled_by":
                    user.username,
                "expires_at":
                    expires_at,
                "reason":
                    reason_value,
            },
        )

        write_audit(
            db=db,
            request=request,
            action=(
                "EMERGENCY_MODE_ENABLE"
            ),
            result="SUCCESS",
            user=user,
            target_type=(
                "EMERGENCY_MODE"
            ),
            target_id="1",
            reason=reason_value,
            details=(
                "Expires at {}".format(
                    expires_at.isoformat()
                )
            ),
        )

        db.commit()

    except SQLAlchemyError as exception:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail=(
                "Unable to enable "
                "Emergency Mode."
            ),
        ) from exception

    return RedirectResponse(
        url=(
            "/web/admin/security"
            "?message=Emergency+Mode+enabled"
        ),
        status_code=303,
    )


# ============================================================
# DISABLE EMERGENCY MODE
# ============================================================

@router.post(
    "/emergency-mode/disable",
    response_class=RedirectResponse,
)
def disable_emergency_mode(
    request: Request,
    db: Session = Depends(get_db),
):
    user = get_current_user(request)

    try:
        db.execute(
            text(
                """
                UPDATE app_emergency_mode
                SET
                    enabled = false,
                    disabled_at =
                        CURRENT_TIMESTAMP,
                    disabled_by =
                        :disabled_by
                WHERE id = 1
                """
            ),
            {
                "disabled_by":
                    user.username,
            },
        )

        write_audit(
            db=db,
            request=request,
            action=(
                "EMERGENCY_MODE_DISABLE"
            ),
            result="SUCCESS",
            user=user,
            target_type=(
                "EMERGENCY_MODE"
            ),
            target_id="1",
        )

        db.commit()

    except SQLAlchemyError as exception:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail=(
                "Unable to disable "
                "Emergency Mode."
            ),
        ) from exception

    return RedirectResponse(
        url=(
            "/web/admin/security"
            "?message=Emergency+Mode+disabled"
        ),
        status_code=303,
    )


# ============================================================
# CREATE TEMPORARY LOCAL USER
#
# Only Reader and Operator can be created here.
# Admin remains a separately controlled emergency account.
# ============================================================

@router.post(
    "/users/create",
    response_class=RedirectResponse,
)
def create_local_user(
    request: Request,
    username: str = Form(...),
    display_name: str = Form(...),
    role: str = Form(...),
    password: str = Form(...),
    expiry_hours: int = Form(...),
    db: Session = Depends(get_db),
):
    admin = get_current_user(request)

    username_value = (
        normalize_username(
            username
        )
    )

    display_name_value = (
        display_name.strip()
    )

    if not username_value:
        raise HTTPException(
            status_code=400,
            detail="Username is required.",
        )

    if not display_name_value:
        raise HTTPException(
            status_code=400,
            detail=(
                "Display name is required."
            ),
        )

    if role not in (
        ROLE_READER,
        ROLE_OPERATOR,
    ):
        raise HTTPException(
            status_code=400,
            detail=(
                "Temporary accounts can "
                "only be Reader or Operator."
            ),
        )

    if len(password) < 14:
        raise HTTPException(
            status_code=400,
            detail=(
                "Password must contain at "
                "least 14 characters."
            ),
        )

    if expiry_hours not in (
        2,
        4,
        8,
        12,
        24,
    ):
        raise HTTPException(
            status_code=400,
            detail=(
                "Account expiry must be "
                "2, 4, 8, 12 or 24 hours."
            ),
        )

    emergency = load_emergency_mode(
        db
    )

    if (
        emergency is None
        or not emergency["enabled"]
    ):
        raise HTTPException(
            status_code=400,
            detail=(
                "Emergency Mode must be "
                "enabled before temporary "
                "users can be created."
            ),
        )

    expires_at = (
        datetime.now()
        + timedelta(
            hours=expiry_hours
        )
    )

    if (
        emergency["expires_at"]
        is not None
        and expires_at
            > emergency["expires_at"]
    ):
        expires_at = (
            emergency["expires_at"]
        )

    password_hash = hash_password(
        password
    )

    try:
        db.execute(
            text(
                """
                INSERT INTO app_local_users (
                    username,
                    display_name,
                    password_hash,
                    role,
                    enabled,
                    emergency_admin,
                    expires_at,
                    created_by,
                    updated_by
                )
                VALUES (
                    :username,
                    :display_name,
                    :password_hash,
                    :role,
                    true,
                    false,
                    :expires_at,
                    :created_by,
                    :updated_by
                )
                """
            ),
            {
                "username":
                    username_value,
                "display_name":
                    display_name_value,
                "password_hash":
                    password_hash,
                "role":
                    role,
                "expires_at":
                    expires_at,
                "created_by":
                    admin.username,
                "updated_by":
                    admin.username,
            },
        )

        write_audit(
            db=db,
            request=request,
            action=(
                "LOCAL_USER_CREATE"
            ),
            result="SUCCESS",
            user=admin,
            target_type="LOCAL_USER",
            target_id=username_value,
            details=(
                "Role {}; expires {}".format(
                    role,
                    expires_at.isoformat(),
                )
            ),
        )

        db.commit()

    except IntegrityError:
        db.rollback()

        raise HTTPException(
            status_code=409,
            detail=(
                "That local username "
                "already exists."
            ),
        )

    except SQLAlchemyError as exception:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail=(
                "Unable to create "
                "temporary local user."
            ),
        ) from exception

    return RedirectResponse(
        url=(
            "/web/admin/security"
            "?message=Temporary+user+created"
        ),
        status_code=303,
    )


# ============================================================
# DISABLE LOCAL USER
# ============================================================

@router.post(
    "/users/{user_id}/disable",
    response_class=RedirectResponse,
)
def disable_local_user(
    request: Request,
    user_id: int,
    db: Session = Depends(get_db),
):
    admin = get_current_user(request)

    row = db.execute(
        text(
            """
            SELECT
                id,
                username,
                emergency_admin
            FROM app_local_users
            WHERE id = :user_id
            """
        ),
        {
            "user_id":
                user_id,
        },
    ).mappings().first()

    if row is None:
        raise HTTPException(
            status_code=404,
            detail="Local user not found.",
        )

    if row["emergency_admin"]:
        raise HTTPException(
            status_code=400,
            detail=(
                "Emergency Admin accounts "
                "cannot be disabled from "
                "this screen."
            ),
        )

    db.execute(
        text(
            """
            UPDATE app_local_users
            SET
                enabled = false,
                updated_at =
                    CURRENT_TIMESTAMP,
                updated_by =
                    :updated_by
            WHERE id = :user_id
            """
        ),
        {
            "user_id":
                user_id,
            "updated_by":
                admin.username,
        },
    )

    write_audit(
        db=db,
        request=request,
        action="LOCAL_USER_DISABLE",
        result="SUCCESS",
        user=admin,
        target_type="LOCAL_USER",
        target_id=row["username"],
    )

    db.commit()

    return RedirectResponse(
        url=(
            "/web/admin/security"
            "?message=Local+user+disabled"
        ),
        status_code=303,
    )


# ============================================================
# ENABLE LOCAL USER
# ============================================================

@router.post(
    "/users/{user_id}/enable",
    response_class=RedirectResponse,
)
def enable_local_user(
    request: Request,
    user_id: int,
    db: Session = Depends(get_db),
):
    admin = get_current_user(request)

    row = db.execute(
        text(
            """
            SELECT
                id,
                username,
                emergency_admin,
                expires_at
            FROM app_local_users
            WHERE id = :user_id
            """
        ),
        {
            "user_id":
                user_id,
        },
    ).mappings().first()

    if row is None:
        raise HTTPException(
            status_code=404,
            detail="Local user not found.",
        )

    if row["emergency_admin"]:
        raise HTTPException(
            status_code=400,
            detail=(
                "Emergency Admin accounts "
                "are managed separately."
            ),
        )

    emergency = load_emergency_mode(
        db
    )

    if (
        emergency is None
        or not emergency["enabled"]
    ):
        raise HTTPException(
            status_code=400,
            detail=(
                "Emergency Mode must be "
                "enabled before temporary "
                "users can be enabled."
            ),
        )

    if (
        row["expires_at"] is None
        or row["expires_at"]
            <= datetime.now()
    ):
        raise HTTPException(
            status_code=400,
            detail=(
                "This local account has "
                "expired. Create a new "
                "temporary account."
            ),
        )

    db.execute(
        text(
            """
            UPDATE app_local_users
            SET
                enabled = true,
                failed_attempts = 0,
                locked_until = NULL,
                updated_at =
                    CURRENT_TIMESTAMP,
                updated_by =
                    :updated_by
            WHERE id = :user_id
            """
        ),
        {
            "user_id":
                user_id,
            "updated_by":
                admin.username,
        },
    )

    write_audit(
        db=db,
        request=request,
        action="LOCAL_USER_ENABLE",
        result="SUCCESS",
        user=admin,
        target_type="LOCAL_USER",
        target_id=row["username"],
    )

    db.commit()

    return RedirectResponse(
        url=(
            "/web/admin/security"
            "?message=Local+user+enabled"
        ),
        status_code=303,
    )
