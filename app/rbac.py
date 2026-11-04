from app.security import ROLE_ADMIN, ROLE_OPERATOR, ROLE_READER

PUBLIC_PATHS = {"/login", "/logout", "/health", "/change-password"}
PUBLIC_PREFIXES = ("/static/",)


def is_public_path(path):
    if path in PUBLIC_PATHS:
        return True
    return any(path.startswith(prefix) for prefix in PUBLIC_PREFIXES)


def allowed_roles_for_request(method, path):
    method = method.upper()
    all_roles = {ROLE_READER, ROLE_OPERATOR, ROLE_ADMIN}
    operator_admin = {ROLE_OPERATOR, ROLE_ADMIN}
    admin_only = {ROLE_ADMIN}

    if path == "/":
        return all_roles

    if path.startswith(("/docs", "/openapi", "/redoc", "/web/admin")):
        return admin_only

    # Daily Tasks are viewable by all authenticated roles.
    # All maintenance routes continue to require Admin.
    if path.startswith("/web/daily-tasks"):
        if method != "GET":
            return admin_only
        if path == "/web/daily-tasks" or path.rstrip("/").split("/")[-1].isdigit():
            return all_roles
        return admin_only

    if path == "/web/production-control":
        return all_roles if method == "GET" else admin_only
    if path.startswith("/web/production-control/"):
        return admin_only

    if path.startswith("/web/turnover/mps/new") or path.startswith("/web/turnover/add"):
        return admin_only
    if path.startswith("/web/turnover"):
        return all_roles if method == "GET" else admin_only

    if path.startswith("/web/reports"):
        return all_roles

    if path.startswith("/web/activities"):
        if path.endswith("/delete") or path.endswith("/restore"):
            return admin_only
        if "/events" in path:
            return operator_admin if method == "POST" else all_roles
        if path == "/web/activities/new":
            return operator_admin
        if path.endswith("/edit"):
            return operator_admin
        return all_roles if method == "GET" else operator_admin

    if path.startswith("/activities"):
        return all_roles if method == "GET" else operator_admin

    return admin_only
