from app.security import (
    ROLE_ADMIN,
    ROLE_OPERATOR,
    ROLE_READER,
)


# ============================================================
# PUBLIC ROUTES
#
# /change-password is public to RBAC middleware, but the
# route itself still requires a valid signed session.
# ============================================================

PUBLIC_PATHS = {
    "/login",
    "/logout",
    "/health",
    "/change-password",
}


PUBLIC_PREFIXES = (
    "/static/",
)


def is_public_path(
    path,
):
    if path in PUBLIC_PATHS:
        return True

    return any(
        path.startswith(
            prefix
        )
        for prefix
        in PUBLIC_PREFIXES
    )


# ============================================================
# ASPEN AUTHORIZATION MATRIX
# ============================================================

def allowed_roles_for_request(
    method,
    path,
):
    method = method.upper()


    all_roles = {
        ROLE_READER,
        ROLE_OPERATOR,
        ROLE_ADMIN,
    }


    operator_admin = {
        ROLE_OPERATOR,
        ROLE_ADMIN,
    }


    admin_only = {
        ROLE_ADMIN,
    }


    # ========================================================
    # DASHBOARD
    # ========================================================

    if path == "/":
        return all_roles


    # ========================================================
    # API DOCUMENTATION
    # Admin only
    # ========================================================

    if path.startswith(
        "/docs"
    ):
        return admin_only


    if path.startswith(
        "/openapi"
    ):
        return admin_only


    if path.startswith(
        "/redoc"
    ):
        return admin_only


    # ========================================================
    # ADMINISTRATION
    # Admin only
    # ========================================================

    if path.startswith(
        "/web/admin"
    ):
        return admin_only


    # ========================================================
    # DAILY TASKS
    #
    # Reader     NO
    # Operator   NO
    # Admin      YES
    # ========================================================

    if path.startswith(
        "/web/daily-tasks"
    ):
        return admin_only


    # ========================================================
    # PRODUCTION CONTROL
    #
    # Reader     Preview
    # Operator   Preview
    # Admin      Preview + Populate
    # ========================================================

    if path == (
        "/web/production-control"
    ):

        if method == "GET":
            return all_roles

        return admin_only


    if path.startswith(
        "/web/production-control/"
    ):
        return admin_only


    # ========================================================
    # TURNOVER
    #
    # Reader / Operator:
    #     View only
    #
    # Admin:
    #     Add/update
    # ========================================================

    if path.startswith(
        "/web/turnover/mps/new"
    ):
        return admin_only


    if path.startswith(
        "/web/turnover/add"
    ):
        return admin_only


    if path.startswith(
        "/web/turnover"
    ):

        if method == "GET":
            return all_roles

        return admin_only


    # ========================================================
    # REPORTS
    # Reader / Operator / Admin
    # ========================================================

    if path.startswith(
        "/web/reports"
    ):
        return all_roles


    # ========================================================
    # ACTIVITIES WEB UI
    #
    # Reader:
    #     View only
    #
    # Operator:
    #     View
    #     Create
    #     Edit
    #     Add Event
    #
    # Admin:
    #     Full access including delete/restore
    # ========================================================

    if path.startswith(
        "/web/activities"
    ):

        # ----------------------------------------------------
        # Activity deletion / restore
        # Admin only
        # ----------------------------------------------------

        if (
            path.endswith(
                "/delete"
            )
            or path.endswith(
                "/restore"
            )
        ):
            return admin_only


        # ----------------------------------------------------
        # Add Event
        # Operator + Admin
        # ----------------------------------------------------

        if "/events" in path:

            if method == "POST":
                return operator_admin

            return all_roles


        # ----------------------------------------------------
        # New Activity
        # GET form + POST creation
        # Operator + Admin
        # ----------------------------------------------------

        if (
            path
            == "/web/activities/new"
        ):
            return operator_admin


        # ----------------------------------------------------
        # Edit Activity
        # GET form + POST update
        # Operator + Admin
        # ----------------------------------------------------

        if path.endswith(
            "/edit"
        ):
            return operator_admin


        # ----------------------------------------------------
        # Remaining Activity pages
        # GET = everyone
        # Other mutation = Operator/Admin
        # ----------------------------------------------------

        if method == "GET":
            return all_roles

        return operator_admin


    # ========================================================
    # ACTIVITIES API
    #
    # Reader may GET.
    # Operator/Admin may mutate.
    # ========================================================

    if path.startswith(
        "/activities"
    ):

        if method == "GET":
            return all_roles

        return operator_admin


    # ========================================================
    # DEFAULT DENY
    #
    # Any new route must be explicitly classified before
    # non-Admin users receive access.
    # ========================================================

    return admin_only
