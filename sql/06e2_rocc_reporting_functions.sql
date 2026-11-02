\set ON_ERROR_STOP on

BEGIN;


-- ============================================================
-- 1. uf_roccreport
--
-- PostgreSQL conversion of dbo.uf_ROCCReport
-- ============================================================

CREATE OR REPLACE FUNCTION uf_roccreport(
    p_env varchar(10),
    p_datefrom timestamp without time zone,
    p_dateto timestamp without time zone
)
RETURNS TABLE (
    actid integer,
    evtid integer,
    taskno integer,
    est_time timestamp without time zone,
    title varchar(500),
    actdetails text,
    status varchar(15),
    dependency varchar(50),
    resource varchar(50),
    note text,
    time_started timestamp without time zone,
    systimeentered timestamp without time zone,
    evtdetails text,
    "operator" varchar(50),
    serial integer,
    colour varchar(7),
    subenvironment varchar(25)
)
LANGUAGE sql
STABLE
AS $func$

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

$func$;



-- ============================================================
-- 2. uf_roccarchivereport
--
-- PostgreSQL conversion of dbo.uf_ROCCArchiveReport
-- ============================================================

CREATE OR REPLACE FUNCTION uf_roccarchivereport(
    p_env varchar(10),
    p_datefrom timestamp without time zone,
    p_dateto timestamp without time zone
)
RETURNS TABLE (
    actid integer,
    evtid integer,
    taskno integer,
    est_time timestamp without time zone,
    title varchar(500),
    actdetails text,
    status varchar(15),
    dependency varchar(50),
    resource varchar(50),
    note text,
    time_started timestamp without time zone,
    systimeentered timestamp without time zone,
    evtdetails text,
    "operator" varchar(50),
    serial integer,
    colour varchar(7)
)
LANGUAGE sql
STABLE
AS $func$

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
        c.colour::varchar(7)

    FROM archived_activities a

    LEFT JOIN archived_events e
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

$func$;



-- ============================================================
-- 3. uf_roccreportsearch
--
-- PostgreSQL conversion of dbo.uf_ROCCReportSearch
--
-- ILIKE is used so searching behaves case-insensitively.
-- ============================================================

CREATE OR REPLACE FUNCTION uf_roccreportsearch(
    p_env varchar(10),
    p_datefrom timestamp without time zone,
    p_dateto timestamp without time zone,
    p_search varchar(50) DEFAULT ''
)
RETURNS TABLE (
    actid integer,
    evtid integer,
    taskno integer,
    est_time timestamp without time zone,
    title varchar(500),
    actdetails text,
    status varchar(15),
    dependency varchar(50),
    resource varchar(50),
    note text,
    time_started timestamp without time zone,
    systimeentered timestamp without time zone,
    evtdetails text,
    "operator" varchar(50),
    serial integer,
    colour varchar(7),
    subenvironment varchar(25)
)
LANGUAGE sql
STABLE
AS $func$

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

    WHERE r.title ILIKE '%' || p_search || '%'

       OR r.actdetails ILIKE '%' || p_search || '%'

       OR r.note ILIKE '%' || p_search || '%'

       OR r.evtdetails ILIKE '%' || p_search || '%';

$func$;



-- ============================================================
-- 4. uf_roccsreqreport
--
-- PostgreSQL conversion of dbo.uf_ROCCSREQReport
-- ============================================================

CREATE OR REPLACE FUNCTION uf_roccsreqreport(
    p_env varchar(10),
    p_datefrom timestamp without time zone,
    p_dateto timestamp without time zone
)
RETURNS TABLE (
    actid integer,
    evtid integer,
    taskno integer,
    est_time timestamp without time zone,
    title varchar(500),
    actdetails text,
    status varchar(15),
    dependency varchar(50),
    resource varchar(50),
    note text,
    time_started timestamp without time zone,
    systimeentered timestamp without time zone,
    evtdetails text,
    "operator" varchar(50),
    serial integer,
    colour varchar(7),
    subenvironment varchar(25)
)
LANGUAGE sql
STABLE
AS $func$

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

$func$;



-- ============================================================
-- 5. uf_roccsreqarchivereport
--
-- PostgreSQL conversion of dbo.uf_ROCCSREQArchiveReport
-- ============================================================

CREATE OR REPLACE FUNCTION uf_roccsreqarchivereport(
    p_env varchar(10),
    p_datefrom timestamp without time zone,
    p_dateto timestamp without time zone
)
RETURNS TABLE (
    actid integer,
    evtid integer,
    taskno integer,
    est_time timestamp without time zone,
    title varchar(500),
    actdetails text,
    status varchar(15),
    dependency varchar(50),
    resource varchar(50),
    note text,
    time_started timestamp without time zone,
    systimeentered timestamp without time zone,
    evtdetails text,
    "operator" varchar(50),
    serial integer,
    colour varchar(7)
)
LANGUAGE sql
STABLE
AS $func$

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
        r.colour

    FROM uf_roccarchivereport(
        p_env,
        p_datefrom,
        p_dateto
    ) r

    WHERE r.title ILIKE '%SREQ5%'
       OR r.title ILIKE '%SREQ05%'
       OR r.title ILIKE '%SREQ16%';

$func$;


COMMIT;
