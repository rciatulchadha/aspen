CREATE OR REPLACE PROCEDURE public.sp_sched_cleanupturnovermps(IN p_iddiff integer DEFAULT 100)
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$

