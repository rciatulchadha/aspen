BEGIN;

-- ============================================================
-- vw_PassedDueActivities
-- ============================================================

CREATE OR REPLACE VIEW vw_passeddueactivities AS
SELECT
    taskno AS "Task Number",
    est_time AS "Estimated Time",
    title,
    details,

    CASE environment
        WHEN 'v21' THEN 'Vision 21'
        ELSE environment
    END AS environment,

    id

FROM activities

WHERE status = 'None'
  AND est_time < CURRENT_TIMESTAMP
  AND deleted = false;


-- ============================================================
-- vw_ROCC_ActivityListForColour
-- ============================================================

CREATE OR REPLACE VIEW vw_rocc_activitylistforcolour AS
SELECT
    id,

    taskno AS "Task #",

    (
        to_char(est_time, 'MM/DD/YYYY')
        || ' - '
        || to_char(est_time, 'HH24:MI')
    ) AS "Estimated Time",

    est_time,
    title,
    details,
    status,
    closed,
    note,
    dependency,
    resource,
    environment,
    subenvironment,
    criticalact

FROM activities

WHERE deleted = false;


-- ============================================================
-- vw_SLAExceptionReport
-- ============================================================

CREATE OR REPLACE VIEW vw_slaexceptionreport AS
SELECT
    a.taskno,
    a.est_time,
    a.title,
    a.status,

    CASE
        WHEN MIN(e.systimeentered) IS NULL
            THEN CURRENT_TIMESTAMP
        ELSE MIN(e.systimeentered)
    END AS firstevent,

    a.environment,
    a.id

FROM activities a

LEFT JOIN events e
    ON a.id = e.id

WHERE a.est_time <= CURRENT_TIMESTAMP

GROUP BY
    a.id,
    a.taskno,
    a.est_time,
    a.title,
    a.status,
    a.environment;


-- ============================================================
-- vw_StatutoryHolidays
-- ============================================================

CREATE OR REPLACE VIEW vw_statutoryholidays AS
SELECT
    serial,

    (
        to_char(holiday, 'FMMonth')
        || ' '
        || EXTRACT(day FROM holiday)::integer
        || ', '
        || EXTRACT(year FROM holiday)::integer
    ) AS formattedholiday,

    reason

FROM statutoryholidays;


-- ============================================================
-- vw_TurnoverActivities
-- ============================================================

CREATE OR REPLACE VIEW vw_turnoveractivities AS
SELECT
    a.id,
    a.taskno,
    a.est_time,
    a.title,

    COALESCE(t.comments, '') AS comments,

    CASE
        WHEN t.eoxdate IS NULL
            THEN e.description
        ELSE
            e.description
            || ' - '
            || to_char(t.eoxdate, 'FMMonth')
            || ' '
            || EXTRACT(day FROM t.eoxdate)::integer
    END AS envdescription,

    COALESCE(s.description, '') AS subdescription,

    t.serial,
    e.sortorder

FROM activities a

JOIN turnoveractivities t
    ON a.id = t.activityid

JOIN turnoverenvironment e
    ON t.environmentid = e.id

LEFT JOIN turnoversubenvironment s
    ON t.subenvid = s.id
   AND e.id = s.environmentid;


-- ============================================================
-- vw_TurnoverActList
-- ============================================================

CREATE OR REPLACE VIEW vw_turnoveractlist AS
SELECT
    a.id,

    a.taskno AS "Task #",

    (
        to_char(a.est_time, 'MM/DD/YYYY')
        || ' - '
        || to_char(a.est_time, 'HH24:MI')
    ) AS "Estimated Time",

    a.est_time,
    a.title,
    a.details,
    a.status,
    a.closed,
    a.note,
    a.dependency,
    a.resource,

    'turnover'::varchar AS environment,

    a.approved,
    a.criticalact

FROM activities a

JOIN turnoveractivities t
    ON a.id = t.activityid;


-- ============================================================
-- vw_TurnoverBreakPoints
-- ============================================================

CREATE OR REPLACE VIEW vw_turnoverbreakpoints AS

SELECT
    0::integer AS sortorder

UNION

SELECT
    sortorder
FROM turnoverenvironment
WHERE description IN (
    'Mainframe',
    'Scheduling',
    'AS400'
)

UNION

SELECT
    999999::integer AS sortorder;


COMMIT;
