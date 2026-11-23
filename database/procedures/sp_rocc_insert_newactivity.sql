CREATE OR REPLACE PROCEDURE public.sp_rocc_insert_newactivity(IN p_taskno integer, IN p_est_time timestamp without time zone, IN p_title character varying, IN p_details text, IN p_note text, IN p_env character varying, IN p_filter character varying, IN p_dependency character varying, IN p_resource character varying, IN p_username character varying)
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
$procedure$

