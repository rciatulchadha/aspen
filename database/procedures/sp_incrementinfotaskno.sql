CREATE OR REPLACE PROCEDURE public.sp_incrementinfotaskno(IN p_taskno integer, IN p_env character varying)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_task_text text;
    v_suffix text;
    v_expected_nines text;
    v_new_taskno integer;
BEGIN

    v_task_text := p_taskno::text;

    -- Equivalent to:
    -- RIGHT(@TaskNo, LEN(@TaskNo) - 1)

    v_suffix :=
        substring(
            v_task_text
            FROM 2
        );


    v_expected_nines :=
        repeat(
            '9',
            length(v_task_text) - 1
        );


    IF v_suffix = v_expected_nines THEN

        v_new_taskno :=
            (
                substring(v_task_text FROM 1 FOR 1)
                || '5'
                || repeat(
                    '0',
                    length(v_task_text) - 2
                )
            )::integer;

    ELSE

        v_new_taskno :=
            p_taskno + 1;

    END IF;


    UPDATE infotaskno

    SET taskno = v_new_taskno

    WHERE environment = p_env
      AND taskno = p_taskno;


    IF NOT FOUND THEN
        RAISE EXCEPTION
            'InfoTaskNo record not found for environment %, TaskNo %',
            p_env,
            p_taskno;
    END IF;

END;
$procedure$

