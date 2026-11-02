\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION uf_autoeoxdailylist(
    p_env varchar(10),
    p_weekday char(1),
    p_tasklength integer
)
RETURNS TABLE (
    taskno integer,
    title varchar(255),
    details text,
    note text,
    dependency varchar(100),
    environment varchar(10),
    subenvironment varchar(25),
    resource varchar(20),
    "time" varchar(5),
    criticalact boolean,
    deleted boolean
)
LANGUAGE sql
STABLE
AS $func$

    SELECT
        d.taskno,
        d.title,
        d.details,
        d.note,
        d.dependency,
        d.environment,
        d.subenvironment,
        d.resource,
        d.time::varchar(5),
        d.criticalact,
        d.deleted

    FROM dailytasks d

    WHERE d.environment = p_env

      AND (
            d.taskno BETWEEN 0 AND 99

            OR

            d.taskno BETWEEN
                (
                    p_weekday
                    || repeat('0', p_tasklength)
                )::integer

                AND

                (
                    p_weekday
                    || repeat('9', p_tasklength)
                )::integer
          )

      AND d.deleted = false

    ORDER BY d.time;

$func$;

COMMIT;
