from datetime import datetime, timedelta

from fastapi import HTTPException
from pwdlib import PasswordHash
from sqlalchemy import text

from app.config import settings


password_hash = PasswordHash.recommended()


# ============================================================
# ASPEN APPLICATION ROLES
# ============================================================

ROLE_READER = "ASPEN.Reader"
ROLE_OPERATOR = "ASPEN.Operator"
ROLE_ADMIN = "ASPEN.Admin"


VALID_ROLES = {
    ROLE_READER,
    ROLE_OPERATOR,
    ROLE_ADMIN,
}


# ============================================================
# AUTHENTICATED USER
# ============================================================

class AuthenticatedUser:

    def __init__(
        self,
        username,
        display_name,
        role,
        authentication_type,
        emergency_admin=False,
        must_change_password=False,
    ):
        self.username = username

        self.display_name = (
            display_name
        )

        self.role = role

        self.authentication_type = (
            authentication_type
        )

        self.emergency_admin = (
            emergency_admin
        )

        self.must_change_password = (
            must_change_password
        )


    @property
    def is_reader(self):
        return (
            self.role
            == ROLE_READER
        )


    @property
    def is_operator(self):
        return (
            self.role
            == ROLE_OPERATOR
        )


    @property
    def is_admin(self):
        return (
            self.role
            == ROLE_ADMIN
        )


    def has_role(
        self,
        role,
    ):
        if self.role == ROLE_ADMIN:
            return True

        if role == ROLE_READER:
            return self.role in {
                ROLE_READER,
                ROLE_OPERATOR,
            }

        return self.role == role


# ============================================================
# PASSWORD FUNCTIONS
# ============================================================

def hash_password(
    password,
):
    return password_hash.hash(
        password
    )


def verify_password(
    plain_password,
    stored_hash,
):
    try:
        return password_hash.verify(
            plain_password,
            stored_hash,
        )

    except Exception:
        return False


# ============================================================
# USERNAME NORMALIZATION
# ============================================================

def normalize_username(
    username,
):
    return (
        username
        .strip()
        .lower()
    )


# ============================================================
# SOURCE IP
# ============================================================

def get_source_ip(
    request,
):
    forwarded_for = (
        request.headers.get(
            "x-forwarded-for"
        )
    )

    if forwarded_for:
        return (
            forwarded_for
            .split(",")[0]
            .strip()
        )

    if request.client is None:
        return None

    return request.client.host


# ============================================================
# AUDIT LOG
# ============================================================

def write_audit(
    db,
    request,
    action,
    result,
    user=None,
    username=None,
    target_type=None,
    target_id=None,
    reason=None,
    details=None,
):
    if user is not None:

        audit_username = (
            user.username
        )

        display_name = (
            user.display_name
        )

        authentication_type = (
            user.authentication_type
        )

        role = user.role

    else:

        audit_username = username

        display_name = None

        authentication_type = (
            "LOCAL"
        )

        role = None


    db.execute(
        text(
            """
            INSERT INTO app_audit_log (
                username,
                display_name,
                authentication_type,
                role,
                action,
                target_type,
                target_id,
                result,
                source_ip,
                reason,
                details
            )
            VALUES (
                :username,
                :display_name,
                :authentication_type,
                :role,
                :action,
                :target_type,
                :target_id,
                :result,
                :source_ip,
                :reason,
                :details
            )
            """
        ),
        {
            "username":
                audit_username,

            "display_name":
                display_name,

            "authentication_type":
                authentication_type,

            "role":
                role,

            "action":
                action,

            "target_type":
                target_type,

            "target_id":
                (
                    str(target_id)
                    if target_id is not None
                    else None
                ),

            "result":
                result,

            "source_ip":
                get_source_ip(
                    request
                ),

            "reason":
                reason,

            "details":
                details,
        },
    )


# ============================================================
# EMERGENCY MODE
# ============================================================

