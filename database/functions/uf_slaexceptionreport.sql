CREATE OR REPLACE FUNCTION public.uf_slaexceptionreport(p_taskstart character, p_repdate timestamp without time zone, p_env character varying, p_difference integer)
 RETURNS TABLE(taskno integer, title character varying, est_time timestamp without time zone, firstevent timestamp without time zone, status character varying, difference integer, id integer)
 LANGUAGE sql
 STABLE
AS $function$

    SELECT
        s.taskno,
        s.title,
        s.est_time,
        s.firstevent,
        s.status,

        (
            EXTRACT(
                EPOCH FROM (
                    s.firstevent
                    - s.est_time
                )
            ) / 60
        )::integer AS difference,

        s.id

    FROM vw_slaexceptionreport s

    WHERE s.taskno::text
              LIKE p_taskstart || '%'

      AND s.est_time
          BETWEEN
              p_repdate - INTERVAL '2 days'
              AND
              p_repdate + INTERVAL '2 days'

      AND s.environment = p_env

      AND (
            EXTRACT(
                EPOCH FROM (
                    s.firstevent
                    - s.est_time
                )
            ) / 60
          ) >= p_difference;

$function$

