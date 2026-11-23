CREATE OR REPLACE FUNCTION public.uf_pcactivitylist(p_env character varying, p_datefrom timestamp without time zone, p_dateto timestamp without time zone)
 RETURNS SETOF activities
 LANGUAGE sql
 STABLE
AS $function$

    SELECT a.*

    FROM activities a

    WHERE a.environment = p_env

      AND a.est_time
          BETWEEN p_datefrom AND p_dateto

      AND a.status = 'None'

      AND a.unplannedact = false

      AND a.deleted = false

    ORDER BY a.est_time;

$function$

