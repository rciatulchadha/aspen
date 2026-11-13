import sys

from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.database import SessionLocal


RETENTION_DAYS = 7


def main():
    db = SessionLocal()

    try:
        print()
        print("============================================")
        print("ASPEN Activity Retention")
        print("============================================")
        print()

        print(
            "Retention policy: {} calendar days "
            "including today".format(
                RETENTION_DAYS
            )
        )

        # ----------------------------------------------------
        # Prevent two retention processes from running
        # simultaneously.
        # ----------------------------------------------------

        db.execute(
            text(
                """
                SELECT pg_advisory_xact_lock(
                    hashtext(
                        'aspen_activity_retention'
                    )
                )
                """
            )
        )

        # ----------------------------------------------------
        # Freeze the list of Activities eligible for purge.
        #
        # Example:
        #
        # Today = Nov 13
        #
        # Keep:
        # Nov 7 through future
        #
        # Delete:
        # Before Nov 7 00:00
        # ----------------------------------------------------

        db.execute(
            text(
                """
                CREATE TEMP TABLE
                    purge_activity_ids
                ON COMMIT DROP
                AS

                SELECT
                    id

                FROM activities

                WHERE est_time
                    < CURRENT_DATE
                    - INTERVAL '6 days'
                """
            )
        )

        db.execute(
            text(
                """
                CREATE UNIQUE INDEX
                    purge_activity_ids_pk

                ON purge_activity_ids (
                    id
                )
                """
            )
        )

        db.execute(
            text(
                """
                ANALYZE purge_activity_ids
                """
            )
        )

        summary = db.execute(
            text(
                """
                SELECT
                    CURRENT_DATE
                        AS run_date,

                    CURRENT_DATE
                        - INTERVAL '6 days'
                        AS retention_cutoff,

                    COUNT(*)
                        AS activities_selected

                FROM purge_activity_ids
                """
            )
        ).mappings().one()

        print(
            "Run date          : {}".format(
                summary["run_date"]
            )
        )

        print(
            "Retention cutoff  : {}".format(
                summary["retention_cutoff"]
            )
        )

        print(
            "Activities selected: {}".format(
                summary["activities_selected"]
            )
        )

        # ----------------------------------------------------
        # Delete child Event records first.
        # ----------------------------------------------------

        events_deleted = db.scalar(
            text(
                """
                WITH deleted AS (
                    DELETE FROM events e

                    USING purge_activity_ids p

                    WHERE e.id = p.id

                    RETURNING e.serial
                )

                SELECT
                    COUNT(*)

                FROM deleted
                """
            )
        ) or 0

        print(
            "Events deleted    : {}".format(
                events_deleted
            )
        )

        # ----------------------------------------------------
        # Delete Turnover references.
        # ----------------------------------------------------

        turnover_deleted = db.scalar(
            text(
                """
                WITH deleted AS (
                    DELETE
                    FROM turnoveractivities t

                    USING purge_activity_ids p

                    WHERE t.activityid = p.id

                    RETURNING t.activityid
                )

                SELECT
                    COUNT(*)

                FROM deleted
                """
            )
        ) or 0

        print(
            "Turnover refs deleted: {}".format(
                turnover_deleted
            )
        )

        # ----------------------------------------------------
        # Delete parent Activities.
        # ----------------------------------------------------

        activities_deleted = db.scalar(
            text(
                """
                WITH deleted AS (
                    DELETE
                    FROM activities a

                    USING purge_activity_ids p

                    WHERE a.id = p.id

                    RETURNING a.id
                )

                SELECT
                    COUNT(*)

                FROM deleted
                """
            )
        ) or 0

        print(
            "Activities deleted: {}".format(
                activities_deleted
            )
        )

        # ----------------------------------------------------
        # Verification
        # ----------------------------------------------------

        remaining = db.scalar(
            text(
                """
                SELECT
                    COUNT(*)

                FROM activities

                WHERE est_time
                    < CURRENT_DATE
                    - INTERVAL '6 days'
                """
            )
        ) or 0

        if remaining != 0:
            raise RuntimeError(
                "{} expired Activities remain "
                "after retention cleanup.".format(
                    remaining
                )
            )

        orphaned_events = db.scalar(
            text(
                """
                SELECT
                    COUNT(*)

                FROM events e

                LEFT JOIN activities a
                    ON a.id = e.id

                WHERE a.id IS NULL
                """
            )
        ) or 0

        if orphaned_events != 0:
            raise RuntimeError(
                "{} orphaned Events detected."
                .format(
                    orphaned_events
                )
            )

        orphaned_turnover = db.scalar(
            text(
                """
                SELECT
                    COUNT(*)

                FROM turnoveractivities t

                LEFT JOIN activities a
                    ON a.id = t.activityid

                WHERE a.id IS NULL
                """
            )
        ) or 0

        if orphaned_turnover != 0:
            raise RuntimeError(
                "{} orphaned Turnover records "
                "detected.".format(
                    orphaned_turnover
                )
            )

        db.commit()

        print()
        print(
            "ASPEN retention completed successfully."
        )

        print(
            "Expired Activities remaining: 0"
        )

        print(
            "Orphaned Events: 0"
        )

        print(
            "Orphaned Turnover references: 0"
        )

        return 0

    except (
        SQLAlchemyError,
        RuntimeError,
    ) as exception:

        db.rollback()

        print(
            "ERROR: ASPEN retention failed.",
            file=sys.stderr,
        )

        print(
            str(exception),
            file=sys.stderr,
        )

        return 1

    finally:

        db.close()


if __name__ == "__main__":
    sys.exit(
        main()
    )
