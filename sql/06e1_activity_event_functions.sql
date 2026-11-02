\set ON_ERROR_STOP on

BEGIN;


-- ============================================================
-- uf_activitywithevent
--
-- PostgreSQL conversion of:
-- dbo.uf_ActivityWithEvent
--
-- Returns one activity joined to:
--   - zero or more Events
--   - OpsReportStatusColour
--
-- If the activity has no events, event columns are NULL.
-- ============================================================

CREATE OR REPLACE FUNCTION uf_activitywithevent(
    p_id integer
)
RETURNS TABLE (
    taskno integer,
    est_time timestamp without time zone,
    title varchar(500),
    actdetails text,
    status varchar(15),
    note text,
    dependency varchar(50),
    resource varchar(50),
    time_started timestamp without time zone,
    evtdetails text,
    "operator" varchar(50),
    colour varchar(7)
)
LANGUAGE sql
STABLE
AS $func$

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

$func$;



-- ============================================================
-- uf_toactivitywithevent
--
-- PostgreSQL conversion of:
-- dbo.uf_TOActivityWithEvent
--
-- Adds TurnoverActivities comments when present.
-- ============================================================

CREATE OR REPLACE FUNCTION uf_toactivitywithevent(
    p_id integer
)
RETURNS TABLE (
    taskno integer,
    est_time timestamp without time zone,
    title varchar(500),
    actdetails text,
    status varchar(15),
    note text,
    dependency varchar(50),
    resource varchar(50),
    time_started timestamp without time zone,
    evtdetails text,
    "operator" varchar(50),
    colour varchar(7),
    comments text
)
LANGUAGE sql
STABLE
AS $func$

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
        c.colour::varchar(7) AS colour,
        t.comments

    FROM activities a

    LEFT JOIN events e
        ON a.id = e.id

    LEFT JOIN turnoveractivities t
        ON a.id = t.activityid

    JOIN opsreportstatuscolour c
        ON a.status = c.status

    WHERE a.id = p_id

    ORDER BY
        e.time_started,
        e.serial;

$func$;


COMMIT;