def get_emergency_mode(
    db,
):
    row = db.execute(
        text(
            """
            SELECT
                enabled,
                enabled_at,
                enabled_by,
                expires_at,
                reason

            FROM app_emergency_mode

            WHERE id = 1
            """
        )
    ).mappings().first()


    if row is None:

        return {
            "enabled": False,
            "enabled_at": None,
            "enabled_by": None,
            "expires_at": None,
            "reason": None,
        }


    if (
        row["enabled"]
        and row["expires_at"]
        is not None
        and row["expires_at"]
        <= datetime.now()
    ):

        db.execute(
            text(
                """
                UPDATE app_emergency_mode

                SET
                    enabled = false,

                    disabled_at =
                        CURRENT_TIMESTAMP,

                    disabled_by =
                        'SYSTEM_EXPIRY'

                WHERE id = 1
                """
            )
        )

        db.commit()

        return {
            "enabled": False,

            "enabled_at":
                row["enabled_at"],

            "enabled_by":
                row["enabled_by"],

            "expires_at":
                row["expires_at"],

            "reason":
                row["reason"],
        }


    return dict(row)


# ============================================================
# SESSION MANAGEMENT
# ============================================================

def load_session_user(
    request,
):
    session_user = (
        request.session.get(
            "user"
        )
    )


    if not session_user:
        return None


    role = session_user.get(
        "role"
    )


    if role not in VALID_ROLES:

        request.session.clear()

        return None


    now = datetime.now()


    last_activity_raw = (
        request.session.get(
            "last_activity"
        )
    )


    if not last_activity_raw:

        # Session was created before idle
        # timeout support or is malformed.

        request.session.clear()

        return None


    try:

        last_activity = (
            datetime.fromisoformat(
                last_activity_raw
            )
        )

    except (
        ValueError,
        TypeError,
    ):

        request.session.clear()

        return None


    idle_limit = timedelta(
        minutes=(
            settings
            .session_idle_minutes
        )
    )


    if (
        now - last_activity
        > idle_limit
    ):

        request.session.clear()

        return None


    # Refresh idle timestamp.

    request.session[
        "last_activity"
    ] = now.isoformat()


    return AuthenticatedUser(

        username=(
            session_user.get(
                "username"
            )
        ),

        display_name=(
            session_user.get(
                "display_name"
            )
        ),

        role=role,

        authentication_type=(
            session_user.get(
                "authentication_type"
            )
        ),

        emergency_admin=(
            session_user.get(
                "emergency_admin",
                False,
            )
        ),

        must_change_password=(
            session_user.get(
                "must_change_password",
                False,
            )
        ),
    )


def save_session_user(
    request,
    user,
):
    request.session.clear()


    request.session["user"] = {

        "username":
            user.username,

        "display_name":
            user.display_name,

        "role":
            user.role,

        "authentication_type":
            user.authentication_type,

        "emergency_admin":
            user.emergency_admin,

        "must_change_password":
            user.must_change_password,
    }


    request.session[
        "last_activity"
    ] = datetime.now().isoformat()


# ============================================================
# AUTHORIZATION HELPERS
# ============================================================

def require_login(
    request,
):
    user = getattr(
        request.state,
        "user",
        None,
    )


    if user is None:

        raise HTTPException(
            status_code=401,
            detail=(
                "Authentication required"
            ),
        )


    return user


def require_role(
    request,
    allowed_roles,
):
    user = require_login(
        request
    )


    if user.role not in allowed_roles:

        raise HTTPException(
            status_code=403,
            detail=(
                "You do not have permission "
                "to perform this action."
            ),
        )


    return user


# ============================================================
# LOCAL USER AUTHENTICATION
#
# Account types:
#
# 1. Permanent local account
#       emergency_admin = false
#       expires_at = NULL
#
#       Login allowed whenever account is enabled.
#
# 2. Temporary emergency account
#       emergency_admin = false
#       expires_at IS NOT NULL
#
#       Emergency Mode must be enabled.
#
# 3. Emergency Admin
#       emergency_admin = true
#
#       Emergency Mode is not required.
# ============================================================

