CREATE OR REPLACE FUNCTION public.uf_prodcontrolreport(p_env character varying, p_datefrom timestamp without time zone, p_dateto timestamp without time zone)
 RETURNS TABLE(taskno integer, est_time timestamp without time zone, title character varying, details text, note text, dependency character varying, resource character varying)
 LANGUAGE sql
 STABLE
AS $function$

    SELECT
        a.taskno,
        a.est_time,
        a.title,
        a.details,
        a.note,
        a.dependency,
        a.resource

    FROM activities a

    WHERE a.closed != 'Yes'

      AND a.environment = p_env

      AND a.est_time
          BETWEEN p_datefrom AND p_dateto

      AND a.unplannedact = false

      AND a.deleted = false;

$function$

