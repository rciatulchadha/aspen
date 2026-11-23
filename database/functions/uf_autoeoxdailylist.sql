CREATE OR REPLACE FUNCTION public.uf_autoeoxdailylist(p_env character varying, p_weekday character, p_tasklength integer)
 RETURNS TABLE(taskno integer, title character varying, details text, note text, dependency character varying, environment character varying, subenvironment character varying, resource character varying, "time" character varying, criticalact boolean, deleted boolean)
 LANGUAGE sql
 STABLE
AS $function$

    SELECT
        d.taskno,
        d.title,
        d.details,
        d.note,
        d.dependency,
        d.environment,
        d.subenvironment,
        d.resource,
        d."time"::varchar(5),
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
                    || repeat(
                        '0',
                        p_tasklength
                    )
                )::integer

                AND

                (
                    p_weekday
                    || repeat(
                        '9',
                        p_tasklength
                    )
                )::integer
          )

      AND d.deleted = false

    ORDER BY
        d."time"::time,
        d.taskno;

$function$