def authenticate_local_user(
    db,
    request,
    username,
    password,
):
    normalized = normalize_username(
        username
    )


    row = db.execute(
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
                expires_at,
                failed_attempts,
                locked_until,
                must_change_password

            FROM app_local_users

            WHERE lower(username) =
                  :username
            """
        ),
        {
            "username":
                normalized,
        },
    ).mappings().first()


    # --------------------------------------------------------
    # UNKNOWN USER
    # --------------------------------------------------------

    if row is None:

        write_audit(
            db=db,
            request=request,
            action="LOCAL_LOGIN",
            result="FAILURE",
            username=normalized,
            details="Unknown username",
        )

        db.commit()

        return None


    now = datetime.now()


    # --------------------------------------------------------
    # DISABLED
    # --------------------------------------------------------

    if not row["enabled"]:

        write_audit(
            db=db,
            request=request,
            action="LOCAL_LOGIN",
            result="DENIED",
            username=row["username"],
            details="Account disabled",
        )

        db.commit()

        return None


    # --------------------------------------------------------
    # EXPIRED TEMPORARY ACCOUNT
    # --------------------------------------------------------

    if (
        row["expires_at"] is not None
        and row["expires_at"] <= now
    ):

        write_audit(
            db=db,
            request=request,
            action="LOCAL_LOGIN",
            result="DENIED",
            username=row["username"],
            details="Account expired",
        )

        db.commit()

        return None


    # --------------------------------------------------------
    # LOCKOUT
    # --------------------------------------------------------

    if (
        row["locked_until"] is not None
        and row["locked_until"] > now
    ):

        write_audit(
            db=db,
            request=request,
            action="LOCAL_LOGIN",
            result="DENIED",
            username=row["username"],
            details="Account locked",
        )

        db.commit()

        return None


    # --------------------------------------------------------
    # TEMPORARY EMERGENCY USER
    #
    # Permanent local users have expires_at = NULL.
    # They do NOT require Emergency Mode.
    # --------------------------------------------------------

    if (
        not row["emergency_admin"]
        and row["expires_at"] is not None
    ):

        emergency_mode = (
            get_emergency_mode(
                db
            )
        )

        if not emergency_mode[
            "enabled"
        ]:

            write_audit(
                db=db,
                request=request,
                action="LOCAL_LOGIN",
                result="DENIED",
                username=row["username"],
                details=(
                    "Temporary account "
                    "requires Emergency Mode"
                ),
            )

            db.commit()

            return None


    # --------------------------------------------------------
    # PASSWORD CHECK
    # --------------------------------------------------------

    if not verify_password(
        password,
        row["password_hash"],
    ):

        failed_attempts = (
            row["failed_attempts"]
            + 1
        )


        locked_until = None


        if (
            failed_attempts
            >= settings.login_max_attempts
        ):

            locked_until = (
                now
                + timedelta(
                    minutes=(
                        settings
                        .login_lock_minutes
                    )
                )
            )

            failed_attempts = 0


        db.execute(
            text(
                """
                UPDATE app_local_users

                SET
                    failed_attempts =
                        :failed_attempts,

                    locked_until =
                        :locked_until,

                    updated_at =
                        CURRENT_TIMESTAMP,

                    updated_by =
                        'LOGIN_SYSTEM'

                WHERE id =
                    :user_id
                """
            ),
            {
                "failed_attempts":
                    failed_attempts,

                "locked_until":
                    locked_until,

                "user_id":
                    row["id"],
            },
        )


        write_audit(
            db=db,
            request=request,
            action="LOCAL_LOGIN",
            result="FAILURE",
            username=row["username"],
            details="Invalid password",
        )


        db.commit()

        return None


    # --------------------------------------------------------
    # AUTHENTICATION TYPE
    # --------------------------------------------------------

    if row["emergency_admin"]:

        authentication_type = (
            "LOCAL_EMERGENCY"
        )

    elif row["expires_at"] is not None:

        authentication_type = (
            "LOCAL_EMERGENCY"
        )

    else:

        authentication_type = (
            "LOCAL"
        )


    # --------------------------------------------------------
    # CREATE AUTHENTICATED USER
    # --------------------------------------------------------

    user = AuthenticatedUser(

        username=row["username"],

        display_name=(
            row["display_name"]
        ),

        role=row["role"],

        authentication_type=(
            authentication_type
        ),

        emergency_admin=(
            row["emergency_admin"]
        ),

        must_change_password=(
            row["must_change_password"]
        ),
    )


    # --------------------------------------------------------
    # SUCCESSFUL LOGIN
    # --------------------------------------------------------

    db.execute(
        text(
            """
            UPDATE app_local_users

            SET
                failed_attempts = 0,

                locked_until = NULL,

                last_login_at =
                    CURRENT_TIMESTAMP,

                updated_at =
                    CURRENT_TIMESTAMP,

                updated_by =
                    'LOGIN_SYSTEM'

            WHERE id =
                :user_id
            """
        ),
        {
            "user_id":
                row["id"],
        },
    )


    write_audit(
        db=db,
        request=request,
        action="LOCAL_LOGIN",
        result="SUCCESS",
        user=user,
    )


    db.commit()


    return user
