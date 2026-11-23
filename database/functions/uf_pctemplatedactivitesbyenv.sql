CREATE OR REPLACE FUNCTION public.uf_pctemplatedactivitesbyenv(p_envdesc character varying)
 RETURNS SETOF dailytasks
 LANGUAGE sql
 STABLE
AS $function$

    SELECT
        d.*

    FROM dailytasks d

    JOIN vw_environment_pc e
        ON d.environment = e.dbkey

    WHERE e.description = p_envdesc

      AND (
            d.taskno < 100

            OR

            right(
                d.taskno::text,
                3
            ) IN (
                SELECT t.tasknumber
                FROM templatedactivities t
                WHERE t.environment = e.dbkey
            )
          )

    ORDER BY
        d.taskno,
        d.time;

$function$

