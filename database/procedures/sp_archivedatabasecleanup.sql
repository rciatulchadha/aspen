CREATE OR REPLACE PROCEDURE public.sp_archivedatabasecleanup(IN p_datediff smallint)
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
$procedure$

