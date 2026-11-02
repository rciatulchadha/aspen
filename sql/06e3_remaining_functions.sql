\set ON_ERROR_STOP on

BEGIN;


-- ============================================================
-- 1. uf_GetMPSStatus
-- ============================================================

CREATE OR REPLACE FUNCTION uf_getmpsstatus(
    p_mpsenv varchar(10)
)
RETURNS TABLE (
    description varchar(100)
)
LANGUAGE sql
STABLE
AS $func$

    SELECT
        s.description
    FROM turnovermpsstatus s
    WHERE s.statusenvironment IN (
        p_mpsenv,
        'All'
    )
    ORDER BY s.sortorder;

$func$;



-- ============================================================
-- 2. uf_GetTOActDetails
-- ============================================================

CREATE OR REPLACE FUNCTION uf_gettoactdetails(
    p_id integer
)
RETURNS TABLE (
    envdescription varchar(50),
    subenvdescription varchar(50),
    eoxdate timestamp without time zone,
    comments text
)
LANGUAGE sql
STABLE
AS $func$

    SELECT
        e.description::varchar(50),

        COALESCE(
            s.description,
            ''
        )::varchar(50),

        a.eoxdate,

        COALESCE(
            a.comments,
            ''
        )::text

    FROM turnoveractivities a

    JOIN turnoverenvironment e
        ON a.environmentid = e.id

    LEFT JOIN turnoversubenvironment s
        ON a.subenvid = s.id
       AND e.id = s.environmentid

    WHERE a.serial = p_id;

$func$;



-- ============================================================
-- 3. uf_SubEnvsForEnv
-- ============================================================

CREATE OR REPLACE FUNCTION uf_subenvsforenv(
    p_env varchar(50)
)
RETURNS TABLE (
    description varchar(50)
)
LANGUAGE sql
STABLE
AS $func$

    SELECT
        s.description

    FROM turnoversubenvironment s

    JOIN turnoverenvironment e
        ON s.environmentid = e.id

    WHERE e.description = p_env

    ORDER BY s.sortorder;

$func$;



-- ============================================================
-- 4. uf_PCActivityList
-- ============================================================

CREATE OR REPLACE FUNCTION uf_pcactivitylist(
    p_env varchar(10),
    p_datefrom timestamp without time zone,
    p_dateto timestamp without time zone
)
RETURNS SETOF activities
LANGUAGE sql
STABLE
AS $func$

    SELECT a.*

    FROM activities a

    WHERE a.environment = p_env

      AND a.est_time
          BETWEEN p_datefrom AND p_dateto

      AND a.status = 'None'

      AND a.unplannedact = false

      AND a.deleted = false

    ORDER BY a.est_time;

$func$;



-- ============================================================
-- 5. uf_ProdControlReport
-- ============================================================

CREATE OR REPLACE FUNCTION uf_prodcontrolreport(
    p_env varchar(10),
    p_datefrom timestamp without time zone,
    p_dateto timestamp without time zone
)
RETURNS TABLE (
    taskno integer,
    est_time timestamp without time zone,
    title varchar(500),
    details text,
    note text,
    dependency varchar(50),
    resource varchar(50)
)
LANGUAGE sql
STABLE
AS $func$

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

$func$;



-- ============================================================
-- 6. uf_ROCCBillingFYIReport
--
-- PostgreSQL conversion of:
-- dbo.uf_ROCCBillingFYIReport
-- ============================================================

CREATE OR REPLACE FUNCTION uf_roccbillingfyireport(
    p_repdate timestamp without time zone,
    p_hourrange integer
)
RETURNS TABLE (
    title varchar(500),
    status varchar(15),
    id integer,
    systimeentered timestamp without time zone
)
LANGUAGE sql
STABLE
AS $func$

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

$func$;



-- ============================================================
-- 7. uf_SLAExceptionReport
--
-- Uses vw_slaexceptionreport.
--
-- Legacy DATEDIFF(minute, Est_Time, FirstEvent)
-- converted to epoch seconds / 60.
-- ============================================================

CREATE OR REPLACE FUNCTION uf_slaexceptionreport(
    p_taskstart char(1),
    p_repdate timestamp without time zone,
    p_env varchar(10),
    p_difference integer
)
RETURNS TABLE (
    taskno integer,
    title varchar(500),
    est_time timestamp without time zone,
    firstevent timestamp without time zone,
    status varchar(15),
    difference integer,
    id integer
)
LANGUAGE sql
STABLE
AS $func$

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

