CREATE OR REPLACE PROCEDURE public.sp_automaticdailytaskpopulator(IN p_env character varying, IN p_datediff smallint DEFAULT 1)
 LANGUAGE plpgsql
AS $procedure$

DECLARE
    v_target_date
        timestamp without time zone;

    v_weekday_no
        char(1);

    v_inserted
        integer;

BEGIN

    v_target_date :=
        (
            CURRENT_DATE
            + p_datediff::integer
        )::timestamp without time zone;


    v_weekday_no :=
        EXTRACT(
            ISODOW
            FROM v_target_date
        )::integer::char(1);


    INSERT INTO activities (
        taskno,
        title,
        details,
        note,
        dependency,
        environment,
        subenvironment,
        resource,
        est_time,
        criticalact,
        deleted,
        unplannedact
    )

    SELECT
        f.taskno,
        f.title,
        f.details,
        f.note,
        f.dependency,
        f.environment,
        f.subenvironment,
        f.resource,
        f.est_time,
        f.criticalact,
        f.deleted,
        false

    FROM uf_autoeoxreplacedailylist(
        p_env,
        v_target_date,
        v_weekday_no
    ) f

    WHERE f.taskno IS NOT NULL
      AND f.deleted = false

      AND NOT EXISTS (
          SELECT 1

          FROM activities existing

          WHERE existing.taskno =
                f.taskno

            AND existing.est_time =
                f.est_time

            AND existing.environment =
                f.environment
      );


    GET DIAGNOSTICS
        v_inserted = ROW_COUNT;


    RAISE NOTICE
        'Generated % missing activities for environment %, target date %, weekday %',
        v_inserted,
        p_env,
        v_target_date::date,
        v_weekday_no;

END;

$procedure$

