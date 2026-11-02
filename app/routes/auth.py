from fastapi import (
    APIRouter,
    Depends,
    Form,
    Request,
)
from fastapi.responses import (
    HTMLResponse,
    RedirectResponse,
)
from fastapi.templating import Jinja2Templates
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.security import (
    authenticate_local_user,
    hash_password,
    load_session_user,
    save_session_user,
    verify_password,
    write_audit,
)


router = APIRouter(
    tags=["Authentication"],
)

templates = Jinja2Templates(
    directory="app/templates"
)


# ============================================================
# LOGIN PAGE
# ============================================================

@router.get(
    "/login",
    response_class=HTMLResponse,
)
def login_page(
    request: Request,
):
    existing_user = load_session_user(
        request
    )

    if existing_user is not None:

        if (
            existing_user
            .must_change_password
        ):
            return RedirectResponse(
                url="/change-password",
                status_code=303,
            )

        return RedirectResponse(
            url="/",
            status_code=303,
        )

    return templates.TemplateResponse(
        request=request,
        name="login.html",
        context={
            "error": None,
            "local_auth_enabled":
                settings.local_auth_enabled,
        },
    )


# ============================================================
# LOCAL LOGIN
# ============================================================

@router.post(
    "/login",
    response_class=HTMLResponse,
)
def local_login(
    request: Request,
    username: str = Form(...),
    password: str = Form(...),
    db: Session = Depends(get_db),
):
    if not settings.local_auth_enabled:
        return templates.TemplateResponse(
            request=request,
            name="login.html",
            status_code=403,
            context={
                "error": (
                    "Local authentication "
                    "is disabled."
                ),
                "local_auth_enabled": False,
            },
        )

    user = authenticate_local_user(
        db=db,
        request=request,
        username=username,
        password=password,
    )

    if user is None:
        return templates.TemplateResponse(
            request=request,
            name="login.html",
            status_code=401,
            context={
                "error": (
                    "Invalid username or "
                    "password, or the account "
                    "is disabled, expired, "
                    "or locked."
                ),
                "local_auth_enabled": True,
            },
        )

    save_session_user(
        request,
        user,
    )

    if user.must_change_password:
        return RedirectResponse(
            url="/change-password",
            status_code=303,
        )

    return RedirectResponse(
        url="/",
        status_code=303,
    )


# ============================================================
# CHANGE PASSWORD PAGE
#
# Used for:
# - mandatory first-login password change
# - password change after an Admin reset
# - voluntary password change by the signed-in user
# ============================================================

@router.get(
    "/change-password",
    response_class=HTMLResponse,
)
def change_password_page(
    request: Request,
):
    user = load_session_user(
        request
    )

    if user is None:
        return RedirectResponse(
            url="/login",
            status_code=303,
        )

    return templates.TemplateResponse(
        request=request,
        name="change_password.html",
        context={
            "error": None,
            "success": None,
            "forced": (
                user.must_change_password
            ),
            "user": user,
        },
    )


# ============================================================
# CHANGE PASSWORD
# ============================================================

@router.post(
    "/change-password",
    response_class=HTMLResponse,
)
def change_password(
    request: Request,

    current_password: str = Form(...),
    new_password: str = Form(...),
    confirm_password: str = Form(...),

    db: Session = Depends(get_db),
):
    session_user = load_session_user(
        request
    )

    if session_user is None:
        return RedirectResponse(
            url="/login",
            status_code=303,
        )

    account = db.execute(
        text(
            """
            SELECT
                id,
                username,
                display_name,
                password_hash,
                role,
                enabled,
                emergency_admin,
                must_change_password
            FROM app_local_users
            WHERE lower(username) =
                  lower(:username)
            """
        ),
        {
            "username":
                session_user.username,
        },
    ).mappings().first()

    if account is None:
        request.session.clear()

        return RedirectResponse(
            url="/login",
            status_code=303,
        )

    error = None

    if not account["enabled"]:
        error = (
            "This account is disabled."
        )

    elif not verify_password(
        current_password,
        account["password_hash"],
    ):
        error = (
            "The current password is incorrect."
        )

    elif len(new_password) < 14:
        error = (
            "The new password must contain "
            "at least 14 characters."
        )

    elif new_password != confirm_password:
        error = (
            "The new password and confirmation "
            "do not match."
        )

    elif verify_password(
        new_password,
        account["password_hash"],
    ):
        error = (
            "The new password must be different "
            "from the current password."
        )

    if error:
        write_audit(
            db=db,
            request=request,
            action="PASSWORD_CHANGE",
            result="FAILURE",
            user=session_user,
            target_type="LOCAL_USER",
            target_id=(
                session_user.username
            ),
            details=error,
        )

        db.commit()

        return templates.TemplateResponse(
            request=request,
            name="change_password.html",
            status_code=400,
            context={
                "error": error,
                "success": None,
                "forced": (
                    session_user
                    .must_change_password
                ),
                "user": session_user,
            },
        )

    try:
        new_password_hash = (
            hash_password(
                new_password
            )
        )

        db.execute(
            text(
                """
                UPDATE app_local_users
                SET
                    password_hash =
                        :password_hash,

                    must_change_password =
                        false,

                    password_changed_at =
                        CURRENT_TIMESTAMP,

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
                "password_hash":
                    new_password_hash,
                "updated_by":
                    session_user.username,
                "user_id":
                    account["id"],
            },
        )

        session_user.must_change_password = (
            False
        )

        save_session_user(
            request,
            session_user,
        )

        write_audit(
            db=db,
            request=request,
            action="PASSWORD_CHANGE",
            result="SUCCESS",
            user=session_user,
            target_type="LOCAL_USER",
            target_id=(
                session_user.username
            ),
            details=(
                "User changed local "
                "ASPEN password."
            ),
        )

        db.commit()

    except SQLAlchemyError:
        db.rollback()

        return templates.TemplateResponse(
            request=request,
            name="change_password.html",
            status_code=500,
            context={
                "error": (
                    "ASPEN could not change "
                    "the password. The previous "
                    "password remains valid."
                ),
                "success": None,
                "forced": (
                    session_user
                    .must_change_password
                ),
                "user": session_user,
            },
        )

    return templates.TemplateResponse(
        request=request,
        name="change_password.html",
        context={
            "error": None,
            "success": (
                "Password changed successfully."
            ),
            "forced": False,
            "user": session_user,
        },
    )


# ============================================================
# LOGOUT
# ============================================================

@router.post(
    "/logout",
    response_class=RedirectResponse,
)
def logout(
    request: Request,
    db: Session = Depends(get_db),
):
    user = load_session_user(
        request
    )

    if user is not None:
        try:
            write_audit(
                db=db,
                request=request,
                action="LOGOUT",
                result="SUCCESS",
                user=user,
            )

            db.commit()

        except SQLAlchemyError:
            db.rollback()

    request.session.clear()

    return RedirectResponse(
        url="/login",
        status_code=303,
    )
