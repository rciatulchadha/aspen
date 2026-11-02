\set ON_ERROR_STOP on

BEGIN;


CREATE OR REPLACE FUNCTION public.uf_autoeoxreplacedailylist(
    p_env character varying,
    p_today timestamp without time zone,
    p_weekdayno character
)
RETURNS TABLE (
    taskno integer,
    title character varying,
    details text,
    note text,
    dependency character varying,
    environment character varying,
    subenvironment character varying,
    resource character varying,
    est_time timestamp without time zone,
    criticalact boolean,
    deleted boolean
)
LANGUAGE sql
STABLE
AS $function$

WITH environment_config AS (
    SELECT
        tasklength - 1
            AS function_tasklength,

        timeend::time
            AS schedule_end_time

    FROM vw_environment_pc

    WHERE dbkey = p_env
),


source_tasks AS (
    SELECT
        d.taskno
            AS source_taskno,

        d.title
            AS source_title,

        d.details
            AS source_details,

        d.note
            AS source_note,

        d.dependency
            AS source_dependency,

        d.environment,
        d.subenvironment,
        d.resource,

        d."time"
            AS source_time,

        d.criticalact,
        d.deleted,

        c.schedule_end_time

    FROM environment_config c

    JOIN dailytasks d
      ON d.environment = p_env

    WHERE d.deleted = false

      AND d.effective_from
          <= p_today::date

      AND (
            d.effective_to IS NULL
            OR d.effective_to
               >= p_today::date
          )

      AND (
            d.taskno BETWEEN 0 AND 99

            OR

            d.taskno BETWEEN
                (
                    p_weekdayno
                    || repeat(
                        '0',
                        c.function_tasklength
                    )
                )::integer

                AND

                (
                    p_weekdayno
                    || repeat(
                        '9',
                        c.function_tasklength
                    )
                )::integer
          )
),


classified_tasks AS (
    SELECT
        s.*,

        right(
            s.source_taskno::text,
            3
        ) AS task_suffix,

        EXISTS (
            SELECT 1

            FROM templatedactivities t

            WHERE t.environment = p_env

              AND t.tasknumber =
                  right(
                      s.source_taskno::text,
                      3
                  )
        ) AS is_templated,

        CASE
            -- Normal weekday-specific Daily Task.
            WHEN s.source_taskno > 100
                THEN s.source_taskno

            -- New Every Day range.
            -- Values 7 through 99 are converted into the
            -- selected date's weekday task-number range.
            WHEN s.source_taskno
                 BETWEEN 7 AND 99

                THEN
                    p_weekdayno::integer
                    * 10000
                    + s.source_taskno

            -- Preserve legacy EOX behavior.
            WHEN (
                    s.source_taskno < 100
                    AND p_weekdayno <> '6'
                    AND s.source_taskno
                        NOT IN (5, 6)
                 )

              OR (
                    s.source_taskno
                        IN (2, 3)
                    AND p_weekdayno = '6'
                 )

                THEN
                    p_weekdayno::integer
                    * 10000
                    + s.source_taskno

            WHEN p_weekdayno = '6'
             AND s.source_taskno = 5
                THEN 60001

            WHEN p_weekdayno = '6'
             AND s.source_taskno = 6
                THEN 60004

            ELSE NULL
        END AS calculated_taskno

    FROM source_tasks s
),


