CREATE OR REPLACE FUNCTION public.uf_roccbillingfyireport(p_repdate timestamp without time zone, p_hourrange integer)
 RETURNS TABLE(title character varying, status character varying, id integer, systimeentered timestamp without time zone)
 LANGUAGE sql
 STABLE
AS $function$

    SELECT
        x.title,
        x.status,
        x.id,
        x.systimeentered

    FROM (

        SELECT
            a.title,
            a.status,
            a.id,
            MIN(e.systimeentered) AS systimeentered

        FROM activities a

        JOIN events e
            ON a.id = e.id

        WHERE a.environment = 'v21'

          AND a.title ILIKE '%Bill%'

          AND (
                a.status = 'Open'

                OR

                (
                    e.systimeentered >=
                        p_repdate
                        - (
                            p_hourrange
                            * INTERVAL '1 hour'
                          )

                    AND e.systimeentered <=
                        p_repdate
                )

                OR

                (
                    a.est_time >=
                        p_repdate
                        - (
                            p_hourrange
                            * INTERVAL '1 hour'
                          )

                    AND a.est_time <=
                        p_repdate
                )
              )

        GROUP BY
            a.title,
            a.status,
            a.id


        UNION


        SELECT
            a.title,
            a.status,
            a.id,
            a.est_time AS systimeentered

        FROM activities a

        WHERE a.environment = 'v21'

          AND a.title ILIKE '%Bill%'

          AND a.status = 'None'

          AND a.est_time <= p_repdate

    ) x;

$function$

