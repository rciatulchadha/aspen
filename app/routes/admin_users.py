from typing import Optional
from datetime import datetime

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
    ROLE_ADMIN,
    ROLE_OPERATOR,
    ROLE_READER,
    hash_password,
    normalize_username,
    write_audit,
)


router = APIRouter(
    prefix="/web/admin/users",
    tags=["User Administration"],
)

templates = Jinja2Templates(
    directory="app/templates"
)


VALID_ROLES = {
    ROLE_READER,
    ROLE_OPERATOR,
    ROLE_ADMIN,
}


ROLE_OPTIONS = [
    {
        "value": ROLE_READER,
        "label": "Reader",
    },
    {
        "value": ROLE_OPERATOR,
        "label": "Operator",
    },
    {
        "value": ROLE_ADMIN,
        "label": "Admin",
    },
]


# ============================================================
# HELPERS
# ============================================================

def require_admin(
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

    if not user.is_admin:
        raise HTTPException(
            status_code=403,
            detail="Admin access required",
        )

    return user


def get_local_user(
    db: Session,
    user_id: int,
):
    user = db.execute(
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
                created_by,
                updated_at,
                updated_by,
                must_change_password,
                password_changed_at

            FROM app_local_users

            WHERE id = :user_id
            """
        ),
        {
            "user_id": user_id,
        },
    ).mappings().first()

    if user is None:
        raise HTTPException(
            status_code=404,
            detail="ASPEN user not found",
        )

    return user


def count_enabled_admins(
    db: Session,
):
    return db.scalar(
        text(
            """
            SELECT COUNT(*)

            FROM app_local_users

            WHERE role = :admin_role
              AND enabled = true
            """
        ),
        {
            "admin_role": ROLE_ADMIN,
        },
    ) or 0


def validate_username(
    username: str,
):
    if not username:
        return "Username is required."

    if len(username) > 100:
        return (
            "Username cannot exceed "
            "100 characters."
        )

    allowed = set(
        "abcdefghijklmnopqrstuvwxyz"
        "0123456789._-@"
    )

    if any(
        character not in allowed
        for character in username
    ):
        return (
            "Username may contain only "
            "letters, numbers, periods, "
            "underscores, hyphens and @."
        )

    return None


def validate_display_name(
    display_name: str,
):
    if not display_name:
        return (
            "Display Name is required."
        )

    if len(display_name) > 200:
        return (
            "Display Name cannot exceed "
            "200 characters."
        )

    return None


def render_new_user_page(
    request: Request,
    error: Optional[str] = None,
    form: Optional[dict] = None,
    status_code: int = 200,
):
    return templates.TemplateResponse(
        request=request,
        name="admin_user_new.html",
        status_code=status_code,
        context={
            "error": error,
            "form": form,
            "roles": ROLE_OPTIONS,
        },
    )


# ============================================================
# USER LIST
# ============================================================

@router.get(
    "",
    response_class=HTMLResponse,
)
def users_page(
    request: Request,
    search: str = "",
    account_status: str = "",
    role: str = "",
    message: str = "",
    db: Session = Depends(get_db),
):
    require_admin(request)

    filters = []

    parameters = {}

    if search.strip():
        parameters["search"] = (
            "%{}%".format(
                search.strip()
            )
        )

        filters.append(
            """
            (
                username ILIKE :search
                OR display_name ILIKE :search
            )
            """
        )

    if account_status == "enabled":
        filters.append(
            "enabled = true"
        )

    elif account_status == "disabled":
        filters.append(
            "enabled = false"
        )

    elif account_status == "locked":
        filters.append(
            """
            locked_until IS NOT NULL
            AND locked_until > CURRENT_TIMESTAMP
            """
        )

    elif account_status == "password-change":
        filters.append(
            "must_change_password = true"
        )

    if role in VALID_ROLES:
        parameters["role"] = role

        filters.append(
            "role = :role"
        )

    where_clause = ""

    if filters:
        where_clause = (
            "WHERE "
            + " AND ".join(filters)
        )

    users = db.execute(
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
                created_by,
                must_change_password,
                password_changed_at

            FROM app_local_users

            {}

            ORDER BY
                emergency_admin DESC,
                enabled DESC,
                display_name,
                username
            """.format(
                where_clause
            )
        ),
        parameters,
    ).mappings().all()

    return templates.TemplateResponse(
        request=request,
        name="admin_users.html",
        context={
            "users": users,
            "roles": ROLE_OPTIONS,
            "search": search,
            "selected_status":
                account_status,
            "selected_role": role,
            "message": message,
	    "now": datetime.now(),
        },
    )


