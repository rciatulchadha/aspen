import getpass

from sqlalchemy import text

from app.database import SessionLocal
from app.security import (
    ROLE_ADMIN,
    hash_password,
    normalize_username,
)


def main():
    username = normalize_username(
        input(
            "Emergency Admin username: "
        )
    )

    display_name = input(
        "Display name: "
    ).strip()

    password = getpass.getpass(
        "Password: "
    )

    confirm = getpass.getpass(
        "Confirm password: "
    )

    if not username:
        raise SystemExit(
            "Username is required."
        )

    if not display_name:
        raise SystemExit(
            "Display name is required."
        )

    if len(password) < 14:
        raise SystemExit(
            "Password must contain at least "
            "14 characters."
        )

    if password != confirm:
        raise SystemExit(
            "Passwords do not match."
        )

    password_hash = hash_password(
        password
    )

    with SessionLocal() as db:
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
            raise SystemExit(
                "Username already exists."
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
                    created_by,
                    updated_by
                )
                VALUES (
                    :username,
                    :display_name,
                    :password_hash,
                    :role,
                    true,
                    true,
                    NULL,
                    'INITIAL_BOOTSTRAP',
                    'INITIAL_BOOTSTRAP'
                )
                """
            ),
            {
                "username": username,
                "display_name":
                    display_name,
                "password_hash":
                    password_hash,
                "role": ROLE_ADMIN,
            },
        )

        db.commit()

    print(
        "Emergency Admin created."
    )


if __name__ == "__main__":
    main()
