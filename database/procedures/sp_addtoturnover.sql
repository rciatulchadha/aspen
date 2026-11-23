CREATE OR REPLACE PROCEDURE public.sp_addtoturnover(IN p_activityid integer, IN p_env character varying, IN p_subenv character varying DEFAULT NULL::character varying, IN p_comments text DEFAULT NULL::text, IN p_eoxdate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_environmentid integer;
    v_subenvid integer;
BEGIN

    -- Validate Activity first.
    IF NOT EXISTS (
        SELECT 1
        FROM activities
        WHERE id = p_activityid
    ) THEN
        RAISE EXCEPTION
            'Activity ID % does not exist',
            p_activityid;
    END IF;


    -- Resolve Turnover Environment.
    SELECT id
    INTO v_environmentid
    FROM turnoverenvironment
    WHERE description = p_env;


    IF v_environmentid IS NULL THEN
        RAISE EXCEPTION
            'Turnover environment % does not exist',
            p_env;
    END IF;


    -- No SubEnvironment supplied.
    IF p_subenv IS NULL THEN

        INSERT INTO turnoveractivities (
            activityid,
            environmentid,
            subenvid,
            comments,
            eoxdate
        )
        VALUES (
            p_activityid,
            v_environmentid,
            NULL,
            p_comments,
            p_eoxdate
        );

    ELSE

        -- Resolve SubEnvironment belonging to Environment.
        SELECT id
        INTO v_subenvid
        FROM turnoversubenvironment
        WHERE environmentid = v_environmentid
          AND description = p_subenv;


        IF v_subenvid IS NULL THEN
            RAISE EXCEPTION
                'Turnover subenvironment % does not exist for environment %',
                p_subenv,
                p_env;
        END IF;


        INSERT INTO turnoveractivities (
            activityid,
            environmentid,
            subenvid,
            comments,
            eoxdate
        )
        VALUES (
            p_activityid,
            v_environmentid,
            v_subenvid,
            p_comments,
            p_eoxdate
        );

    END IF;

END;
$procedure$