# ============================================================
# NEW USER PAGE
# ============================================================

@router.get(
    "/new",
    response_class=HTMLResponse,
)
def new_user_page(
    request: Request,
):
    require_admin(request)

    return render_new_user_page(
        request=request,
    )


# ============================================================
# CREATE PERMANENT LOCAL USER
# ============================================================

@router.post(
    "/new",
    response_class=HTMLResponse,
)
def create_user(
    request: Request,

    username: str = Form(...),
    display_name: str = Form(...),
    role: str = Form(...),
    temporary_password: str = Form(...),
    confirm_password: str = Form(...),

    db: Session = Depends(get_db),
):
    admin = require_admin(request)

    username_value = normalize_username(
        username
    )

    display_name_value = (
        display_name.strip()
    )

    form = {
        "username": username,
        "display_name": display_name,
        "role": role,
    }

    error = validate_username(
        username_value
    )

    if error is None:
        error = validate_display_name(
            display_name_value
        )

    if (
        error is None
        and role not in VALID_ROLES
    ):
        error = (
            "A valid ASPEN role "
            "is required."
        )

    if (
        error is None
        and len(temporary_password) < 14
    ):
        error = (
            "Temporary password must "
            "contain at least 14 characters."
        )

    if (
        error is None
        and temporary_password
            != confirm_password
    ):
        error = (
            "Temporary password and "
            "confirmation do not match."
        )

    if error:
        return render_new_user_page(
            request=request,
            error=error,
            form=form,
            status_code=400,
        )

    try:
        password_hash = hash_password(
            temporary_password
        )

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
                    failed_attempts,
                    locked_until,
                    must_change_password,
                    password_changed_at,
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
                    NULL,
                    0,
                    NULL,
                    true,
                    NULL,
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

                "created_by":
                    admin.username,

                "updated_by":
                    admin.username,
            },
        )

        write_audit(
            db=db,
            request=request,
            action="LOCAL_USER_CREATE",
            result="SUCCESS",
            user=admin,
            target_type="LOCAL_USER",
            target_id=username_value,
            details=(
                "Permanent local user "
                "created with role {}. "
                "Password change required."
            ).format(role),
        )

        db.commit()

    except IntegrityError:
        db.rollback()

        return render_new_user_page(
            request=request,
            error=(
                "That ASPEN username "
                "already exists."
            ),
            form=form,
            status_code=409,
        )

    except SQLAlchemyError as exception:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail=(
                "Unable to create "
                "ASPEN user."
            ),
        ) from exception

    return RedirectResponse(
        url=(
            "/web/admin/users"
            "?message=User+created+successfully"
        ),
        status_code=303,
    )


# ============================================================
# EDIT USER PAGE
# ============================================================

@router.get(
    "/{user_id}/edit",
    response_class=HTMLResponse,
)
def edit_user_page(
    request: Request,
    user_id: int,
    db: Session = Depends(get_db),
):
    require_admin(request)

    user = get_local_user(
        db,
        user_id,
    )

    return templates.TemplateResponse(
        request=request,
        name="admin_user_edit.html",
        context={
            "managed_user": user,
            "roles": ROLE_OPTIONS,
            "error": None,
        },
    )


# ============================================================
# UPDATE USER PROFILE / ROLE
# ============================================================

