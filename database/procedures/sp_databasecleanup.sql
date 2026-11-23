CREATE OR REPLACE PROCEDURE public.sp_databasecleanup(IN p_datediff smallint)
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$

