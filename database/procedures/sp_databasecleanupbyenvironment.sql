CREATE OR REPLACE PROCEDURE public.sp_databasecleanupbyenvironment(IN p_environment character varying)
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$

