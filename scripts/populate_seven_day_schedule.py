import argparse
import sys
from datetime import date, timedelta

from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.database import SessionLocal
from app.environments import (
    ASPEN_ENVIRONMENTS,
    is_valid_environment,
    normalize_environment,
)


SYSTEM_USER = "ASPEN_SCHEDULE_LOADER"


def get_environments(
    db,
    requested_environment=None,
):
    if requested_environment:
        normalized = normalize_environment(
            requested_environment
        )
        if not is_valid_environment(
            normalized
        ):
            raise ValueError(
                "Environment must be Maestro, "
                "V21, or SDM."
            )
        return [normalized]

    return list(ASPEN_ENVIRONMENTS)


def replace_activity_date_tokens(
    db,
    environment,
    schedule_date,
):
    formatted_date = schedule_date.strftime(
        "%d-%m-%Y"
    )

    result = db.execute(
        text(
            """
            UPDATE activities
            SET
                title = REPLACE(
                    title,
                    'DD-MM-YYYY',
                    :formatted_date
                ),
                details = REPLACE(
                    details,
                    'DD-MM-YYYY',
                    :formatted_date
                ),
                note = CASE
                    WHEN note IS NULL THEN NULL
                    ELSE REPLACE(
                        note,
                        'DD-MM-YYYY',
                        :formatted_date
                    )
                END
            WHERE environment = :environment
              AND est_time >= CAST(:schedule_date AS date)
              AND est_time < (
                    CAST(:schedule_date AS date)
                    + INTERVAL '1 day'
              )
              AND (
                    title LIKE '%DD-MM-YYYY%'
                    OR details LIKE '%DD-MM-YYYY%'
                    OR note LIKE '%DD-MM-YYYY%'
              )
            """
        ),
        {
            "environment": environment,
            "schedule_date": schedule_date,
            "formatted_date": formatted_date,
        },
    )

    return result.rowcount or 0


def count_missing_activities(
    db,
    environment,
    schedule_date,
):
    weekday_number = (
        schedule_date.isoweekday()
    )

    return db.scalar(
        text(
            """
            SELECT COUNT(*)

            FROM uf_autoeoxreplacedailylist(
                CAST(
                    :environment
                    AS varchar
                ),
                CAST(
                    :schedule_date
                    AS timestamp
                ),
                CAST(
                    :weekday_number
                    AS char(1)
                )
            ) generated

            WHERE generated.taskno
                  IS NOT NULL

              AND generated.deleted = false

              AND NOT EXISTS (
                  SELECT 1

                  FROM activities existing

                  WHERE existing.taskno =
                        generated.taskno

                    AND existing.est_time =
                        generated.est_time

                    AND existing.environment =
                        generated.environment
              )
            """
        ),
        {
            "environment":
                environment,
            "schedule_date":
                schedule_date,
            "weekday_number":
                str(weekday_number),
        },
    ) or 0