@router.post(
    "/{user_id}/edit",
    response_class=HTMLResponse,
)
def update_user(
    request: Request,
    user_id: int,
    display_name: str = Form(...),
    role: str = Form(...),
    db: Session = Depends(get_db),
):
    admin = require_admin(request)

    managed_user = get_local_user(
        db,
        user_id,
    )

    display_name_value = (
        display_name.strip()
    )

    error = validate_display_name(
        display_name_value
    )

    if (
        error is None
        and role not in VALID_ROLES
    ):
        error = (
            "A valid ASPEN role "
            "is required."
        )

    if managed_user["emergency_admin"]:
        error = (
            "Emergency Admin accounts "
            "cannot be modified through "
            "normal User Management."
        )

    if (
        managed_user["username"]
        == admin.username
        and role != ROLE_ADMIN
    ):
        error = (
            "You cannot remove the Admin "
            "role from your current account."
        )

    if (
        managed_user["role"]
        == ROLE_ADMIN
        and role != ROLE_ADMIN
        and managed_user["enabled"]
        and count_enabled_admins(db) <= 1
    ):
        error = (
            "ASPEN must retain at least "
            "one enabled Admin account."
        )

    if error:
        return templates.TemplateResponse(
            request=request,
            name="admin_user_edit.html",
            status_code=400,
            context={
                "managed_user":
                    managed_user,
                "roles":
                    ROLE_OPTIONS,
                "error":
                    error,
            },
        )

    try:
        db.execute(
            text(
                """
                UPDATE app_local_users

                SET
                    display_name =
                        :display_name,

                    role =
                        :role,

                    updated_at =
                        CURRENT_TIMESTAMP,

                    updated_by =
                        :updated_by

                WHERE id =
                    :user_id
                """
            ),
            {
                "display_name":
                    display_name_value,

                "role":
                    role,

                "updated_by":
                    admin.username,

                "user_id":
                    user_id,
            },
        )

        write_audit(
            db=db,
            request=request,
            action="LOCAL_USER_UPDATE",
            result="SUCCESS",
            user=admin,
            target_type="LOCAL_USER",
            target_id=(
                managed_user["username"]
            ),
            details=(
                "Display name updated; "
                "role set to {}."
            ).format(role),
        )

        db.commit()

    except SQLAlchemyError as exception:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail=(
                "Unable to update "
                "ASPEN user."
            ),
        ) from exception

    return RedirectResponse(
        url=(
            "/web/admin/users"
            "?message=User+updated+successfully"
        ),
        status_code=303,
    )


# ============================================================
# DISABLE USER
# ============================================================

@router.post(
    "/{user_id}/disable",
    response_class=RedirectResponse,
)
def disable_user(
    request: Request,
    user_id: int,
    db: Session = Depends(get_db),
):
    admin = require_admin(request)

    managed_user = get_local_user(
        db,
        user_id,
    )

    if managed_user["emergency_admin"]:
        raise HTTPException(
            status_code=400,
            detail=(
                "Emergency Admin accounts "
                "cannot be disabled."
            ),
        )

    if (
        managed_user["username"]
        == admin.username
    ):
        raise HTTPException(
            status_code=400,
            detail=(
                "You cannot disable your "
                "current account."
            ),
        )

    if (
        managed_user["role"]
        == ROLE_ADMIN
        and managed_user["enabled"]
        and count_enabled_admins(db) <= 1
    ):
        raise HTTPException(
            status_code=400,
            detail=(
                "ASPEN must retain at least "
                "one enabled Admin account."
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

            WHERE id =
                :user_id
            """
        ),
        {
            "updated_by":
                admin.username,

            "user_id":
                user_id,
        },
    )

    write_audit(
        db=db,
        request=request,
        action="LOCAL_USER_DISABLE",
        result="SUCCESS",
        user=admin,
        target_type="LOCAL_USER",
        target_id=(
            managed_user["username"]
        ),
    )

    db.commit()

    return RedirectResponse(
        url=(
            "/web/admin/users"
            "?message=User+disabled"
        ),
        status_code=303,
    )


# ============================================================
# ENABLE USER
# ============================================================

@router.post(
    "/{user_id}/enable",
    response_class=RedirectResponse,
)
def enable_user(
    request: Request,
    user_id: int,
    db: Session = Depends(get_db),
):
    admin = require_admin(request)

    managed_user = get_local_user(
        db,
        user_id,
    )

    if managed_user["emergency_admin"]:
        raise HTTPException(
            status_code=400,
            detail=(
                "Emergency Admin accounts "
                "are managed separately."
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

            WHERE id =
                :user_id
            """
        ),
        {
            "updated_by":
                admin.username,

            "user_id":
                user_id,
        },
    )

    write_audit(
        db=db,
        request=request,
        action="LOCAL_USER_ENABLE",
        result="SUCCESS",
        user=admin,
        target_type="LOCAL_USER",
        target_id=(
            managed_user["username"]
        ),
    )

    db.commit()

    return RedirectResponse(
        url=(
            "/web/admin/users"
            "?message=User+enabled"
        ),
        status_code=303,
    )


