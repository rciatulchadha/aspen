\set ON_ERROR_STOP on

BEGIN;


-- ============================================================
-- sp_addtoturnover
--
-- Migration of:
-- dbo.up_AddToTurnover
--
-- Resolves Turnover Environment/SubEnvironment descriptions
-- to their IDs and inserts TurnoverActivities.
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_addtoturnover(
    p_activityid integer,
    p_env varchar(50),
    p_subenv varchar(50) DEFAULT NULL,
    p_comments text DEFAULT NULL,
    p_eoxdate timestamp without time zone DEFAULT NULL
)
LANGUAGE plpgsql
AS $proc$
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
$proc$;



-- ============================================================
-- sp_addturnovermps
--
-- Migration of:
-- dbo.up_AddTurnoverMPS
--
-- The SQL Server procedure inserted TurnoverMPS then searched
-- for MAX(ID) matching the inserted data.
--
-- PostgreSQL uses INSERT ... RETURNING, removing that race.
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_addturnovermps(
    p_collections integer,
    p_maindrivers integer,
    p_guiders integer,
    p_mpupappgd timestamp without time zone,
    p_cycle1 varchar(150),
    p_cycle2 varchar(150) DEFAULT '',
    p_cycle3 varchar(150) DEFAULT '',
    p_cycle4 varchar(150) DEFAULT '',
    p_cycle5 varchar(150) DEFAULT '',
    p_cycle6 varchar(150) DEFAULT '',
    p_premaf1date timestamp without time zone DEFAULT NULL,
    p_premaf1status varchar(100) DEFAULT NULL,
    p_premaf4date timestamp without time zone DEFAULT NULL,
    p_premaf4status varchar(100) DEFAULT NULL,
    p_volser1 varchar(7) DEFAULT NULL,
    p_volser2 varchar(7) DEFAULT NULL,
    p_volser3 varchar(7) DEFAULT NULL
)
LANGUAGE plpgsql
AS $proc$
DECLARE
    v_mpsid integer;
BEGIN

    INSERT INTO turnovermps (
        collections,
        maindrivers,
        guiders,
        mpupappgdtime,
        premaf1date,
        premaf1status,
        premaf4date,
        premaf4status,
        cibervolser1,
        cibervolser2,
        cibervolser3
    )
    VALUES (
        p_collections,
        p_maindrivers,
        p_guiders,
        p_mpupappgd,
        p_premaf1date,
        p_premaf1status,
        p_premaf4date,
        p_premaf4status,
        p_volser1,
        p_volser2,
        p_volser3
    )
    RETURNING id
    INTO v_mpsid;


    -- Cycle 1 was mandatory in the legacy procedure.
    INSERT INTO turnovermpscycles (
        mpsid,
        cycledetails
    )
    VALUES (
        v_mpsid,
        p_cycle1
    );


    IF COALESCE(p_cycle2, '') != '' THEN
        INSERT INTO turnovermpscycles (
            mpsid,
            cycledetails
        )
        VALUES (
            v_mpsid,
            p_cycle2
        );
    END IF;


    IF COALESCE(p_cycle3, '') != '' THEN
        INSERT INTO turnovermpscycles (
            mpsid,
            cycledetails
        )
        VALUES (
            v_mpsid,
            p_cycle3
        );
    END IF;


    IF COALESCE(p_cycle4, '') != '' THEN
        INSERT INTO turnovermpscycles (
            mpsid,
            cycledetails
        )
        VALUES (
            v_mpsid,
            p_cycle4
        );
    END IF;


    IF COALESCE(p_cycle5, '') != '' THEN
        INSERT INTO turnovermpscycles (
            mpsid,
            cycledetails
        )
        VALUES (
            v_mpsid,
            p_cycle5
        );
    END IF;


    IF COALESCE(p_cycle6, '') != '' THEN
        INSERT INTO turnovermpscycles (
            mpsid,
            cycledetails
        )
        VALUES (
            v_mpsid,
            p_cycle6
        );
    END IF;

END;
$proc$;



-- ============================================================
-- sp_incrementinfotaskno
--
-- Migration of:
-- dbo.up_IncrementInfoTaskNo
--
-- Examples from legacy comments:
--
-- 199  -> 150
-- 1999 -> 1500
--
-- Otherwise TaskNo increases by 1.
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_incrementinfotaskno(
    p_taskno integer,
    p_env varchar(10)
)
LANGUAGE plpgsql
AS $proc$
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
$proc$;


COMMIT;