def write_system_audit(
    db,
    action,
    result,
    environment,
    details,
):
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
                NULL,
                :reason,
                :details
            )
            """
        ),
        {
            "username":
                SYSTEM_USER,
            "display_name":
                "ASPEN Schedule Loader",
            "authentication_type":
                "SYSTEM_JOB",
            "role":
                "ASPEN.Admin",
            "action":
                action,
            "target_type":
                "ENVIRONMENT",
            "target_id":
                environment,
            "result":
                result,
            "reason":
                "Rolling seven-day schedule",
            "details":
                details,
        },
    )


def populate_environment(
    db,
    environment,
    start_offset,
    days,
    dry_run,
):
    start_date = (
        date.today()
        + timedelta(
            days=start_offset
        )
    )

    results = []

    for relative_day in range(days):
        date_difference = (
            start_offset
            + relative_day
        )

        schedule_date = (
            date.today()
            + timedelta(
                days=date_difference
            )
        )

        missing_before = (
            count_missing_activities(
                db=db,
                environment=environment,
                schedule_date=schedule_date,
            )
        )

        if not dry_run:
            db.execute(
                text(
                    """
                    CALL
                        sp_automaticdailytaskpopulator(
                            CAST(
                                :environment
                                AS varchar
                            ),
                            CAST(
                                :date_difference
                                AS smallint
                            )
                        )
                    """
                ),
                {
                    "environment":
                        environment,
                    "date_difference":
                        date_difference,
                },
            )

        replacements = 0
        if not dry_run:
            replacements = replace_activity_date_tokens(
                db=db,
                environment=environment,
                schedule_date=schedule_date,
            )

        results.append(
            {
                "schedule_date":
                    schedule_date,
                "missing_before":
                    missing_before,
                "inserted":
                    (
                        0
                        if dry_run
                        else missing_before
                    ),
                "date_tokens_replaced":
                    replacements,
            }
        )

    end_date = (
        start_date
        + timedelta(
            days=days - 1
        )
    )

    total_missing = sum(
        item["missing_before"]
        for item in results
    )

    total_replaced = sum(
        item["date_tokens_replaced"]
        for item in results
    )

    details = (
        "Range {} through {}; "
        "{} day(s); {} missing "
        "Activities; {} date token(s) replaced; "
        "dry_run={}"
    ).format(
        start_date,
        end_date,
        days,
        total_missing,
        total_replaced,
        dry_run,
    )

    write_system_audit(
        db=db,
        action=(
            "SEVEN_DAY_SCHEDULE_DRY_RUN"
            if dry_run
            else
            "SEVEN_DAY_SCHEDULE_POPULATE"
        ),
        result="SUCCESS",
        environment=environment,
        details=details,
    )

    return results


def parse_arguments():
    parser = argparse.ArgumentParser(
        description=(
            "Populate the ASPEN rolling "
            "schedule using Daily Tasks."
        )
    )

    parser.add_argument(
        "--environment",
        help=(
            "Populate one environment. "
            "Omit to process all Production "
            "Control environments."
        ),
    )

    parser.add_argument(
        "--days",
        type=int,
        default=7,
        help=(
            "Number of schedule dates to "
            "evaluate. Default: 7."
        ),
    )

    parser.add_argument(
        "--start-offset",
        type=int,
        default=0,
        help=(
            "Starting date offset from today. "
            "Default: 0."
        ),
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
        help=(
            "Report missing Activities without "
            "inserting them."
        ),
    )

    return parser.parse_args()


def validate_arguments(args):
    if args.days < 1:
        raise ValueError(
            "--days must be at least 1."
        )

    if args.days > 31:
        raise ValueError(
            "--days cannot exceed 31."
        )

    last_offset = (
        args.start_offset
        + args.days
        - 1
    )

    if (
        args.start_offset < -32768
        or last_offset > 32767
    ):
        raise ValueError(
            "Requested date range exceeds "
            "the procedure's smallint offset."
        )


def main():
    args = parse_arguments()

    try:
        validate_arguments(args)

        with SessionLocal() as db:
            environments = (
                get_environments(
                    db=db,
                    requested_environment=(
                        args.environment
                    ),
                )
            )

            if not environments:
                raise ValueError(
                    "No Production Control "
                    "environments were found."
                )

            print(
                "ASPEN rolling schedule loader"
            )

            print(
                "Mode:",
                (
                    "DRY RUN"
                    if args.dry_run
                    else "POPULATE"
                ),
            )

            print(
                "Days:",
                args.days,
            )

            print(
                "Start offset:",
                args.start_offset,
            )

            print()

            grand_total = 0
            grand_replaced = 0

            for environment in environments:
                print(
                    "Environment:",
                    environment,
                )

                results = (
                    populate_environment(
                        db=db,
                        environment=(
                            environment
                        ),
                        start_offset=(
                            args.start_offset
                        ),
                        days=args.days,
                        dry_run=args.dry_run,
                    )
                )

                for result in results:
                    print(
                        "  {}  missing={}  date_tokens_replaced={}"
                        .format(
                            result["schedule_date"],
                            result["missing_before"],
                            result["date_tokens_replaced"],
                        )
                    )
                    grand_replaced += result[
                        "date_tokens_replaced"
                    ]

                    grand_total += (
                        result[
                            "missing_before"
                        ]
                    )

                print()

            if args.dry_run:
                db.rollback()

                print(
                    "Dry run complete."
                )

                print(
                    "Total missing Activities:",
                    grand_total,
                )

            else:
                db.commit()

                print(
                    "Schedule population "
                    "committed."
                )

                print(
                    "Activities inserted:",
                    grand_total,
                )
                print(
                    "Date tokens replaced:",
                    grand_replaced,
                )

        return 0

    except (
        ValueError,
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
