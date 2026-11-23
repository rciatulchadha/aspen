CREATE OR REPLACE FUNCTION public.uf_activitywithevent(p_id integer)
 RETURNS TABLE(taskno integer, est_time timestamp without time zone, title character varying, actdetails text, status character varying, note text, dependency character varying, resource character varying, time_started timestamp without time zone, evtdetails text, operator character varying, colour character varying)
 LANGUAGE sql
 STABLE
AS $function$

    SELECT
        a.taskno,
        a.est_time,
        a.title,
        a.details AS actdetails,
        a.status,
        a.note,
        a.dependency,
        a.resource,
        e.time_started,
        e.details AS evtdetails,
        e.operator::varchar(50) AS "operator",
        c.colour::varchar(7) AS colour

    FROM activities a

    LEFT JOIN events e
        ON a.id = e.id

    JOIN opsreportstatuscolour c
        ON a.status = c.status

    WHERE a.id = p_id

    ORDER BY
        e.time_started,
        e.serial;

$function$

