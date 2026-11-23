CREATE OR REPLACE PROCEDURE public.sp_rocc_insert_newevent(IN p_activityid integer, IN p_time_started timestamp without time zone, IN p_details text, IN p_operator character varying)
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$

