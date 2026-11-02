\set ON_ERROR_STOP on

BEGIN;


-- ============================================================
-- 1. sp_databasecleanup
--
-- SQL Server: up_DatabaseCleanup
--
-- Archive closed activities older than p_datediff days.
-- Related Events are archived.
-- Related TurnoverActivities are removed.
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_databasecleanup(
    p_datediff smallint
)
LANGUAGE plpgsql
AS $proc$
DECLARE
    v_cutoff timestamp without time zone;
    v_activity_count integer;
BEGIN

    v_cutoff :=
        CURRENT_TIMESTAMP
        - (p_datediff::integer * INTERVAL '1 day');

    SELECT COUNT(*)
    INTO v_activity_count
    FROM activities
    WHERE closed = 'Yes'
      AND est_time < v_cutoff;

    -- Archive events belonging to qualifying activities.
    INSERT INTO archived_events (
        id,
        time_updated,
        time_started,
        systimeentered,
        details,
        operator,
        serial
    )
    SELECT
        e.id,
        e.time_updated,
        e.time_started,
        e.systimeentered,
        e.details,
        e.operator,
        e.serial
    FROM events e
    JOIN activities a
        ON a.id = e.id
    WHERE a.closed = 'Yes'
      AND a.est_time < v_cutoff;

    -- Remove live events.
    DELETE FROM events e
    USING activities a
    WHERE e.id = a.id
      AND a.closed = 'Yes'
      AND a.est_time < v_cutoff;

    -- Remove Turnover report relationships.
    DELETE FROM turnoveractivities t
    USING activities a
    WHERE t.activityid = a.id
      AND a.closed = 'Yes'
      AND a.est_time < v_cutoff;

    -- Archive activities.
    INSERT INTO archived_activities (
        id,
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
        approved,
        unplannedact,
        criticalact,
        deleted
    )
    SELECT
        id,
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
        approved,
        unplannedact,
        criticalact,
        deleted
    FROM activities
    WHERE closed = 'Yes'
      AND est_time < v_cutoff;

    -- Remove archived activities from live table.
    DELETE FROM activities
    WHERE closed = 'Yes'
      AND est_time < v_cutoff;

    RAISE NOTICE
        'Archived % activities older than %',
        v_activity_count,
        v_cutoff;

END;
$proc$;



-- ============================================================
-- 2. sp_archivedatabasecleanup
--
-- SQL Server: up_ArchiveDatabaseCleanup
--
-- Permanently remove archive records older than p_datediff.
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_archivedatabasecleanup(
    p_datediff smallint
)
LANGUAGE plpgsql
AS $proc$
DECLARE
    v_cutoff timestamp without time zone;
    v_activity_count integer;
BEGIN

    v_cutoff :=
        CURRENT_TIMESTAMP
        - (p_datediff::integer * INTERVAL '1 day');

    SELECT COUNT(*)
    INTO v_activity_count
    FROM archived_activities
    WHERE est_time < v_cutoff;

    DELETE FROM archived_events e
    USING archived_activities a
    WHERE e.id = a.id
      AND a.est_time < v_cutoff;

    DELETE FROM archived_activities
    WHERE est_time < v_cutoff;

    RAISE NOTICE
        'Deleted % archived activities older than %',
        v_activity_count,
        v_cutoff;

END;
$proc$;



-- ============================================================
-- 3. sp_databasecleanupbyenvironment
--
-- SQL Server: up_DatabaseCleanupByEnvironment
--
-- Deletes all activity/event rows for an environment.
--
-- The SQL Server parameter was declared as NVARCHAR without
-- an explicit length. PostgreSQL uses varchar(10), matching
-- activities.environment.
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_databasecleanupbyenvironment(
    p_environment varchar(10)
)
LANGUAGE plpgsql
AS $proc$
DECLARE
    v_activity_count integer;
BEGIN

    SELECT COUNT(*)
    INTO v_activity_count
    FROM activities
    WHERE environment = p_environment;

    DELETE FROM events e
    USING activities a
    WHERE e.id = a.id
      AND a.environment = p_environment;

    -- Required because PostgreSQL enforces this FK.
    DELETE FROM turnoveractivities t
    USING activities a
    WHERE t.activityid = a.id
      AND a.environment = p_environment;

    DELETE FROM activities
    WHERE environment = p_environment;

    RAISE NOTICE
        'Deleted % activities for environment %',
        v_activity_count,
        p_environment;

END;
$proc$;



-- ============================================================
-- 4. sp_sched_cleanupturnovermps
--
-- SQL Server: up_SCHED_CleanupTurnoverMPS
--
-- Legacy algorithm:
--
-- cutoff = MAX(TurnoverMPS.ID) - p_iddiff
--
-- delete cycles where MPSID < cutoff
-- delete MPS where ID < cutoff
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_sched_cleanupturnovermps(
    p_iddiff integer DEFAULT 100
)
LANGUAGE plpgsql
AS $proc$
DECLARE
    v_cutoff_id integer;
BEGIN

    SELECT MAX(id) - p_iddiff
    INTO v_cutoff_id
    FROM turnovermps;

    IF v_cutoff_id IS NULL THEN
        RETURN;
    END IF;

    DELETE FROM turnovermpscycles
    WHERE mpsid < v_cutoff_id;

    DELETE FROM turnovermps
    WHERE id < v_cutoff_id;

    RAISE NOTICE
        'TurnoverMPS cleanup cutoff ID = %',
        v_cutoff_id;

END;
$proc$;
-- ============================================================
-- 5. sp_statholidaycleanup
--
-- Migration of:
-- dbo.up_StatHolidayCleanUp
--
-- Deletes statutory holidays older than three months.
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_statholidaycleanup()
LANGUAGE plpgsql
AS $proc$
DECLARE
    v_deleted integer;
BEGIN

    DELETE FROM statutoryholidays
    WHERE holiday <
          CURRENT_TIMESTAMP - INTERVAL '3 months';

    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    RAISE NOTICE
        'Deleted % old statutory holiday rows',
        v_deleted;

END;
$proc$;
commit;