replaced_tasks AS (
    SELECT
        c.*,

        CASE
            WHEN c.source_taskno
                 BETWEEN 7 AND 99
                THEN c.source_title

            WHEN c.source_taskno > 100
             AND NOT c.is_templated
                THEN c.source_title

            WHEN c.is_templated

              OR (
                    c.source_taskno
                        IN (1, 2, 3, 4)
                    AND p_weekdayno <> '6'
                 )

              OR (
                    c.source_taskno
                        IN (2, 3)
                    AND p_weekdayno = '6'
                 )

                THEN uf_autoeoxreplace(
                    c.source_title,
                    c.source_taskno,
                    p_today,
                    p_weekdayno
                )

            WHEN p_weekdayno = '6'
             AND c.source_taskno = 5

                THEN replace(
                    uf_autoeoxreplace(
                        c.source_title,
                        c.source_taskno,
                        p_today,
                        p_weekdayno
                    ),
                    '60005',
                    '60001'
                )

            WHEN p_weekdayno = '6'
             AND c.source_taskno = 6

                THEN replace(
                    uf_autoeoxreplace(
                        c.source_title,
                        c.source_taskno,
                        p_today,
                        p_weekdayno
                    ),
                    '60006',
                    '60004'
                )

            ELSE NULL
        END AS final_title,


        CASE
            WHEN c.source_taskno
                 BETWEEN 7 AND 99
                THEN c.source_details

            WHEN c.source_taskno > 100
             AND NOT c.is_templated
                THEN c.source_details

            WHEN c.is_templated

              OR (
                    c.source_taskno
                        IN (1, 2, 3, 4)
                    AND p_weekdayno <> '6'
                 )

              OR (
                    c.source_taskno
                        IN (2, 3)
                    AND p_weekdayno = '6'
                 )

                THEN uf_autoeoxreplace(
                    c.source_details,
                    c.source_taskno,
                    p_today,
                    p_weekdayno
                )

            WHEN p_weekdayno = '6'
             AND c.source_taskno = 5

                THEN replace(
                    uf_autoeoxreplace(
                        c.source_details,
                        c.source_taskno,
                        p_today,
                        p_weekdayno
                    ),
                    '60005',
                    '60001'
                )

            WHEN p_weekdayno = '6'
             AND c.source_taskno = 6

                THEN replace(
                    uf_autoeoxreplace(
                        c.source_details,
                        c.source_taskno,
                        p_today,
                        p_weekdayno
                    ),
                    '60006',
                    '60004'
                )

            ELSE NULL
        END AS final_details,


        CASE
            WHEN c.source_taskno
                 BETWEEN 7 AND 99
                THEN c.source_note

            WHEN c.source_taskno > 100
             AND NOT c.is_templated
                THEN c.source_note

            WHEN c.is_templated

              OR (
                    c.source_taskno
                        IN (1, 2, 3, 4)
                    AND p_weekdayno <> '6'
                 )

              OR (
                    c.source_taskno
                        IN (2, 3)
                    AND p_weekdayno = '6'
                 )

                THEN uf_autoeoxreplace(
                    c.source_note,
                    c.source_taskno,
                    p_today,
                    p_weekdayno
                )

            WHEN p_weekdayno = '6'
             AND c.source_taskno = 5

                THEN replace(
                    uf_autoeoxreplace(
                        c.source_note,
                        c.source_taskno,
                        p_today,
                        p_weekdayno
                    ),
                    '60005',
                    '60001'
                )

            WHEN p_weekdayno = '6'
             AND c.source_taskno = 6

                THEN replace(
                    uf_autoeoxreplace(
                        c.source_note,
                        c.source_taskno,
                        p_today,
                        p_weekdayno
                    ),
                    '60006',
                    '60004'
                )

            ELSE NULL
        END AS final_note,


        CASE
            WHEN c.source_taskno
                 BETWEEN 7 AND 99
                THEN c.source_dependency

            WHEN c.source_taskno > 100
             AND NOT c.is_templated
                THEN c.source_dependency

            WHEN c.is_templated

              OR (
                    c.source_taskno
                        IN (1, 2, 3, 4)
                    AND p_weekdayno <> '6'
                 )

              OR (
                    c.source_taskno
                        IN (2, 3)
                    AND p_weekdayno = '6'
                 )

                THEN uf_autoeoxreplace(
                    c.source_dependency,
                    c.source_taskno,
                    p_today,
                    p_weekdayno
                )

            WHEN p_weekdayno = '6'
             AND c.source_taskno = 5

                THEN replace(
                    uf_autoeoxreplace(
                        c.source_dependency,
                        c.source_taskno,
                        p_today,
                        p_weekdayno
                    ),
                    '60005',
                    '60001'
                )

            WHEN p_weekdayno = '6'
             AND c.source_taskno = 6

                THEN replace(
                    uf_autoeoxreplace(
                        c.source_dependency,
                        c.source_taskno,
                        p_today,
                        p_weekdayno
                    ),
                    '60006',
                    '60004'
                )

            ELSE NULL
        END AS final_dependency

    FROM classified_tasks c
)


SELECT
    r.calculated_taskno
        AS taskno,

    r.final_title::varchar(255)
        AS title,

    r.final_details::text
        AS details,

    r.final_note::text
        AS note,

    r.final_dependency::varchar(100)
        AS dependency,

    r.environment::varchar(10)
        AS environment,

    r.subenvironment::varchar(25)
        AS subenvironment,

    r.resource::varchar(20)
        AS resource,

    (
        CASE
            WHEN r.source_time::time
                 < r.schedule_end_time
                THEN p_today::date + 1

            ELSE p_today::date
        END

        + r.source_time::time

    )::timestamp without time zone
        AS est_time,

    r.criticalact,
    r.deleted

FROM replaced_tasks r

WHERE r.calculated_taskno
      IS NOT NULL

ORDER BY
    r.source_time::time,
    r.calculated_taskno;

$function$;


COMMIT;
