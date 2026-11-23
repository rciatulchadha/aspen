import argparse
import os
import re
import sys
from pathlib import Path

from sqlalchemy import create_engine, text
from sqlalchemy.exc import SQLAlchemyError


MIGRATION_PATTERN = re.compile(
    r"^(?P<version>[0-9]+)_(?P<description>.+)\.sql$"
)

DEFAULT_MIGRATIONS_DIR = (
    Path(__file__).resolve().parent.parent
    / "database"
    / "migrations"
)


def parse_arguments():
    parser = argparse.ArgumentParser(
        description=(
            "Apply pending ASPEN PostgreSQL "
            "database migrations."
        )
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
        help=(
            "Show pending migrations without "
            "applying database changes."
        ),
    )

    parser.add_argument(
        "--migrations-dir",
        default=str(DEFAULT_MIGRATIONS_DIR),
        help=(
            "Migration directory. Default: "
            "database/migrations."
        ),
    )

    return parser.parse_args()


def get_database_url():
    database_url = os.environ.get(
        "VSR_DATABASE_URL"
    )

    if not database_url:
        raise RuntimeError(
            "VSR_DATABASE_URL is not configured."
        )

    return database_url


def discover_migrations(migrations_dir):
    path = Path(migrations_dir)

    if not path.exists():
        raise RuntimeError(
            "Migration directory does not exist: "
            f"{path}"
        )

    if not path.is_dir():
        raise RuntimeError(
            "Migration path is not a directory: "
            f"{path}"
        )

    migrations = []

    for migration_file in path.glob("*.sql"):
        match = MIGRATION_PATTERN.match(
            migration_file.name
        )

        if not match:
            continue

        version = match.group("version")

        description = (
            match.group("description")
            .replace("_", " ")
            .strip()
        )

        migrations.append(
            {
                "version": version,
                "description": description,
                "path": migration_file,
            }
        )

    migrations.sort(
        key=lambda item: int(item["version"])
    )

    validate_migration_versions(migrations)

    return migrations


def validate_migration_versions(migrations):
    seen_versions = set()

    for migration in migrations:
        version = migration["version"]

        if version in seen_versions:
            raise RuntimeError(
                "Duplicate migration version: "
                f"{version}"
            )

        seen_versions.add(version)


def migration_table_exists(connection):
    return bool(
        connection.scalar(
            text(
                """
                SELECT EXISTS (
                    SELECT 1
                    FROM information_schema.tables
                    WHERE table_schema = 'public'
                      AND table_name =
                          'schema_migrations'
                )
                """
            )
        )
    )


def get_applied_versions(connection):
    if not migration_table_exists(
        connection
    ):
        return set()

    rows = connection.execute(
        text(
            """
            SELECT version
            FROM public.schema_migrations
            """
        )
    )

    return {
        str(row[0])
        for row in rows
    }


def execute_sql_file(
    connection,
    migration,
):
    sql = migration["path"].read_text(
        encoding="utf-8"
    )

    if not sql.strip():
        raise RuntimeError(
            "Migration file is empty: "
            f"{migration['path']}"
        )

    connection.exec_driver_sql(sql)


def record_migration(
    connection,
    migration,
):
    connection.execute(
        text(
            """
            INSERT INTO public.schema_migrations (
                version,
                description
            )
            VALUES (
                :version,
                :description
            )
            """
        ),
        {
            "version":
                migration["version"],
            "description":
                migration["description"],
        },
    )


def apply_bootstrap_migration(
    engine,
    migration,
):
    with engine.begin() as connection:
        execute_sql_file(
            connection,
            migration,
        )

        if not migration_table_exists(
            connection
        ):
            raise RuntimeError(
                "Migration 000 did not create "
                "public.schema_migrations."
            )

        existing = connection.scalar(
            text(
                """
                SELECT COUNT(*)
                FROM public.schema_migrations
                WHERE version = :version
                """
            ),
            {
                "version":
                    migration["version"],
            },
        )

        if not existing:
            record_migration(
                connection,
                migration,
            )


def apply_migration(
    engine,
    migration,
):
    with engine.begin() as connection:
        execute_sql_file(
            connection,
            migration,
        )

        record_migration(
            connection,
            migration,
        )


def print_migration(migration):
    print(
        "{} - {} ({})".format(
            migration["version"],
            migration["description"],
            migration["path"].name,
        )
    )


def main():
    args = parse_arguments()

    try:
        migrations = discover_migrations(
            args.migrations_dir
        )

        if not migrations:
            raise RuntimeError(
                "No migration files were found."
            )

        database_url = get_database_url()

        engine = create_engine(
            database_url,
            pool_pre_ping=True,
        )

        print(
            "ASPEN PostgreSQL migration runner"
        )
        print(
            "Mode:",
            (
                "DRY RUN"
                if args.dry_run
                else "APPLY"
            ),
        )
        print(
            "Migration directory:",
            Path(
                args.migrations_dir
            ).resolve(),
        )
        print()

        with engine.connect() as connection:
            applied_versions = (
                get_applied_versions(
                    connection
                )
            )

        pending = [
            migration
            for migration in migrations
            if migration["version"]
            not in applied_versions
        ]

        print(
            "Discovered migrations:",
            len(migrations),
        )
        print(
            "Already applied:",
            len(applied_versions),
        )
        print(
            "Pending migrations:",
            len(pending),
        )
        print()

        if not pending:
            print(
                "Database is up to date."
            )
            return 0

        print(
            "Pending migration list:"
        )

        for migration in pending:
            print(
                "  ",
                end="",
            )
            print_migration(
                migration
            )

        print()

        if args.dry_run:
            print(
                "Dry run complete. "
                "No database changes were made."
            )
            return 0

        for migration in pending:
            print(
                "Applying:",
                end=" ",
            )
            print_migration(
                migration
            )

            if (
                migration["version"]
                == "000"
                and not applied_versions
            ):
                apply_bootstrap_migration(
                    engine,
                    migration,
                )
            else:
                apply_migration(
                    engine,
                    migration,
                )

            applied_versions.add(
                migration["version"]
            )

            print(
                "  SUCCESS"
            )

        print()
        print(
            "All pending migrations "
            "completed successfully."
        )

        return 0

    except (
        RuntimeError,
        OSError,
        SQLAlchemyError,
    ) as exception:
        print(
            "ERROR:",
            str(exception),
            file=sys.stderr,
        )

        return 1


if __name__ == "__main__":
    raise SystemExit(
        main()
    )