$func$;



-- ============================================================
-- 8. uf_UsedTaskNumbers
-- ============================================================

CREATE OR REPLACE FUNCTION uf_usedtasknumbers(
    p_env varchar(10),
    p_weekday char(1),
    p_tasklength integer
)
RETURNS TABLE (
    taskno integer
)
LANGUAGE sql
STABLE
AS $func$

    SELECT
        d.taskno::integer

    FROM dailytasks d

    WHERE d.environment = p_env

      AND d.taskno BETWEEN

          (
              p_weekday
              || repeat(
                    '0',
                    p_tasklength
                 )
          )::integer

          AND

          (
              p_weekday
              || '4'
              || repeat(
                    '9',
                    p_tasklength - 1
                 )
          )::integer

    ORDER BY d.taskno;

$func$;



-- ============================================================
-- 9. uf_AvailableTaskNumbers
--
-- Legacy SQL Server function generated values in a WHILE loop,
-- then removed values already assigned in DailyTasks.
--
-- PostgreSQL generate_series replaces the loop.
-- ============================================================

CREATE OR REPLACE FUNCTION uf_availabletasknumbers(
    p_weekday char(1),
    p_env varchar(10)
)
RETURNS TABLE (
    taskno integer
)
LANGUAGE plpgsql
STABLE
AS $func$

DECLARE
    v_tasklength integer;
    v_start integer;
    v_max integer;

BEGIN

    IF p_weekday::integer > 7 THEN
        RETURN;
    END IF;


    SELECT
        tasklength - 1

    INTO v_tasklength

    FROM vw_environment_pc

    WHERE dbkey = p_env;


    IF v_tasklength IS NULL THEN
        RETURN;
    END IF;


    v_start :=
        (
            p_weekday
            || repeat(
                '0',
                v_tasklength
            )
        )::integer;


    v_max :=
        v_start
        +
        (
            '4'
            || repeat(
                '9',
                v_tasklength - 1
            )
        )::integer;


    RETURN QUERY

    SELECT
        g.taskno

    FROM generate_series(
        v_start,
        v_max
    ) AS g(taskno)

    WHERE NOT EXISTS (
        SELECT 1

        FROM dailytasks d

        WHERE d.environment = p_env
          AND d.taskno = g.taskno
    )

    ORDER BY g.taskno;

END;

$func$;



-- ============================================================
-- 10. uf_TemplatedTasksString
--
-- Legacy SQL Server used nested cursors.
--
-- Output example concept:
-- (1001,2001,3001,...)
-- ============================================================

CREATE OR REPLACE FUNCTION uf_templatedtasksstring(
    p_env varchar(10) DEFAULT 'v21'
)
RETURNS varchar(400)
LANGUAGE sql
STABLE
AS $func$

    SELECT

        CASE

            WHEN COUNT(*) = 0
                THEN '('''')'

            ELSE
                '('
                ||
                string_agg(
                    d.day_no::text
                    || t.tasknumber,
                    ','
                    ORDER BY
                        t.id,
                        d.day_no
                )
                ||
                ')'

        END::varchar(400)

    FROM templatedactivities t

    CROSS JOIN generate_series(
        1,
        7
    ) AS d(day_no)

    WHERE t.environment = p_env;

$func$;



-- ============================================================
-- 11. uf_PCTemplatedActivitesByEnv
--
-- NOTE:
-- The legacy SQL Server function itself used the misspelling
-- "Activites", so that spelling is preserved here.
-- ============================================================

CREATE OR REPLACE FUNCTION uf_pctemplatedactivitesbyenv(
    p_envdesc varchar(20)
)
RETURNS SETOF dailytasks
LANGUAGE sql
STABLE
AS $func$

    SELECT
        d.*

    FROM dailytasks d

    JOIN vw_environment_pc e
        ON d.environment = e.dbkey

    WHERE e.description = p_envdesc

      AND (
            d.taskno < 100

            OR

            right(
                d.taskno::text,
                3
            ) IN (
                SELECT t.tasknumber
                FROM templatedactivities t
                WHERE t.environment = e.dbkey
            )
          )

    ORDER BY
        d.taskno,
        d.time;

$func$;


COMMIT;

