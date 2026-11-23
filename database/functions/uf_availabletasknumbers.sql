CREATE OR REPLACE FUNCTION public.uf_availabletasknumbers(p_weekday character, p_env character varying)
 RETURNS TABLE(taskno integer)
 LANGUAGE plpgsql
 STABLE
AS $function$

DECLARE
    v_tasklength integer;
    v_start integer;
    v_max integer;

BEGIN

    IF p_weekday::integer > 7 THEN
        RETURN;
    END IF;


    SELECT
        tasklength - 1

    INTO v_tasklength

    FROM vw_environment_pc

    WHERE dbkey = p_env;


    IF v_tasklength IS NULL THEN
        RETURN;
    END IF;


    v_start :=
        (
            p_weekday
            || repeat(
                '0',
                v_tasklength
            )
        )::integer;


    v_max :=
        v_start
        +
        (
            '4'
            || repeat(
                '9',
                v_tasklength - 1
            )
        )::integer;


    RETURN QUERY

    SELECT
        g.taskno

    FROM generate_series(
        v_start,
        v_max
    ) AS g(taskno)

    WHERE NOT EXISTS (
        SELECT 1

        FROM dailytasks d

        WHERE d.environment = p_env
          AND d.taskno = g.taskno
    )

    ORDER BY g.taskno;

END;

$function$

