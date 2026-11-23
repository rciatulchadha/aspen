CREATE OR REPLACE FUNCTION public.uf_roccreport(p_env character varying, p_datefrom timestamp without time zone, p_dateto timestamp without time zone)
 RETURNS TABLE(actid integer, evtid integer, taskno integer, est_time timestamp without time zone, title character varying, actdetails text, status character varying, dependency character varying, resource character varying, note text, time_started timestamp without time zone, systimeentered timestamp without time zone, evtdetails text, operator character varying, serial integer, colour character varying, subenvironment character varying)
 LANGUAGE sql
 STABLE
AS $function$

    SELECT
        a.id AS actid,
        e.id AS evtid,
        a.taskno,
        a.est_time,
        a.title,
        a.details AS actdetails,
        a.status,
        a.dependency,
        a.resource,
        a.note,
        e.time_started,
        e.systimeentered,
        e.details AS evtdetails,
        e.operator::varchar(50),
        e.serial,
        c.colour::varchar(7),
        a.subenvironment

    FROM activities a

    LEFT JOIN events e
        ON a.id = e.id

    JOIN opsreportstatuscolour c
        ON a.status = c.status

    WHERE a.environment = p_env

      AND (
            a.est_time BETWEEN p_datefrom AND p_dateto

            OR

            e.time_started BETWEEN p_datefrom AND p_dateto

            OR

            (
                a.est_time <= p_dateto
                AND a.status IN ('Open', 'None')
            )
          );

$function$