# ============================================================
# UNLOCK USER
# ============================================================

@router.post(
    "/{user_id}/unlock",
    response_class=RedirectResponse,
)
def unlock_user(
    request: Request,
    user_id: int,
    db: Session = Depends(get_db),
):
    admin = require_admin(request)

    managed_user = get_local_user(
        db,
        user_id,
    )

    db.execute(
        text(
            """
            UPDATE app_local_users

            SET
                failed_attempts = 0,

                locked_until = NULL,

                updated_at =
                    CURRENT_TIMESTAMP,

                updated_by =
                    :updated_by

            WHERE id =
                :user_id
            """
        ),
        {
            "updated_by":
                admin.username,

            "user_id":
                user_id,
        },
    )

    write_audit(
        db=db,
        request=request,
        action="LOCAL_USER_UNLOCK",
        result="SUCCESS",
        user=admin,
        target_type="LOCAL_USER",
        target_id=(
            managed_user["username"]
        ),
    )

    db.commit()

    return RedirectResponse(
        url=(
            "/web/admin/users"
            "?message=User+unlocked"
        ),
        status_code=303,
    )


# ============================================================
# RESET PASSWORD PAGE
# ============================================================

@router.get(
    "/{user_id}/reset-password",
    response_class=HTMLResponse,
)
def reset_password_page(
    request: Request,
    user_id: int,
    db: Session = Depends(get_db),
):
    require_admin(request)

    managed_user = get_local_user(
        db,
        user_id,
    )

    if managed_user["emergency_admin"]:
        raise HTTPException(
            status_code=400,
            detail=(
                "Emergency Admin passwords "
                "must be managed separately."
            ),
        )

    return templates.TemplateResponse(
        request=request,
        name="admin_user_reset_password.html",
        context={
            "managed_user":
                managed_user,
            "error":
                None,
        },
    )


# ============================================================
# RESET PASSWORD
# ============================================================

@router.post(
    "/{user_id}/reset-password",
    response_class=HTMLResponse,
)
def reset_password(
    request: Request,
    user_id: int,

    temporary_password: str = Form(...),
    confirm_password: str = Form(...),

    db: Session = Depends(get_db),
):
    admin = require_admin(request)

    managed_user = get_local_user(
        db,
        user_id,
    )

    if managed_user["emergency_admin"]:
        raise HTTPException(
            status_code=400,
            detail=(
                "Emergency Admin passwords "
                "must be managed separately."
            ),
        )

    error = None

    if len(temporary_password) < 14:
        error = (
            "Temporary password must contain "
            "at least 14 characters."
        )

    elif (
        temporary_password
        != confirm_password
    ):
        error = (
            "Temporary password and "
            "confirmation do not match."
        )

    if error:
        return templates.TemplateResponse(
            request=request,
            name="admin_user_reset_password.html",
            status_code=400,
            context={
                "managed_user":
                    managed_user,
                "error":
                    error,
            },
        )

    try:
        new_hash = hash_password(
            temporary_password
        )

        db.execute(
            text(
                """
                UPDATE app_local_users

                SET
                    password_hash =
                        :password_hash,

                    must_change_password =
                        true,

                    password_changed_at =
                        NULL,

                    failed_attempts = 0,

                    locked_until = NULL,

                    updated_at =
                        CURRENT_TIMESTAMP,

                    updated_by =
                        :updated_by

                WHERE id =
                    :user_id
                """
            ),
            {
                "password_hash":
                    new_hash,

                "updated_by":
                    admin.username,

                "user_id":
                    user_id,
            },
        )

        write_audit(
            db=db,
            request=request,
            action=(
                "LOCAL_USER_PASSWORD_RESET"
            ),
            result="SUCCESS",
            user=admin,
            target_type="LOCAL_USER",
            target_id=(
                managed_user["username"]
            ),
            details=(
                "Temporary password issued. "
                "Password change required "
                "at next login."
            ),
        )

        db.commit()

    except SQLAlchemyError as exception:
        db.rollback()

        raise HTTPException(
            status_code=500,
            detail=(
                "Unable to reset "
                "the password."
            ),
        ) from exception

    return RedirectResponse(
        url=(
            "/web/admin/users"
            "?message=Password+reset+successfully"
        ),
        status_code=303,
    )
