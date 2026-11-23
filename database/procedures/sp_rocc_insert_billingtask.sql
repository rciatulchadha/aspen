CREATE OR REPLACE PROCEDURE public.sp_rocc_insert_billingtask(IN p_taskno integer, IN p_title character varying, IN p_details character varying, IN p_env character varying, IN p_dependency character varying)
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$

