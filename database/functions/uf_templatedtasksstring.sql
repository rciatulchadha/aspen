CREATE OR REPLACE FUNCTION public.uf_templatedtasksstring(p_env character varying DEFAULT 'v21'::character varying)
 RETURNS character varying
 LANGUAGE sql
 STABLE
AS $function$

    SELECT

        CASE

            WHEN COUNT(*) = 0
                THEN '('''')'

            ELSE
                '('
                ||
                string_agg(
                    d.day_no::text
                    || t.tasknumber,
                    ','
                    ORDER BY
                        t.id,
                        d.day_no
                )
                ||
                ')'

        END::varchar(400)

    FROM templatedactivities t

    CROSS JOIN generate_series(
        1,
        7
    ) AS d(day_no)

    WHERE t.environment = p_env;

$function$

