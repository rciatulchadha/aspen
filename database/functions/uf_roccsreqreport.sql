CREATE OR REPLACE FUNCTION public.uf_roccsreqreport(p_env character varying, p_datefrom timestamp without time zone, p_dateto timestamp without time zone)
 RETURNS TABLE(actid integer, evtid integer, taskno integer, est_time timestamp without time zone, title character varying, actdetails text, status character varying, dependency character varying, resource character varying, note text, time_started timestamp without time zone, systimeentered timestamp without time zone, evtdetails text, operator character varying, serial integer, colour character varying, subenvironment character varying)
 LANGUAGE sql
 STABLE
AS $function$

    SELECT
        r.actid,
        r.evtid,
        r.taskno,
        r.est_time,
        r.title,
        r.actdetails,
        r.status,
        r.dependency,
        r.resource,
        r.note,
        r.time_started,
        r.systimeentered,
        r.evtdetails,
        r."operator",
        r.serial,
        r.colour,
        r.subenvironment

    FROM uf_roccreport(
        p_env,
        p_datefrom,
        p_dateto
    ) r

    WHERE r.title ILIKE '%SREQ5%'
       OR r.title ILIKE '%SREQ05%'
       OR r.title ILIKE '%SREQ16%';

$function$

