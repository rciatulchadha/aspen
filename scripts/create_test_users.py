import getpass
from datetime import datetime, timedelta

from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from app.database import SessionLocal
from app.security import (
    ROLE_OPERATOR,
    ROLE_READER,
    hash_password,
    normalize_username,
)


def get_password(
    label,
):
    password = getpass.getpass(
        "{} password: ".format(label)
    )

    confirm = getpass.getpass(
        "Confirm {} password: ".format(
            label
        )
    )

    if password != confirm:
        raise SystemExit(
            "{} passwords do not match.".format(
                label
            )
        )

    if len(password) < 14:
        raise SystemExit(
            "{} password must contain at least "
            "14 characters.".format(label)
        )

    return password


def create_user(
    db,
    username,
    display_name,
    role,
    password,
    expires_at,
):
    username = normalize_username(
        username
    )

    existing = db.scalar(
        text(
            """
            SELECT COUNT(*)
            FROM app_local_users
            WHERE lower(username) =
                  :username
            """
        ),
        {
            "username": username,
        },
    )

    if existing:
        print(
            "{} already exists. Skipping.".format(
                username
            )
        )
        return False

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
                0,
                'RBAC_TEST_SETUP',
                'RBAC_TEST_SETUP'
            )
            """
        ),
        {
            "username": username,
            "display_name": display_name,
            "password_hash":
                hash_password(password),
            "role": role,
            "expires_at": expires_at,
        },
    )

    print(
        "Created {} with role {}".format(
            username,
            role,
        )
    )

    return True


def main():
    with SessionLocal() as db:

        emergency = db.execute(
            text(
                """
                SELECT
                    enabled,
                    expires_at
                FROM app_emergency_mode
                WHERE id = 1
                """
            )
        ).mappings().first()

        if (
            emergency is None
            or not emergency["enabled"]
        ):
            raise SystemExit(
                "Emergency Mode is not enabled."
            )

        now = datetime.now()

        if (
            emergency["expires_at"]
            is not None
            and emergency["expires_at"] <= now
        ):
            raise SystemExit(
                "Emergency Mode has expired."
            )

        print()
        print("Creating ASPEN RBAC test users")
        print("================================")
        print()

        reader_password = get_password(
            "Reader"
        )

        print()

        operator_password = get_password(
            "Operator"
        )

        requested_expiry = (
            now
            + timedelta(hours=2)
        )

        if (
            emergency["expires_at"]
            is not None
            and requested_expiry
                > emergency["expires_at"]
        ):
            expires_at = (
                emergency["expires_at"]
            )
        else:
            expires_at = (
                requested_expiry
            )

        try:

            create_user(
                db=db,
                username="aspen_reader_test",
                display_name=(
                    "ASPEN Reader Test"
                ),
                role=ROLE_READER,
                password=reader_password,
                expires_at=expires_at,
            )

            create_user(
                db=db,
                username=(
                    "aspen_operator_test"
                ),
                display_name=(
                    "ASPEN Operator Test"
                ),
                role=ROLE_OPERATOR,
                password=operator_password,
                expires_at=expires_at,
            )

            db.commit()

        except IntegrityError as exception:

            db.rollback()

            raise SystemExit(
                "Unable to create test users: "
                "{}".format(exception)
            )

        print()
        print("Test accounts ready.")
        print()
        print(
            "Reader   : aspen_reader_test"
        )
        print(
            "Operator : aspen_operator_test"
        )
        print(
            "Expires  : {}".format(
                expires_at.strftime(
                    "%Y-%m-%d %H:%M"
                )
            )
        )


if __name__ == "__main__":
    main()
