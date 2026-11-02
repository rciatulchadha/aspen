\set ON_ERROR_STOP on

BEGIN;

-- ============================================================
-- up_ROCC_INSERT_BillingTask
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_rocc_insert_billingtask(
    p_taskno integer,
    p_title varchar(500),
    p_details varchar(500),
    p_env varchar(10),
    p_dependency varchar(50)
)
LANGUAGE plpgsql
AS $proc$
BEGIN
    INSERT INTO activities (
        taskno,
        est_time,
        title,
        details,
        status,
        closed,
        environment,
        subenvironment,
        dependency,
        unplannedact,
        criticalact,
        deleted
    )
    VALUES (
        p_taskno,
        CURRENT_TIMESTAMP,
        p_title,
        p_details,
        'None',
        'No',
        p_env,
        'billing',
        p_dependency,
        false,
        false,
        false
    );
END;
$proc$;


-- ============================================================
-- up_ROCC_INSERT_NewActivity
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_rocc_insert_newactivity(
    p_taskno integer,
    p_est_time timestamp without time zone,
    p_title varchar(500),
    p_details text,
    p_note text,
    p_env varchar(10),
    p_filter varchar(25),
    p_dependency varchar(50),
    p_resource varchar(50),
    p_username varchar(50)
)
LANGUAGE plpgsql
AS $proc$
BEGIN
    INSERT INTO activities (
        taskno,
        est_time,
        title,
        details,
        status,
        closed,
        note,
        environment,
        subenvironment,
        dependency,
        resource,
        unplannedact,
        criticalact,
        deleted
    )
    VALUES (
        p_taskno,
        p_est_time,
        p_title,
        p_details,
        'None',
        'No',
        'Unplanned Task added by ROCC ('
            || p_username
            || ').  '
            || COALESCE(p_note, ''),
        p_env,
        p_filter,
        p_dependency,
        p_resource,
        true,
        false,
        false
    );
END;
$proc$;


-- ============================================================
-- up_ROCC_INSERT_NewEvent
--
-- Preserves legacy behavior:
--   event number = existing event count + 1
--   event number is prefixed to Details
--   activity status changes from None to Open
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_rocc_insert_newevent(
    p_activityid integer,
    p_time_started timestamp without time zone,
    p_details text,
    p_operator varchar(50)
)
LANGUAGE plpgsql
AS $proc$
DECLARE
    v_event_count integer;
    v_event_details text;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM activities
        WHERE id = p_activityid
    ) THEN
        RAISE EXCEPTION
            'Activity ID % does not exist',
            p_activityid;
    END IF;

    SELECT COUNT(*)
    INTO v_event_count
    FROM events
    WHERE id = p_activityid;

    v_event_details :=
        (v_event_count + 1)::text
        || ': '
        || COALESCE(p_details, '');

    INSERT INTO events (
        id,
        time_updated,
        time_started,
        systimeentered,
        details,
        operator
    )
    VALUES (
        p_activityid,
        CURRENT_TIMESTAMP,
        p_time_started,
        CURRENT_TIMESTAMP,
        v_event_details,
        p_operator
    );

    UPDATE activities
    SET status = 'Open'
    WHERE id = p_activityid
      AND status = 'None';
END;
$proc$;

COMMIT;
