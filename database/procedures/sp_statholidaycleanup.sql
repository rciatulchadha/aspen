CREATE OR REPLACE PROCEDURE public.sp_statholidaycleanup()
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$

