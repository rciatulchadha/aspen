--
-- PostgreSQL database dump
--

-- Dumped from database version 15.12
-- Dumped by pg_dump version 15.12

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--



--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--



--
-- Name: sp_addtoturnover(integer, character varying, character varying, text, timestamp without time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_addtoturnover(IN p_activityid integer, IN p_env character varying, IN p_subenv character varying DEFAULT NULL::character varying, IN p_comments text DEFAULT NULL::text, IN p_eoxdate timestamp without time zone DEFAULT NULL::timestamp without time zone)
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: sp_addturnovermps(integer, integer, integer, timestamp without time zone, character varying, character varying, character varying, character varying, character varying, character varying, timestamp without time zone, character varying, timestamp without time zone, character varying, character varying, character varying, character varying); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_addturnovermps(IN p_collections integer, IN p_maindrivers integer, IN p_guiders integer, IN p_mpupappgd timestamp without time zone, IN p_cycle1 character varying, IN p_cycle2 character varying DEFAULT ''::character varying, IN p_cycle3 character varying DEFAULT ''::character varying, IN p_cycle4 character varying DEFAULT ''::character varying, IN p_cycle5 character varying DEFAULT ''::character varying, IN p_cycle6 character varying DEFAULT ''::character varying, IN p_premaf1date timestamp without time zone DEFAULT NULL::timestamp without time zone, IN p_premaf1status character varying DEFAULT NULL::character varying, IN p_premaf4date timestamp without time zone DEFAULT NULL::timestamp without time zone, IN p_premaf4status character varying DEFAULT NULL::character varying, IN p_volser1 character varying DEFAULT NULL::character varying, IN p_volser2 character varying DEFAULT NULL::character varying, IN p_volser3 character varying DEFAULT NULL::character varying)
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: sp_archivedatabasecleanup(smallint); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_archivedatabasecleanup(IN p_datediff smallint)
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: sp_automaticdailytaskpopulator(character varying, smallint); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_automaticdailytaskpopulator(IN p_env character varying, IN p_datediff smallint DEFAULT 1)
    LANGUAGE plpgsql
    AS $$

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

$$;


--
-- Name: sp_databasecleanup(smallint); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_databasecleanup(IN p_datediff smallint)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_cutoff timestamp without time zone;
    v_activity_count integer;
BEGIN

    v_cutoff :=
        CURRENT_TIMESTAMP
        - (p_datediff::integer * INTERVAL '1 day');

    SELECT COUNT(*)
    INTO v_activity_count
    FROM activities
    WHERE closed = 'Yes'
      AND est_time < v_cutoff;

    -- Archive events belonging to qualifying activities.
    INSERT INTO archived_events (
        id,
        time_updated,
        time_started,
        systimeentered,
        details,
        operator,
        serial
    )
    SELECT
        e.id,
        e.time_updated,
        e.time_started,
        e.systimeentered,
        e.details,
        e.operator,
        e.serial
    FROM events e
    JOIN activities a
        ON a.id = e.id
    WHERE a.closed = 'Yes'
      AND a.est_time < v_cutoff;

    -- Remove live events.
    DELETE FROM events e
    USING activities a
    WHERE e.id = a.id
      AND a.closed = 'Yes'
      AND a.est_time < v_cutoff;

    -- Remove Turnover report relationships.
    DELETE FROM turnoveractivities t
    USING activities a
    WHERE t.activityid = a.id
      AND a.closed = 'Yes'
      AND a.est_time < v_cutoff;

    -- Archive activities.
    INSERT INTO archived_activities (
        id,
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
        approved,
        unplannedact,
        criticalact,
        deleted
    )
    SELECT
        id,
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
        approved,
        unplannedact,
        criticalact,
        deleted
    FROM activities
    WHERE closed = 'Yes'
      AND est_time < v_cutoff;

    -- Remove archived activities from live table.
    DELETE FROM activities
    WHERE closed = 'Yes'
      AND est_time < v_cutoff;

    RAISE NOTICE
        'Archived % activities older than %',
        v_activity_count,
        v_cutoff;

END;
$$;


--
-- Name: sp_databasecleanupbyenvironment(character varying); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_databasecleanupbyenvironment(IN p_environment character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_activity_count integer;
BEGIN

    SELECT COUNT(*)
    INTO v_activity_count
    FROM activities
    WHERE environment = p_environment;

    DELETE FROM events e
    USING activities a
    WHERE e.id = a.id
      AND a.environment = p_environment;

    -- Required because PostgreSQL enforces this FK.
    DELETE FROM turnoveractivities t
    USING activities a
    WHERE t.activityid = a.id
      AND a.environment = p_environment;

    DELETE FROM activities
    WHERE environment = p_environment;

    RAISE NOTICE
        'Deleted % activities for environment %',
        v_activity_count,
        p_environment;

END;
$$;


--
-- Name: sp_incrementinfotaskno(integer, character varying); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_incrementinfotaskno(IN p_taskno integer, IN p_env character varying)
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: sp_rocc_insert_billingtask(integer, character varying, character varying, character varying, character varying); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_rocc_insert_billingtask(IN p_taskno integer, IN p_title character varying, IN p_details character varying, IN p_env character varying, IN p_dependency character varying)
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: sp_rocc_insert_newactivity(integer, timestamp without time zone, character varying, text, text, character varying, character varying, character varying, character varying, character varying); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_rocc_insert_newactivity(IN p_taskno integer, IN p_est_time timestamp without time zone, IN p_title character varying, IN p_details text, IN p_note text, IN p_env character varying, IN p_filter character varying, IN p_dependency character varying, IN p_resource character varying, IN p_username character varying)
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: sp_rocc_insert_newevent(integer, timestamp without time zone, text, character varying); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_rocc_insert_newevent(IN p_activityid integer, IN p_time_started timestamp without time zone, IN p_details text, IN p_operator character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_event_count integer;
    v_event_details text;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM activities
        WHERE id = p_activityid
    ) THEN
        RAISE EXCEPTION
            'Activity ID % does not exist',
            p_activityid;
    END IF;

    SELECT COUNT(*)
    INTO v_event_count
    FROM events
    WHERE id = p_activityid;

    v_event_details :=
        (v_event_count + 1)::text
        || ': '
        || COALESCE(p_details, '');

    INSERT INTO events (
        id,
        time_updated,
        time_started,
        systimeentered,
        details,
        operator
    )
    VALUES (
        p_activityid,
        CURRENT_TIMESTAMP,
        p_time_started,
        CURRENT_TIMESTAMP,
        v_event_details,
        p_operator
    );

    UPDATE activities
    SET status = 'Open'
    WHERE id = p_activityid
      AND status = 'None';
END;
$$;


--
-- Name: sp_sched_cleanupturnovermps(integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_sched_cleanupturnovermps(IN p_iddiff integer DEFAULT 100)
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: sp_statholidaycleanup(); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_statholidaycleanup()
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: uf_activitywithevent(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_activitywithevent(p_id integer) RETURNS TABLE(taskno integer, est_time timestamp without time zone, title character varying, actdetails text, status character varying, note text, dependency character varying, resource character varying, time_started timestamp without time zone, evtdetails text, operator character varying, colour character varying)
    LANGUAGE sql STABLE
    AS $$

    SELECT
        a.taskno,
        a.est_time,
        a.title,
        a.details AS actdetails,
        a.status,
        a.note,
        a.dependency,
        a.resource,
        e.time_started,
        e.details AS evtdetails,
        e.operator::varchar(50) AS "operator",
        c.colour::varchar(7) AS colour

    FROM activities a

    LEFT JOIN events e
        ON a.id = e.id

    JOIN opsreportstatuscolour c
        ON a.status = c.status

    WHERE a.id = p_id

    ORDER BY
        e.time_started,
        e.serial;

$$;


--
-- Name: uf_autoeoxdailylist(character varying, character, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_autoeoxdailylist(p_env character varying, p_weekday character, p_tasklength integer) RETURNS TABLE(taskno integer, title character varying, details text, note text, dependency character varying, environment character varying, subenvironment character varying, resource character varying, "time" character varying, criticalact boolean, deleted boolean)
    LANGUAGE sql STABLE
    AS $$

    SELECT
        d.taskno,
        d.title,
        d.details,
        d.note,
        d.dependency,
        d.environment,
        d.subenvironment,
        d.resource,
        d."time"::varchar(5),
        d.criticalact,
        d.deleted

    FROM dailytasks d

    WHERE d.environment = p_env

      AND (
            d.taskno BETWEEN 0 AND 99

            OR

            d.taskno BETWEEN
                (
                    p_weekday
                    || repeat(
                        '0',
                        p_tasklength
                    )
                )::integer

                AND

                (
                    p_weekday
                    || repeat(
                        '9',
                        p_tasklength
                    )
                )::integer
          )

      AND d.deleted = false

    ORDER BY
        d."time"::time,
        d.taskno;

$$;


--
-- Name: uf_autoeoxreplace(character varying, integer, timestamp without time zone, character); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_autoeoxreplace(p_templatedstring character varying, p_taskno integer, p_today timestamp without time zone, p_weekdayno character) RETURNS character varying
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    v_result text;
    v_jobtype varchar(20);
    v_tomorrow timestamp without time zone;
BEGIN
    IF p_templatedstring IS NULL THEN
        RETURN NULL;
    END IF;

    v_result := p_templatedstring;
    v_tomorrow := p_today + INTERVAL '1 day';

    v_jobtype :=
        CASE
            WHEN p_weekdayno = '7'
             AND EXTRACT(month FROM p_today)
                 != EXTRACT(month FROM v_tomorrow)
                THEN 'EOD/EOW/EOM'

            WHEN p_weekdayno = '7'
                THEN 'EOD/EOW'

            WHEN EXTRACT(month FROM p_today)
                 != EXTRACT(month FROM v_tomorrow)
                THEN 'EOD/EOM'

            ELSE 'EOD'
        END;

    v_result := replace(v_result, 'EOX', v_jobtype);

    v_result := replace(
        v_result,
        'TODAYSDATEHERE',
        to_char(p_today, 'FMMonth')
        || ' '
        || uf_daywithstringend(p_today)
    );

    v_result := replace(
        v_result,
        'TODAYPLUSONE',
        to_char(v_tomorrow, 'FMMonth')
        || ' '
        || uf_daywithstringend(v_tomorrow)
    );

    v_result := replace(
        v_result,
        'WEEKDAYNO',
        p_weekdayno
    );

    RETURN v_result::varchar(8000);
END;
$$;


--
-- Name: uf_autoeoxreplacedailylist(character varying, timestamp without time zone, character); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_autoeoxreplacedailylist(p_env character varying, p_today timestamp without time zone, p_weekdayno character) RETURNS TABLE(taskno integer, title character varying, details text, note text, dependency character varying, environment character varying, subenvironment character varying, resource character varying, est_time timestamp without time zone, criticalact boolean, deleted boolean)
    LANGUAGE sql STABLE
    AS $$

WITH environment_config AS (
    SELECT
        tasklength - 1
            AS function_tasklength,

        timeend::time
            AS schedule_end_time

    FROM vw_environment_pc

    WHERE dbkey = p_env
),


source_tasks AS (
    SELECT
        d.taskno
            AS source_taskno,

        d.title
            AS source_title,

        d.details
            AS source_details,

        d.note
            AS source_note,

        d.dependency
            AS source_dependency,

        d.environment,
        d.subenvironment,
        d.resource,

        d."time"
            AS source_time,

        d.criticalact,
        d.deleted,

        c.schedule_end_time

    FROM environment_config c

    JOIN dailytasks d
      ON d.environment = p_env

    WHERE d.deleted = false

      AND d.effective_from
          <= p_today::date

      AND (
            d.effective_to IS NULL
            OR d.effective_to
               >= p_today::date
          )

      AND (
            d.taskno BETWEEN 0 AND 99

            OR

            d.taskno BETWEEN
                (
                    p_weekdayno
                    || repeat(
                        '0',
                        c.function_tasklength
                    )
                )::integer

                AND

                (
                    p_weekdayno
                    || repeat(
                        '9',
                        c.function_tasklength
                    )
                )::integer
          )
),


classified_tasks AS (
    SELECT
        s.*,

        right(
            s.source_taskno::text,
            3
        ) AS task_suffix,

        EXISTS (
            SELECT 1

            FROM templatedactivities t

            WHERE t.environment = p_env

              AND t.tasknumber =
                  right(
                      s.source_taskno::text,
                      3
                  )
        ) AS is_templated,

        CASE
            -- Normal weekday-specific Daily Task.
            WHEN s.source_taskno > 100
                THEN s.source_taskno

            -- New Every Day range.
            -- Values 7 through 99 are converted into the
            -- selected date's weekday task-number range.
            WHEN s.source_taskno
                 BETWEEN 7 AND 99

                THEN
                    p_weekdayno::integer
                    * 10000
                    + s.source_taskno

            -- Preserve legacy EOX behavior.
            WHEN (
                    s.source_taskno < 100
                    AND p_weekdayno <> '6'
                    AND s.source_taskno
                        NOT IN (5, 6)
                 )

              OR (
                    s.source_taskno
                        IN (2, 3)
                    AND p_weekdayno = '6'
                 )

                THEN
                    p_weekdayno::integer
                    * 10000
                    + s.source_taskno

            WHEN p_weekdayno = '6'
             AND s.source_taskno = 5
                THEN 60001

            WHEN p_weekdayno = '6'
             AND s.source_taskno = 6
                THEN 60004

            ELSE NULL
        END AS calculated_taskno

    FROM source_tasks s
),


replaced_tasks AS (
    SELECT
        c.*,

        CASE
            WHEN c.source_taskno
                 BETWEEN 7 AND 99
                THEN c.source_title

            WHEN c.source_taskno > 100
             AND NOT c.is_templated
                THEN c.source_title

            WHEN c.is_templated

              OR (
                    c.source_taskno
                        IN (1, 2, 3, 4)
                    AND p_weekdayno <> '6'
                 )

              OR (
                    c.source_taskno
                        IN (2, 3)
                    AND p_weekdayno = '6'
                 )

                THEN uf_autoeoxreplace(
                    c.source_title,
                    c.source_taskno,
                    p_today,
                    p_weekdayno
                )

            WHEN p_weekdayno = '6'
             AND c.source_taskno = 5

                THEN replace(
                    uf_autoeoxreplace(
                        c.source_title,
                        c.source_taskno,
                        p_today,
                        p_weekdayno
                    ),
                    '60005',
                    '60001'
                )

            WHEN p_weekdayno = '6'
             AND c.source_taskno = 6

                THEN replace(
                    uf_autoeoxreplace(
                        c.source_title,
                        c.source_taskno,
                        p_today,
                        p_weekdayno
                    ),
                    '60006',
                    '60004'
                )

            ELSE NULL
        END AS final_title,


        CASE
            WHEN c.source_taskno
                 BETWEEN 7 AND 99
                THEN c.source_details

            WHEN c.source_taskno > 100
             AND NOT c.is_templated
                THEN c.source_details

            WHEN c.is_templated

              OR (
                    c.source_taskno
                        IN (1, 2, 3, 4)
                    AND p_weekdayno <> '6'
                 )

              OR (
                    c.source_taskno
                        IN (2, 3)
                    AND p_weekdayno = '6'
                 )

                THEN uf_autoeoxreplace(
                    c.source_details,
                    c.source_taskno,
                    p_today,
                    p_weekdayno
                )

            WHEN p_weekdayno = '6'
             AND c.source_taskno = 5

                THEN replace(
                    uf_autoeoxreplace(
                        c.source_details,
                        c.source_taskno,
                        p_today,
                        p_weekdayno
                    ),
                    '60005',
                    '60001'
                )

            WHEN p_weekdayno = '6'
             AND c.source_taskno = 6

                THEN replace(
                    uf_autoeoxreplace(
                        c.source_details,
                        c.source_taskno,
                        p_today,
                        p_weekdayno
                    ),
                    '60006',
                    '60004'
                )

            ELSE NULL
        END AS final_details,


        CASE
            WHEN c.source_taskno
                 BETWEEN 7 AND 99
                THEN c.source_note

            WHEN c.source_taskno > 100
             AND NOT c.is_templated
                THEN c.source_note

            WHEN c.is_templated

              OR (
                    c.source_taskno
                        IN (1, 2, 3, 4)
                    AND p_weekdayno <> '6'
                 )

              OR (
                    c.source_taskno
                        IN (2, 3)
                    AND p_weekdayno = '6'
                 )

                THEN uf_autoeoxreplace(
                    c.source_note,
                    c.source_taskno,
                    p_today,
                    p_weekdayno
                )

            WHEN p_weekdayno = '6'
             AND c.source_taskno = 5

                THEN replace(
                    uf_autoeoxreplace(
                        c.source_note,
                        c.source_taskno,
                        p_today,
                        p_weekdayno
                    ),
                    '60005',
                    '60001'
                )

            WHEN p_weekdayno = '6'
             AND c.source_taskno = 6

                THEN replace(
                    uf_autoeoxreplace(
                        c.source_note,
                        c.source_taskno,
                        p_today,
                        p_weekdayno
                    ),
                    '60006',
                    '60004'
                )

            ELSE NULL
        END AS final_note,


        CASE
            WHEN c.source_taskno
                 BETWEEN 7 AND 99
                THEN c.source_dependency

            WHEN c.source_taskno > 100
             AND NOT c.is_templated
                THEN c.source_dependency

            WHEN c.is_templated

              OR (
                    c.source_taskno
                        IN (1, 2, 3, 4)
                    AND p_weekdayno <> '6'
                 )

              OR (
                    c.source_taskno
                        IN (2, 3)
                    AND p_weekdayno = '6'
                 )

                THEN uf_autoeoxreplace(
                    c.source_dependency,
                    c.source_taskno,
                    p_today,
                    p_weekdayno
                )

            WHEN p_weekdayno = '6'
             AND c.source_taskno = 5

                THEN replace(
                    uf_autoeoxreplace(
                        c.source_dependency,
                        c.source_taskno,
                        p_today,
                        p_weekdayno
                    ),
                    '60005',
                    '60001'
                )

            WHEN p_weekdayno = '6'
             AND c.source_taskno = 6

                THEN replace(
                    uf_autoeoxreplace(
                        c.source_dependency,
                        c.source_taskno,
                        p_today,
                        p_weekdayno
                    ),
                    '60006',
                    '60004'
                )

            ELSE NULL
        END AS final_dependency

    FROM classified_tasks c
)


SELECT
    r.calculated_taskno
        AS taskno,

    REPLACE(
    REPLACE(
        REPLACE(
            r.final_title,
            'TODAYPLUSONE',
            UPPER(
                TO_CHAR(
                    p_today::date + 1,
                    'DD-MON-YY'
                )
            )
        ),
        'TODAYSDATEHERE',
        UPPER(
            TO_CHAR(
                p_today::date,
                'DD-MON-YY'
            )
        )
    ),
    'DD-MM-YYYY',
    TO_CHAR(
    CASE
        WHEN r.source_time::time
             < r.schedule_end_time
        THEN p_today::date + 1
        ELSE p_today::date
    END,
    'DD-MM-YYYY'
    )
)::varchar(255)
    AS title,

    REPLACE(
    REPLACE(
        REPLACE(
            r.final_details,
            'TODAYPLUSONE',
            UPPER(
                TO_CHAR(
                    p_today::date + 1,
                    'DD-MON-YY'
                )
            )
        ),
        'TODAYSDATEHERE',
        UPPER(
            TO_CHAR(
                p_today::date,
                'DD-MON-YY'
            )
        )
    ),
    'DD-MM-YYYY',
    TO_CHAR(
    CASE
        WHEN r.source_time::time
             < r.schedule_end_time
        THEN p_today::date + 1
        ELSE p_today::date
    END,
    'DD-MM-YYYY'
    )
)::text
    AS details,

    REPLACE(
    REPLACE(
        REPLACE(
            r.final_note,
            'TODAYPLUSONE',
            UPPER(
                TO_CHAR(
                    p_today::date + 1,
                    'DD-MON-YY'
                )
            )
        ),
        'TODAYSDATEHERE',
        UPPER(
            TO_CHAR(
                p_today::date,
                'DD-MON-YY'
            )
        )
    ),
    'DD-MM-YYYY',
    TO_CHAR(
    CASE
        WHEN r.source_time::time
             < r.schedule_end_time
        THEN p_today::date + 1
        ELSE p_today::date
    END,
    'DD-MM-YYYY'
    )
)::text
    AS note,

    r.final_dependency::varchar(100)
        AS dependency,

    r.environment::varchar(10)
        AS environment,

    r.subenvironment::varchar(25)
        AS subenvironment,

    r.resource::varchar(20)
        AS resource,

    (
        CASE
            WHEN r.source_time::time
                 < r.schedule_end_time
                THEN p_today::date + 1

            ELSE p_today::date
        END

        + r.source_time::time

    )::timestamp without time zone
        AS est_time,

    r.criticalact,
    r.deleted

FROM replaced_tasks r

WHERE r.calculated_taskno
      IS NOT NULL

ORDER BY
    r.source_time::time,
    r.calculated_taskno;

$$;


--
-- Name: uf_availabletasknumbers(character, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_availabletasknumbers(p_weekday character, p_env character varying) RETURNS TABLE(taskno integer)
    LANGUAGE plpgsql STABLE
    AS $$

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

$$;


--
-- Name: uf_buildtaskno(character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_buildtaskno(p_env character varying, p_weekday character varying) RETURNS integer
    LANGUAGE sql STABLE
    AS $$
    SELECT taskno
    FROM infotaskno
    WHERE environment = p_env
      AND weekday = p_weekday;
$$;


--
-- Name: uf_daywithstringend(timestamp without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_daywithstringend(p_date timestamp without time zone) RETURNS character varying
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    v_day integer;
BEGIN
    v_day := EXTRACT(day FROM p_date)::integer;

    RETURN
        v_day::varchar ||
        CASE
            WHEN v_day IN (1, 21, 31) THEN 'st'
            WHEN v_day IN (2, 22)     THEN 'nd'
            WHEN v_day IN (3, 23)     THEN 'rd'
            ELSE 'th'
        END;
END;
$$;


--
-- Name: uf_eoxreplace(character varying, integer, timestamp without time zone, character); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_eoxreplace(p_templatedstring character varying, p_taskno integer, p_today timestamp without time zone, p_weekdayno character) RETURNS character varying
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    v_result text;
    v_jobtype varchar(20);
    v_tomorrow timestamp without time zone;
BEGIN
    IF p_templatedstring IS NULL THEN
        RETURN NULL;
    END IF;

    v_result := p_templatedstring;
    v_tomorrow := p_today + INTERVAL '1 day';

    v_jobtype :=
        CASE
            WHEN p_weekdayno = '7'
             AND EXTRACT(month FROM p_today)
                 != EXTRACT(month FROM v_tomorrow)
                THEN 'EOD/EOW/EOM'

            WHEN p_weekdayno = '7'
                THEN 'EOD/EOW'

            WHEN EXTRACT(month FROM p_today)
                 != EXTRACT(month FROM v_tomorrow)
                THEN 'EOD/EOM'

            ELSE 'EOD'
        END;

    IF p_taskno < 100 THEN
        v_result := p_weekdayno || '000' || v_result;
    END IF;

    v_result := replace(v_result, 'EOX', v_jobtype);

    v_result := replace(
        v_result,
        'TODAYSDATEHERE',
        to_char(p_today, 'FMMonth')
        || ' '
        || uf_daywithstringend(p_today)
    );

    v_result := replace(
        v_result,
        'TODAYPLUSONE',
        to_char(v_tomorrow, 'FMMonth')
        || ' '
        || uf_daywithstringend(v_tomorrow)
    );

    v_result := replace(
        v_result,
        'WEEKDAYNO',
        p_weekdayno
    );

    RETURN v_result::varchar(8000);
END;
$$;


--
-- Name: uf_getmpsstatus(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_getmpsstatus(p_mpsenv character varying) RETURNS TABLE(description character varying)
    LANGUAGE sql STABLE
    AS $$

    SELECT
        s.description
    FROM turnovermpsstatus s
    WHERE s.statusenvironment IN (
        p_mpsenv,
        'All'
    )
    ORDER BY s.sortorder;

$$;


--
-- Name: uf_gettoactdetails(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_gettoactdetails(p_id integer) RETURNS TABLE(envdescription character varying, subenvdescription character varying, eoxdate timestamp without time zone, comments text)
    LANGUAGE sql STABLE
    AS $$

    SELECT
        e.description::varchar(50),

        COALESCE(
            s.description,
            ''
        )::varchar(50),

        a.eoxdate,

        COALESCE(
            a.comments,
            ''
        )::text

    FROM turnoveractivities a

    JOIN turnoverenvironment e
        ON a.environmentid = e.id

    LEFT JOIN turnoversubenvironment s
        ON a.subenvid = s.id
       AND e.id = s.environmentid

    WHERE a.serial = p_id;

$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: activities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activities (
    id integer NOT NULL,
    taskno integer NOT NULL,
    est_time timestamp without time zone NOT NULL,
    title character varying(500) NOT NULL,
    details text NOT NULL,
    status character varying(15) DEFAULT 'None'::character varying NOT NULL,
    closed character varying(3),
    note text,
    environment character varying(10) NOT NULL,
    subenvironment character varying(25) NOT NULL,
    dependency character varying(50),
    resource character varying(50),
    approved character varying(50),
    unplannedact boolean NOT NULL,
    criticalact boolean NOT NULL,
    deleted boolean NOT NULL,
    CONSTRAINT ck_activities_status CHECK (((status)::text = ANY ((ARRAY['None'::character varying, 'Started'::character varying, 'Completed'::character varying, 'Failed'::character varying, 'On Hold'::character varying, 'Cancelled'::character varying])::text[])))
);


--
-- Name: uf_pcactivitylist(character varying, timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_pcactivitylist(p_env character varying, p_datefrom timestamp without time zone, p_dateto timestamp without time zone) RETURNS SETOF public.activities
    LANGUAGE sql STABLE
    AS $$

    SELECT a.*

    FROM activities a

    WHERE a.environment = p_env

      AND a.est_time
          BETWEEN p_datefrom AND p_dateto

      AND a.status = 'None'

      AND a.unplannedact = false

      AND a.deleted = false

    ORDER BY a.est_time;

$$;


--
-- Name: dailytasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dailytasks (
    serial integer NOT NULL,
    taskno smallint NOT NULL,
    title character varying(255) NOT NULL,
    details text NOT NULL,
    note text,
    dependency character varying(100),
    environment character varying(10) NOT NULL,
    subenvironment character varying(25) NOT NULL,
    resource character varying(20),
    "time" character varying(5) NOT NULL,
    criticalact boolean NOT NULL,
    deleted boolean NOT NULL,
    effective_from date DEFAULT CURRENT_DATE NOT NULL,
    effective_to date,
    CONSTRAINT ck_dailytasks_effective_dates CHECK (((effective_to IS NULL) OR (effective_to >= effective_from)))
);


--
-- Name: uf_pctemplatedactivitesbyenv(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_pctemplatedactivitesbyenv(p_envdesc character varying) RETURNS SETOF public.dailytasks
    LANGUAGE sql STABLE
    AS $$

    SELECT
        d.*

    FROM dailytasks d

    JOIN vw_environment_pc e
        ON d.environment = e.dbkey

    WHERE e.description = p_envdesc

      AND (
            d.taskno < 100

            OR

            right(
                d.taskno::text,
                3
            ) IN (
                SELECT t.tasknumber
                FROM templatedactivities t
                WHERE t.environment = e.dbkey
            )
          )

    ORDER BY
        d.taskno,
        d.time;

$$;


--
-- Name: uf_prodcontrolreport(character varying, timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_prodcontrolreport(p_env character varying, p_datefrom timestamp without time zone, p_dateto timestamp without time zone) RETURNS TABLE(taskno integer, est_time timestamp without time zone, title character varying, details text, note text, dependency character varying, resource character varying)
    LANGUAGE sql STABLE
    AS $$

    SELECT
        a.taskno,
        a.est_time,
        a.title,
        a.details,
        a.note,
        a.dependency,
        a.resource

    FROM activities a

    WHERE a.closed != 'Yes'

      AND a.environment = p_env

      AND a.est_time
          BETWEEN p_datefrom AND p_dateto

      AND a.unplannedact = false

      AND a.deleted = false;

$$;


--
-- Name: uf_roccarchivereport(character varying, timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_roccarchivereport(p_env character varying, p_datefrom timestamp without time zone, p_dateto timestamp without time zone) RETURNS TABLE(actid integer, evtid integer, taskno integer, est_time timestamp without time zone, title character varying, actdetails text, status character varying, dependency character varying, resource character varying, note text, time_started timestamp without time zone, systimeentered timestamp without time zone, evtdetails text, operator character varying, serial integer, colour character varying)
    LANGUAGE sql STABLE
    AS $$

    SELECT
        a.id AS actid,
        e.id AS evtid,
        a.taskno,
        a.est_time,
        a.title,
        a.details AS actdetails,
        a.status,
        a.dependency,
        a.resource,
        a.note,
        e.time_started,
        e.systimeentered,
        e.details AS evtdetails,
        e.operator::varchar(50),
        e.serial,
        c.colour::varchar(7)

    FROM archived_activities a

    LEFT JOIN archived_events e
        ON a.id = e.id

    JOIN opsreportstatuscolour c
        ON a.status = c.status

    WHERE a.environment = p_env

      AND (
            a.est_time BETWEEN p_datefrom AND p_dateto

            OR

            e.time_started BETWEEN p_datefrom AND p_dateto

            OR

            (
                a.est_time <= p_dateto
                AND a.status IN ('Open', 'None')
            )
          );

$$;


--
-- Name: uf_roccbillingfyireport(timestamp without time zone, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_roccbillingfyireport(p_repdate timestamp without time zone, p_hourrange integer) RETURNS TABLE(title character varying, status character varying, id integer, systimeentered timestamp without time zone)
    LANGUAGE sql STABLE
    AS $$

    SELECT
        x.title,
        x.status,
        x.id,
        x.systimeentered

    FROM (

        SELECT
            a.title,
            a.status,
            a.id,
            MIN(e.systimeentered) AS systimeentered

        FROM activities a

        JOIN events e
            ON a.id = e.id

        WHERE a.environment = 'v21'

          AND a.title ILIKE '%Bill%'

          AND (
                a.status = 'Open'

                OR

                (
                    e.systimeentered >=
                        p_repdate
                        - (
                            p_hourrange
                            * INTERVAL '1 hour'
                          )

                    AND e.systimeentered <=
                        p_repdate
                )

                OR

                (
                    a.est_time >=
                        p_repdate
                        - (
                            p_hourrange
                            * INTERVAL '1 hour'
                          )

                    AND a.est_time <=
                        p_repdate
                )
              )

        GROUP BY
            a.title,
            a.status,
            a.id


        UNION


        SELECT
            a.title,
            a.status,
            a.id,
            a.est_time AS systimeentered

        FROM activities a

        WHERE a.environment = 'v21'

          AND a.title ILIKE '%Bill%'

          AND a.status = 'None'

          AND a.est_time <= p_repdate

    ) x;

$$;


--
-- Name: uf_roccreport(character varying, timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_roccreport(p_env character varying, p_datefrom timestamp without time zone, p_dateto timestamp without time zone) RETURNS TABLE(actid integer, evtid integer, taskno integer, est_time timestamp without time zone, title character varying, actdetails text, status character varying, dependency character varying, resource character varying, note text, time_started timestamp without time zone, systimeentered timestamp without time zone, evtdetails text, operator character varying, serial integer, colour character varying, subenvironment character varying)
    LANGUAGE sql STABLE
    AS $$

    SELECT
        a.id AS actid,
        e.id AS evtid,
        a.taskno,
        a.est_time,
        a.title,
        a.details AS actdetails,
        a.status,
        a.dependency,
        a.resource,
        a.note,
        e.time_started,
        e.systimeentered,
        e.details AS evtdetails,
        e.operator::varchar(50),
        e.serial,
        c.colour::varchar(7),
        a.subenvironment

    FROM activities a

    LEFT JOIN events e
        ON a.id = e.id

    JOIN opsreportstatuscolour c
        ON a.status = c.status

    WHERE a.environment = p_env

      AND (
            a.est_time BETWEEN p_datefrom AND p_dateto

            OR

            e.time_started BETWEEN p_datefrom AND p_dateto

            OR

            (
                a.est_time <= p_dateto
                AND a.status IN ('Open', 'None')
            )
          );

$$;


--
-- Name: uf_roccreportsearch(character varying, timestamp without time zone, timestamp without time zone, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_roccreportsearch(p_env character varying, p_datefrom timestamp without time zone, p_dateto timestamp without time zone, p_search character varying DEFAULT ''::character varying) RETURNS TABLE(actid integer, evtid integer, taskno integer, est_time timestamp without time zone, title character varying, actdetails text, status character varying, dependency character varying, resource character varying, note text, time_started timestamp without time zone, systimeentered timestamp without time zone, evtdetails text, operator character varying, serial integer, colour character varying, subenvironment character varying)
    LANGUAGE sql STABLE
    AS $$

    SELECT
        r.actid,
        r.evtid,
        r.taskno,
        r.est_time,
        r.title,
        r.actdetails,
        r.status,
        r.dependency,
        r.resource,
        r.note,
        r.time_started,
        r.systimeentered,
        r.evtdetails,
        r."operator",
        r.serial,
        r.colour,
        r.subenvironment

    FROM uf_roccreport(
        p_env,
        p_datefrom,
        p_dateto
    ) r

    WHERE r.title ILIKE '%' || p_search || '%'

       OR r.actdetails ILIKE '%' || p_search || '%'

       OR r.note ILIKE '%' || p_search || '%'

       OR r.evtdetails ILIKE '%' || p_search || '%';

$$;


--
-- Name: uf_roccsreqarchivereport(character varying, timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_roccsreqarchivereport(p_env character varying, p_datefrom timestamp without time zone, p_dateto timestamp without time zone) RETURNS TABLE(actid integer, evtid integer, taskno integer, est_time timestamp without time zone, title character varying, actdetails text, status character varying, dependency character varying, resource character varying, note text, time_started timestamp without time zone, systimeentered timestamp without time zone, evtdetails text, operator character varying, serial integer, colour character varying)
    LANGUAGE sql STABLE
    AS $$

    SELECT
        r.actid,
        r.evtid,
        r.taskno,
        r.est_time,
        r.title,
        r.actdetails,
        r.status,
        r.dependency,
        r.resource,
        r.note,
        r.time_started,
        r.systimeentered,
        r.evtdetails,
        r."operator",
        r.serial,
        r.colour

    FROM uf_roccarchivereport(
        p_env,
        p_datefrom,
        p_dateto
    ) r

    WHERE r.title ILIKE '%SREQ5%'
       OR r.title ILIKE '%SREQ05%'
       OR r.title ILIKE '%SREQ16%';

$$;


--
-- Name: uf_roccsreqreport(character varying, timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_roccsreqreport(p_env character varying, p_datefrom timestamp without time zone, p_dateto timestamp without time zone) RETURNS TABLE(actid integer, evtid integer, taskno integer, est_time timestamp without time zone, title character varying, actdetails text, status character varying, dependency character varying, resource character varying, note text, time_started timestamp without time zone, systimeentered timestamp without time zone, evtdetails text, operator character varying, serial integer, colour character varying, subenvironment character varying)
    LANGUAGE sql STABLE
    AS $$

    SELECT
        r.actid,
        r.evtid,
        r.taskno,
        r.est_time,
        r.title,
        r.actdetails,
        r.status,
        r.dependency,
        r.resource,
        r.note,
        r.time_started,
        r.systimeentered,
        r.evtdetails,
        r."operator",
        r.serial,
        r.colour,
        r.subenvironment

    FROM uf_roccreport(
        p_env,
        p_datefrom,
        p_dateto
    ) r

    WHERE r.title ILIKE '%SREQ5%'
       OR r.title ILIKE '%SREQ05%'
       OR r.title ILIKE '%SREQ16%';

$$;


--
-- Name: uf_slaexceptionreport(character, timestamp without time zone, character varying, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_slaexceptionreport(p_taskstart character, p_repdate timestamp without time zone, p_env character varying, p_difference integer) RETURNS TABLE(taskno integer, title character varying, est_time timestamp without time zone, firstevent timestamp without time zone, status character varying, difference integer, id integer)
    LANGUAGE sql STABLE
    AS $$

    SELECT
        s.taskno,
        s.title,
        s.est_time,
        s.firstevent,
        s.status,

        (
            EXTRACT(
                EPOCH FROM (
                    s.firstevent
                    - s.est_time
                )
            ) / 60
        )::integer AS difference,

        s.id

    FROM vw_slaexceptionreport s

    WHERE s.taskno::text
              LIKE p_taskstart || '%'

      AND s.est_time
          BETWEEN
              p_repdate - INTERVAL '2 days'
              AND
              p_repdate + INTERVAL '2 days'

      AND s.environment = p_env

      AND (
            EXTRACT(
                EPOCH FROM (
                    s.firstevent
                    - s.est_time
                )
            ) / 60
          ) >= p_difference;

$$;


--
-- Name: uf_subenvsforenv(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_subenvsforenv(p_env character varying) RETURNS TABLE(description character varying)
    LANGUAGE sql STABLE
    AS $$

    SELECT
        s.description

    FROM turnoversubenvironment s

    JOIN turnoverenvironment e
        ON s.environmentid = e.id

    WHERE e.description = p_env

    ORDER BY s.sortorder;

$$;


--
-- Name: uf_templatedtasksstring(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_templatedtasksstring(p_env character varying DEFAULT 'v21'::character varying) RETURNS character varying
    LANGUAGE sql STABLE
    AS $$

    SELECT

        CASE

            WHEN COUNT(*) = 0
                THEN '('''')'

            ELSE
                '('
                ||
                string_agg(
                    d.day_no::text
                    || t.tasknumber,
                    ','
                    ORDER BY
                        t.id,
                        d.day_no
                )
                ||
                ')'

        END::varchar(400)

    FROM templatedactivities t

    CROSS JOIN generate_series(
        1,
        7
    ) AS d(day_no)

    WHERE t.environment = p_env;

$$;


--
-- Name: uf_toactivitywithevent(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_toactivitywithevent(p_id integer) RETURNS TABLE(taskno integer, est_time timestamp without time zone, title character varying, actdetails text, status character varying, note text, dependency character varying, resource character varying, time_started timestamp without time zone, evtdetails text, operator character varying, colour character varying, comments text)
    LANGUAGE sql STABLE
    AS $$

    SELECT
        a.taskno,
        a.est_time,
        a.title,
        a.details AS actdetails,
        a.status,
        a.note,
        a.dependency,
        a.resource,
        e.time_started,
        e.details AS evtdetails,
        e.operator::varchar(50) AS "operator",
        c.colour::varchar(7) AS colour,
        t.comments

    FROM activities a

    LEFT JOIN events e
        ON a.id = e.id

    LEFT JOIN turnoveractivities t
        ON a.id = t.activityid

    JOIN opsreportstatuscolour c
        ON a.status = c.status

    WHERE a.id = p_id

    ORDER BY
        e.time_started,
        e.serial;

$$;


--
-- Name: uf_usedtasknumbers(character varying, character, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_usedtasknumbers(p_env character varying, p_weekday character, p_tasklength integer) RETURNS TABLE(taskno integer)
    LANGUAGE sql STABLE
    AS $$

    SELECT
        d.taskno::integer

    FROM dailytasks d

    WHERE d.environment = p_env

      AND d.taskno BETWEEN

          (
              p_weekday
              || repeat(
                    '0',
                    p_tasklength
                 )
          )::integer

          AND

          (
              p_weekday
              || '4'
              || repeat(
                    '9',
                    p_tasklength - 1
                 )
          )::integer

    ORDER BY d.taskno;

$$;


--
-- Name: uf_valideoxdate(timestamp without time zone, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uf_valideoxdate(p_eoxdate timestamp without time zone, p_eoxenv character varying) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    v_eow  boolean := false;
    v_eom  boolean := false;
    v_eowm boolean := false;
BEGIN

    -- Sunday = 7 using ISO weekday numbering
    v_eow :=
        EXTRACT(ISODOW FROM p_eoxdate)::integer = 7;

    -- End of month means tomorrow belongs to another month
    v_eom :=
        EXTRACT(month FROM p_eoxdate)
        <>
        EXTRACT(
            month
            FROM p_eoxdate + INTERVAL '1 day'
        );

    v_eowm := v_eow AND v_eom;

    RETURN
        CASE
            WHEN p_eoxenv = 'EOD'     THEN true
            WHEN p_eoxenv = 'EOD/W'   THEN v_eow
            WHEN p_eoxenv = 'EOD/M'   THEN v_eom
            WHEN p_eoxenv = 'EOD/W/M' THEN v_eowm
            ELSE false
        END;

END;
$$;


--
-- Name: activities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.activities ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.activities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: activitylog_pc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activitylog_pc (
    id integer NOT NULL,
    taskno integer NOT NULL,
    environment character varying(10) NOT NULL,
    name character varying(50) NOT NULL,
    date timestamp without time zone NOT NULL,
    action character varying(50) NOT NULL
);


--
-- Name: activitylog_pc_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.activitylog_pc ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.activitylog_pc_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: alerts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alerts (
    id integer NOT NULL,
    taskno integer NOT NULL,
    due_status character varying(15) NOT NULL,
    email character varying(255) NOT NULL,
    reoccur boolean NOT NULL,
    environment character varying(10) NOT NULL,
    ipaddress character varying(15) NOT NULL
);


--
-- Name: alerts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.alerts ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.alerts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: app_audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_audit_log (
    id bigint NOT NULL,
    occurred_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    username character varying(100),
    display_name character varying(200),
    authentication_type character varying(30),
    role character varying(30),
    action character varying(100) NOT NULL,
    target_type character varying(100),
    target_id character varying(100),
    result character varying(20) NOT NULL,
    source_ip character varying(64),
    reason text,
    details text,
    CONSTRAINT ck_app_audit_log_result CHECK (((result)::text = ANY ((ARRAY['SUCCESS'::character varying, 'FAILURE'::character varying, 'DENIED'::character varying])::text[])))
);


--
-- Name: app_audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.app_audit_log ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.app_audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: app_emergency_mode; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_emergency_mode (
    id smallint DEFAULT 1 NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    enabled_at timestamp without time zone,
    enabled_by character varying(100),
    expires_at timestamp without time zone,
    reason text,
    disabled_at timestamp without time zone,
    disabled_by character varying(100),
    CONSTRAINT ck_app_emergency_mode_singleton CHECK ((id = 1))
);


--
-- Name: app_local_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_local_users (
    id bigint NOT NULL,
    username character varying(100) NOT NULL,
    display_name character varying(200) NOT NULL,
    password_hash text NOT NULL,
    role character varying(30) NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    emergency_admin boolean DEFAULT false NOT NULL,
    expires_at timestamp without time zone,
    failed_attempts integer DEFAULT 0 NOT NULL,
    locked_until timestamp without time zone,
    last_login_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by character varying(100) NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by character varying(100) NOT NULL,
    must_change_password boolean DEFAULT true NOT NULL,
    password_changed_at timestamp without time zone,
    CONSTRAINT ck_app_local_users_role CHECK (((role)::text = ANY ((ARRAY['ASPEN.Reader'::character varying, 'ASPEN.Operator'::character varying, 'ASPEN.Admin'::character varying])::text[])))
);


--
-- Name: app_local_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.app_local_users ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.app_local_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: archived_activities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.archived_activities (
    id integer NOT NULL,
    taskno integer NOT NULL,
    est_time timestamp without time zone,
    title character varying(500) NOT NULL,
    details text NOT NULL,
    status character varying(15),
    closed character varying(3),
    note text,
    environment character varying(10) NOT NULL,
    subenvironment character varying(25),
    dependency character varying(50),
    resource character varying(50),
    approved character varying(50),
    unplannedact boolean NOT NULL,
    criticalact boolean NOT NULL,
    deleted boolean NOT NULL
);


--
-- Name: archived_activitylog_pc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.archived_activitylog_pc (
    id integer NOT NULL,
    taskno integer NOT NULL,
    environment character varying(10) NOT NULL,
    name character varying(50) NOT NULL,
    date timestamp without time zone NOT NULL,
    action character varying(50) NOT NULL
);


--
-- Name: archived_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.archived_events (
    id integer NOT NULL,
    time_updated timestamp without time zone NOT NULL,
    time_started timestamp without time zone NOT NULL,
    systimeentered timestamp without time zone NOT NULL,
    details text NOT NULL,
    operator character varying(50) NOT NULL,
    serial integer NOT NULL
);


--
-- Name: aspenpermissions_pc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aspenpermissions_pc (
    serial integer NOT NULL,
    username character varying(50) NOT NULL,
    envavailable character varying(15) NOT NULL,
    changeenvironment boolean NOT NULL,
    gradientfill boolean NOT NULL,
    updatedailytasks boolean NOT NULL,
    addtasks boolean NOT NULL,
    updatetask boolean NOT NULL,
    deletetask boolean NOT NULL,
    importinfoman boolean NOT NULL
);


--
-- Name: aspenpermissions_pc_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.aspenpermissions_pc ALTER COLUMN serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.aspenpermissions_pc_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: aspenpermissions_rocc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aspenpermissions_rocc (
    serial integer NOT NULL,
    username character varying(50) NOT NULL,
    executeapplication boolean NOT NULL,
    updateevents boolean NOT NULL,
    settransparency boolean NOT NULL
);


--
-- Name: aspenpermissions_rocc_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.aspenpermissions_rocc ALTER COLUMN serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.aspenpermissions_rocc_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: dailytasks_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.dailytasks ALTER COLUMN serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.dailytasks_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: dtproperties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dtproperties (
    id integer NOT NULL,
    objectid integer,
    property character varying(64) NOT NULL,
    value character varying(255),
    uvalue character varying(255),
    lvalue bytea,
    version integer NOT NULL
);


--
-- Name: dtproperties_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.dtproperties ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.dtproperties_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: emailfromaddressandsignature; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.emailfromaddressandsignature (
    serial integer NOT NULL,
    fromaddress character varying(100) NOT NULL,
    signature text NOT NULL,
    department character varying(10) NOT NULL
);


--
-- Name: emailfromaddressandsignature_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.emailfromaddressandsignature ALTER COLUMN serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.emailfromaddressandsignature_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: emailsubscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.emailsubscriptions (
    serial integer NOT NULL,
    username character varying(100) NOT NULL,
    emailaddress character varying(100) NOT NULL,
    v21billingfyi boolean NOT NULL,
    v21opsdaily boolean NOT NULL,
    v21opsweekend boolean NOT NULL,
    v21spooling boolean NOT NULL,
    cableops boolean NOT NULL,
    nbudrp boolean NOT NULL
);


--
-- Name: emailsubscriptions_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.emailsubscriptions ALTER COLUMN serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.emailsubscriptions_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: environment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.environment (
    id integer NOT NULL,
    description character varying(50) NOT NULL,
    dbkey character varying(10) NOT NULL,
    commandline character varying(51),
    tasklength integer NOT NULL
);


--
-- Name: environment_ops; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.environment_ops (
    environmentid integer NOT NULL,
    sortorder integer NOT NULL,
    billenabled boolean NOT NULL,
    colourstart character varying(8) NOT NULL,
    colourend character varying(8) NOT NULL,
    fromdatediff integer NOT NULL,
    fromtime character(5) NOT NULL,
    todatediff integer NOT NULL,
    totime character(5) NOT NULL,
    activitiestable character varying(40) NOT NULL
);


--
-- Name: environment_pc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.environment_pc (
    environmentid integer NOT NULL,
    timeend character(5) NOT NULL,
    fromdatediff integer NOT NULL,
    todatediff integer NOT NULL,
    reporttitle character varying(50) NOT NULL,
    reporttimefrom character(5) NOT NULL,
    reporttimeto character(5) NOT NULL,
    reportdrafttime character(5) NOT NULL,
    reportfinaltime character(5) NOT NULL
);


--
-- Name: environment_sub; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.environment_sub (
    id integer NOT NULL,
    envid integer NOT NULL,
    description character varying(25) NOT NULL,
    sortorder integer NOT NULL
);


--
-- Name: environment_sub_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.environment_sub ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.environment_sub_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: event_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_templates (
    serial integer NOT NULL,
    caption character varying(50) NOT NULL,
    template text NOT NULL,
    environment character varying(10) NOT NULL
);


--
-- Name: event_templates_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.event_templates ALTER COLUMN serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.event_templates_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events (
    id integer NOT NULL,
    time_updated timestamp without time zone NOT NULL,
    time_started timestamp without time zone NOT NULL,
    systimeentered timestamp without time zone NOT NULL,
    details text NOT NULL,
    operator character varying(50) NOT NULL,
    serial integer NOT NULL
);


--
-- Name: events_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.events ALTER COLUMN serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.events_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: infotaskno; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.infotaskno (
    serial integer NOT NULL,
    weekday character varying(9) NOT NULL,
    environment character varying(10) NOT NULL,
    taskno integer NOT NULL
);


--
-- Name: infotaskno_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.infotaskno ALTER COLUMN serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.infotaskno_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: opsreportstatuscolour; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.opsreportstatuscolour (
    id integer NOT NULL,
    status character varying(10) NOT NULL,
    colour character(7) NOT NULL
);


--
-- Name: opsreportstatuscolour_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.opsreportstatuscolour ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.opsreportstatuscolour_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: statutoryholidays; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.statutoryholidays (
    serial integer NOT NULL,
    holiday timestamp without time zone NOT NULL,
    reason character varying(50) NOT NULL
);


--
-- Name: statutoryholidays_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.statutoryholidays ALTER COLUMN serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.statutoryholidays_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: templatedactivities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.templatedactivities (
    id integer NOT NULL,
    tasknumber character varying(5) NOT NULL,
    environment character varying(10) NOT NULL
);


--
-- Name: turnoveractivities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.turnoveractivities (
    serial integer NOT NULL,
    activityid integer NOT NULL,
    environmentid integer NOT NULL,
    subenvid integer,
    comments text,
    eoxdate timestamp without time zone
);


--
-- Name: turnoveractivities_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.turnoveractivities ALTER COLUMN serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.turnoveractivities_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: turnoverenvironment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.turnoverenvironment (
    id integer NOT NULL,
    sortorder integer NOT NULL,
    description character varying(50) NOT NULL
);


--
-- Name: turnoverenvironment_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.turnoverenvironment ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.turnoverenvironment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: turnovermps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.turnovermps (
    id integer NOT NULL,
    collections integer NOT NULL,
    maindrivers integer NOT NULL,
    guiders integer NOT NULL,
    mpupappgdtime timestamp without time zone NOT NULL,
    premaf1date timestamp without time zone NOT NULL,
    premaf1status character varying(50) NOT NULL,
    premaf4date timestamp without time zone NOT NULL,
    premaf4status character varying(50) NOT NULL,
    cibervolser1 character varying(7) NOT NULL,
    cibervolser2 character varying(7) NOT NULL,
    cibervolser3 character varying(7) NOT NULL
);


--
-- Name: turnovermps_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.turnovermps ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.turnovermps_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: turnovermpscycles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.turnovermpscycles (
    id integer NOT NULL,
    mpsid integer NOT NULL,
    cycledetails character varying(200) NOT NULL
);


--
-- Name: turnovermpscycles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.turnovermpscycles ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.turnovermpscycles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: turnovermpsstatus; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.turnovermpsstatus (
    id integer NOT NULL,
    statusenvironment character varying(10) NOT NULL,
    sortorder integer NOT NULL,
    description character varying(100) NOT NULL
);


--
-- Name: turnovermpsstatus_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.turnovermpsstatus ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.turnovermpsstatus_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: turnovernotes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.turnovernotes (
    category character varying(10) NOT NULL,
    title character varying(50) NOT NULL,
    note text NOT NULL,
    sortorder integer NOT NULL
);


--
-- Name: turnoveronlinesmainframe; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.turnoveronlinesmainframe (
    sortorder integer NOT NULL,
    database character varying(30) NOT NULL,
    location character varying(50) NOT NULL,
    sla character varying(50) NOT NULL,
    "time" character(5) NOT NULL
);


--
-- Name: turnoveronlinesv21; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.turnoveronlinesv21 (
    sortorder integer NOT NULL,
    system character varying(50) NOT NULL,
    "time" character(5) NOT NULL
);


--
-- Name: turnoversubenvironment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.turnoversubenvironment (
    id integer NOT NULL,
    sortorder integer NOT NULL,
    description character varying(50) NOT NULL,
    environmentid integer NOT NULL
);


--
-- Name: turnoversubenvironment_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.turnoversubenvironment ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.turnoversubenvironment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: vw_drpbackupemail; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_drpbackupemail AS
 SELECT ((((('Task #'::text || ((activities.taskno)::character varying)::text) || ' - Title:  '::text) || (activities.title)::text) || ' - Status:  '::text) || (activities.status)::text) AS drpdetails
   FROM public.activities
  WHERE (((activities.environment)::text = 'netbackup'::text) AND ((activities.est_time >= (CURRENT_TIMESTAMP - '1 day'::interval)) AND (activities.est_time <= CURRENT_TIMESTAMP)) AND (((activities.taskno)::text ~~ '%080'::text) OR ((activities.taskno)::text ~~ '%017'::text) OR ((activities.taskno)::text ~~ '%015'::text) OR ((activities.taskno)::text ~~ '%019'::text) OR ((activities.taskno)::text ~~ '%079'::text)) AND (activities.deleted = false));


--
-- Name: vw_environment_ops; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_environment_ops AS
 SELECT e.description,
    e.dbkey,
    o.billenabled,
    o.colourstart,
    o.colourend,
    to_char(((CURRENT_DATE + o.fromdatediff))::timestamp with time zone, 'YYYY-MM-DD'::text) AS fromdate,
    o.fromtime,
    to_char(((CURRENT_DATE + o.todatediff))::timestamp with time zone, 'YYYY-MM-DD'::text) AS todate,
    o.totime,
    o.activitiestable
   FROM (public.environment e
     JOIN public.environment_ops o ON ((e.id = o.environmentid)));


--
-- Name: vw_environment_pc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_environment_pc AS
 SELECT e.description,
    e.dbkey,
    e.commandline,
    p.timeend,
    to_char(((CURRENT_DATE + p.fromdatediff))::timestamp with time zone, 'YYYY-MM-DD'::text) AS fromdate,
    to_char(((CURRENT_DATE + p.todatediff))::timestamp with time zone, 'YYYY-MM-DD'::text) AS todate,
    e.tasklength
   FROM (public.environment e
     JOIN public.environment_pc p ON ((e.id = p.environmentid)));


--
-- Name: vw_environment_pc_report; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_environment_pc_report AS
 SELECT e.description,
    e.dbkey,
    e.commandline,
    p.reporttitle,
    p.reporttimefrom,
    p.reporttimeto,
    p.reportdrafttime,
    p.reportfinaltime
   FROM (public.environment e
     JOIN public.environment_pc p ON ((e.id = p.environmentid)));


--
-- Name: vw_environment_sub; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_environment_sub AS
 SELECT e.description AS env,
    e.dbkey AS envkey,
    s.description AS subenv,
    s.sortorder
   FROM (public.environment e
     JOIN public.environment_sub s ON ((e.id = s.envid)));


--
-- Name: vw_passeddueactivities; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_passeddueactivities AS
 SELECT activities.taskno AS "Task Number",
    activities.est_time AS "Estimated Time",
    activities.title,
    activities.details,
        CASE activities.environment
            WHEN 'v21'::text THEN 'Vision 21'::character varying
            ELSE activities.environment
        END AS environment,
    activities.id
   FROM public.activities
  WHERE (((activities.status)::text = 'None'::text) AND (activities.est_time < CURRENT_TIMESTAMP) AND (activities.deleted = false));


--
-- Name: vw_permissions_pc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_permissions_pc AS
 SELECT p.username,
    e.dbkey,
    e.commandline,
    e.description
   FROM (public.environment e
     JOIN public.aspenpermissions_pc p ON (((p.envavailable)::text ~~ (('%'::text || ((e.id)::character varying)::text) || '%'::text))));


--
-- Name: vw_resourcesavailable; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_resourcesavailable AS
 SELECT DISTINCT (rtrim((activities.resource)::text))::character varying(50) AS resource,
    (rtrim((activities.environment)::text))::character varying(10) AS environment
   FROM public.activities
  WHERE (rtrim((activities.resource)::text) <> ''::text);


--
-- Name: vw_rocc_activitylistforcolour; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_rocc_activitylistforcolour AS
 SELECT activities.id,
    activities.taskno AS "Task #",
    ((to_char(activities.est_time, 'MM/DD/YYYY'::text) || ' - '::text) || to_char(activities.est_time, 'HH24:MI'::text)) AS "Estimated Time",
    activities.est_time,
    activities.title,
    activities.details,
    activities.status,
    activities.closed,
    activities.note,
    activities.dependency,
    activities.resource,
    activities.environment,
    activities.subenvironment,
    activities.criticalact
   FROM public.activities
  WHERE (activities.deleted = false);


--
-- Name: vw_slaexceptionreport; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_slaexceptionreport AS
 SELECT a.taskno,
    a.est_time,
    a.title,
    a.status,
        CASE
            WHEN (min(e.systimeentered) IS NULL) THEN CURRENT_TIMESTAMP
            ELSE (min(e.systimeentered))::timestamp with time zone
        END AS firstevent,
    a.environment,
    a.id
   FROM (public.activities a
     LEFT JOIN public.events e ON ((a.id = e.id)))
  WHERE (a.est_time <= CURRENT_TIMESTAMP)
  GROUP BY a.id, a.taskno, a.est_time, a.title, a.status, a.environment;


--
-- Name: vw_statutoryholidays; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_statutoryholidays AS
 SELECT statutoryholidays.serial,
    ((((to_char(statutoryholidays.holiday, 'FMMonth'::text) || ' '::text) || (EXTRACT(day FROM statutoryholidays.holiday))::integer) || ', '::text) || (EXTRACT(year FROM statutoryholidays.holiday))::integer) AS formattedholiday,
    statutoryholidays.reason
   FROM public.statutoryholidays;


--
-- Name: vw_turnoveractivities; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_turnoveractivities AS
 SELECT a.id,
    a.taskno,
    a.est_time,
    a.title,
    COALESCE(t.comments, ''::text) AS comments,
        CASE
            WHEN (t.eoxdate IS NULL) THEN (e.description)::text
            ELSE (((((e.description)::text || ' - '::text) || to_char(t.eoxdate, 'FMMonth'::text)) || ' '::text) || (EXTRACT(day FROM t.eoxdate))::integer)
        END AS envdescription,
    COALESCE(s.description, ''::character varying) AS subdescription,
    t.serial,
    e.sortorder
   FROM (((public.activities a
     JOIN public.turnoveractivities t ON ((a.id = t.activityid)))
     JOIN public.turnoverenvironment e ON ((t.environmentid = e.id)))
     LEFT JOIN public.turnoversubenvironment s ON (((t.subenvid = s.id) AND (e.id = s.environmentid))));


--
-- Name: vw_turnoveractlist; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_turnoveractlist AS
 SELECT a.id,
    a.taskno AS "Task #",
    ((to_char(a.est_time, 'MM/DD/YYYY'::text) || ' - '::text) || to_char(a.est_time, 'HH24:MI'::text)) AS "Estimated Time",
    a.est_time,
    a.title,
    a.details,
    a.status,
    a.closed,
    a.note,
    a.dependency,
    a.resource,
    'turnover'::character varying AS environment,
    a.approved,
    a.criticalact
   FROM (public.activities a
     JOIN public.turnoveractivities t ON ((a.id = t.activityid)));


--
-- Name: vw_turnoverbreakpoints; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_turnoverbreakpoints AS
 SELECT 0 AS sortorder
UNION
 SELECT turnoverenvironment.sortorder
   FROM public.turnoverenvironment
  WHERE ((turnoverenvironment.description)::text = ANY ((ARRAY['Mainframe'::character varying, 'Scheduling'::character varying, 'AS400'::character varying])::text[]))
UNION
 SELECT 999999 AS sortorder;


--
-- Name: vw_turnovermps; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_turnovermps AS
 SELECT turnovermps.id,
    (((((
        CASE
            WHEN (turnovermps.collections = 1) THEN (((turnovermps.collections)::character varying)::text || ' Collection'::text)
            ELSE (((turnovermps.collections)::character varying)::text || ' Collections'::text)
        END || ', '::text) ||
        CASE
            WHEN (turnovermps.maindrivers = 1) THEN (((turnovermps.maindrivers)::character varying)::text || ' Maindriver'::text)
            ELSE (((turnovermps.maindrivers)::character varying)::text || ' Maindrivers'::text)
        END) || ', '::text) ||
        CASE
            WHEN (turnovermps.guiders = 1) THEN (((turnovermps.guiders)::character varying)::text || ' Guider'::text)
            ELSE (((turnovermps.guiders)::character varying)::text || ' Guiders'::text)
        END) || '.'::text) AS mpsconfiguration,
    to_char(turnovermps.mpupappgdtime, 'HH24:MI'::text) AS mpupappgdtime,
    ((((to_char(turnovermps.premaf1date, 'FMMonth'::text) || ' '::text) || (EXTRACT(day FROM turnovermps.premaf1date))::integer) || ' '::text) || (turnovermps.premaf1status)::text) AS premaf1,
    ((((to_char(turnovermps.premaf4date, 'FMMonth'::text) || ' '::text) || (EXTRACT(day FROM turnovermps.premaf4date))::integer) || ' '::text) || (turnovermps.premaf4status)::text) AS premaf4,
    ((('Ciber Incollect Loaded - '::text || (turnovermps.cibervolser1)::text) || ', Ciber Outcollect Loaded - '::text) || (turnovermps.cibervolser2)::text) AS ciberline1,
    ('Ciber Outcollect Created - '::text || (turnovermps.cibervolser3)::text) AS ciberline2
   FROM public.turnovermps
  ORDER BY turnovermps.id DESC
 LIMIT 1;


--
-- Name: vw_turnovermpscurrentcycles; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_turnovermpscurrentcycles AS
 SELECT (replace((turnovermpscycles.cycledetails)::text, 'Cycle '::text, ''::text))::character varying(200) AS cycledetails
   FROM public.turnovermpscycles
  WHERE (turnovermpscycles.mpsid = ( SELECT max(turnovermps.id) AS max
           FROM public.turnovermps))
  ORDER BY turnovermpscycles.id;


--
-- Name: vw_turnovermpswithcycles; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_turnovermpswithcycles AS
 SELECT m.mpsconfiguration,
    m.mpupappgdtime,
    m.premaf1,
    m.premaf4,
    m.ciberline1,
    m.ciberline2,
    c.cycledetails
   FROM (public.vw_turnovermps m
     JOIN public.turnovermpscycles c ON ((c.mpsid = m.id)))
  ORDER BY c.id;


--
-- Name: activities pk_activities; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT pk_activities PRIMARY KEY (id);


--
-- Name: activitylog_pc pk_activitylog_pc; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activitylog_pc
    ADD CONSTRAINT pk_activitylog_pc PRIMARY KEY (id);


--
-- Name: alerts pk_alerts; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT pk_alerts PRIMARY KEY (id);


--
-- Name: app_audit_log pk_app_audit_log; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_audit_log
    ADD CONSTRAINT pk_app_audit_log PRIMARY KEY (id);


--
-- Name: app_emergency_mode pk_app_emergency_mode; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_emergency_mode
    ADD CONSTRAINT pk_app_emergency_mode PRIMARY KEY (id);


--
-- Name: app_local_users pk_app_local_users; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_local_users
    ADD CONSTRAINT pk_app_local_users PRIMARY KEY (id);


--
-- Name: archived_activities pk_archived_activities; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.archived_activities
    ADD CONSTRAINT pk_archived_activities PRIMARY KEY (id);


--
-- Name: archived_activitylog_pc pk_archived_activitylog_pc; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.archived_activitylog_pc
    ADD CONSTRAINT pk_archived_activitylog_pc PRIMARY KEY (id);


--
-- Name: archived_events pk_archived_events; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.archived_events
    ADD CONSTRAINT pk_archived_events PRIMARY KEY (serial);


--
-- Name: aspenpermissions_pc pk_aspenpermissions_pc; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aspenpermissions_pc
    ADD CONSTRAINT pk_aspenpermissions_pc PRIMARY KEY (serial);


--
-- Name: aspenpermissions_rocc pk_aspenpermissions_rocc; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aspenpermissions_rocc
    ADD CONSTRAINT pk_aspenpermissions_rocc PRIMARY KEY (serial);


--
-- Name: dailytasks pk_dailytasks; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dailytasks
    ADD CONSTRAINT pk_dailytasks PRIMARY KEY (serial);


--
-- Name: dtproperties pk_dtproperties; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dtproperties
    ADD CONSTRAINT pk_dtproperties PRIMARY KEY (id, property);


--
-- Name: emailfromaddressandsignature pk_emailfromaddressandsignature; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emailfromaddressandsignature
    ADD CONSTRAINT pk_emailfromaddressandsignature PRIMARY KEY (serial);


--
-- Name: emailsubscriptions pk_emailsubscriptions; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emailsubscriptions
    ADD CONSTRAINT pk_emailsubscriptions PRIMARY KEY (serial);


--
-- Name: environment pk_environment; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.environment
    ADD CONSTRAINT pk_environment PRIMARY KEY (id);


--
-- Name: environment_ops pk_environment_ops; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.environment_ops
    ADD CONSTRAINT pk_environment_ops PRIMARY KEY (environmentid);


--
-- Name: environment_pc pk_environment_pc; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.environment_pc
    ADD CONSTRAINT pk_environment_pc PRIMARY KEY (environmentid);


--
-- Name: environment_sub pk_environment_sub; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.environment_sub
    ADD CONSTRAINT pk_environment_sub PRIMARY KEY (id);


--
-- Name: event_templates pk_event_templates; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_templates
    ADD CONSTRAINT pk_event_templates PRIMARY KEY (serial);


--
-- Name: events pk_events; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT pk_events PRIMARY KEY (serial);


--
-- Name: infotaskno pk_infotaskno; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infotaskno
    ADD CONSTRAINT pk_infotaskno PRIMARY KEY (serial);


--
-- Name: opsreportstatuscolour pk_opsreportstatuscolour; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opsreportstatuscolour
    ADD CONSTRAINT pk_opsreportstatuscolour PRIMARY KEY (id);


--
-- Name: statutoryholidays pk_statutoryholidays; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.statutoryholidays
    ADD CONSTRAINT pk_statutoryholidays PRIMARY KEY (serial);


--
-- Name: templatedactivities pk_templatedactivities; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.templatedactivities
    ADD CONSTRAINT pk_templatedactivities PRIMARY KEY (id);


--
-- Name: turnoveractivities pk_turnoveractivities; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turnoveractivities
    ADD CONSTRAINT pk_turnoveractivities PRIMARY KEY (serial);


--
-- Name: turnoverenvironment pk_turnoverenvironment; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turnoverenvironment
    ADD CONSTRAINT pk_turnoverenvironment PRIMARY KEY (id);


--
-- Name: turnovermps pk_turnovermps; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turnovermps
    ADD CONSTRAINT pk_turnovermps PRIMARY KEY (id);


--
-- Name: turnovermpscycles pk_turnovermpscycles; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turnovermpscycles
    ADD CONSTRAINT pk_turnovermpscycles PRIMARY KEY (id);


--
-- Name: turnovermpsstatus pk_turnovermpsstatus; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turnovermpsstatus
    ADD CONSTRAINT pk_turnovermpsstatus PRIMARY KEY (id);


--
-- Name: turnovernotes pk_turnovernotes; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turnovernotes
    ADD CONSTRAINT pk_turnovernotes PRIMARY KEY (category);


--
-- Name: turnoveronlinesmainframe pk_turnoveronlinesmainframe; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turnoveronlinesmainframe
    ADD CONSTRAINT pk_turnoveronlinesmainframe PRIMARY KEY (database);


--
-- Name: turnoveronlinesv21 pk_turnoveronlinesv21; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turnoveronlinesv21
    ADD CONSTRAINT pk_turnoveronlinesv21 PRIMARY KEY (sortorder);


--
-- Name: turnoversubenvironment pk_turnoversubenvironment; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turnoversubenvironment
    ADD CONSTRAINT pk_turnoversubenvironment PRIMARY KEY (id);


--
-- Name: app_local_users uq_app_local_users_username; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_local_users
    ADD CONSTRAINT uq_app_local_users_username UNIQUE (username);


--
-- Name: ix_app_audit_log_occurred_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_app_audit_log_occurred_at ON public.app_audit_log USING btree (occurred_at DESC);


--
-- Name: ix_app_audit_log_username; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_app_audit_log_username ON public.app_audit_log USING btree (username);


--
-- Name: ix_app_local_users_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_app_local_users_enabled ON public.app_local_users USING btree (enabled, expires_at);


--
-- Name: ix_dailytasks_effective_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_dailytasks_effective_dates ON public.dailytasks USING btree (environment, effective_from, effective_to);


--
-- Name: ix_events_activity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_events_activity_id ON public.events USING btree (id);


--
-- Name: ux_activities_taskno_esttime_environment; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_activities_taskno_esttime_environment ON public.activities USING btree (taskno, est_time, environment);


--
-- Name: ux_aspenpermissions_pc_username; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_aspenpermissions_pc_username ON public.aspenpermissions_pc USING btree (username);


--
-- Name: ux_aspenpermissions_rocc_username; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_aspenpermissions_rocc_username ON public.aspenpermissions_rocc USING btree (username);


--
-- Name: ux_dailytasks_taskno_environment; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_dailytasks_taskno_environment ON public.dailytasks USING btree (taskno, environment);


--
-- Name: ux_emailfromaddress_department; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_emailfromaddress_department ON public.emailfromaddressandsignature USING btree (fromaddress, department);


--
-- Name: ux_emailfromaddress_department_only; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_emailfromaddress_department_only ON public.emailfromaddressandsignature USING btree (department);


--
-- Name: ux_emailsubscriptions_emailaddress; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_emailsubscriptions_emailaddress ON public.emailsubscriptions USING btree (emailaddress);


--
-- Name: ux_environment_dbkey; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_environment_dbkey ON public.environment USING btree (dbkey);


--
-- Name: ux_environment_sub_envid_description; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_environment_sub_envid_description ON public.environment_sub USING btree (envid, description);


--
-- Name: ux_environment_sub_envid_sortorder; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_environment_sub_envid_sortorder ON public.environment_sub USING btree (envid, sortorder);


--
-- Name: ux_infotaskno_weekday_environment; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_infotaskno_weekday_environment ON public.infotaskno USING btree (weekday, environment);


--
-- Name: ux_opsreportstatuscolour_status; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_opsreportstatuscolour_status ON public.opsreportstatuscolour USING btree (status);


--
-- Name: ux_statutoryholidays_holiday; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_statutoryholidays_holiday ON public.statutoryholidays USING btree (holiday);


--
-- Name: ux_turnoveractivities_activityid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_turnoveractivities_activityid ON public.turnoveractivities USING btree (activityid);


--
-- Name: ux_turnoverenvironment_sortorder; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_turnoverenvironment_sortorder ON public.turnoverenvironment USING btree (sortorder);


--
-- Name: ux_turnovermpsstatus_environment_sortorder; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_turnovermpsstatus_environment_sortorder ON public.turnovermpsstatus USING btree (statusenvironment, sortorder);


--
-- Name: ux_turnovernotes_sortorder; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_turnovernotes_sortorder ON public.turnovernotes USING btree (sortorder);


--
-- Name: ux_turnoveronlinesmainframe_sortorder; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_turnoveronlinesmainframe_sortorder ON public.turnoveronlinesmainframe USING btree (sortorder);


--
-- Name: environment_ops fk_environment_ops_environment; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.environment_ops
    ADD CONSTRAINT fk_environment_ops_environment FOREIGN KEY (environmentid) REFERENCES public.environment(id);


--
-- Name: environment_pc fk_environment_pc_environment; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.environment_pc
    ADD CONSTRAINT fk_environment_pc_environment FOREIGN KEY (environmentid) REFERENCES public.environment(id);


--
-- Name: environment_sub fk_environment_sub_environment; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.environment_sub
    ADD CONSTRAINT fk_environment_sub_environment FOREIGN KEY (envid) REFERENCES public.environment(id);


--
-- Name: events fk_events_activities; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_events_activities FOREIGN KEY (id) REFERENCES public.activities(id);


--
-- Name: turnoveractivities fk_turnoveractivities_activities; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turnoveractivities
    ADD CONSTRAINT fk_turnoveractivities_activities FOREIGN KEY (activityid) REFERENCES public.activities(id);


--
-- Name: turnoveractivities fk_turnoveractivities_environment; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turnoveractivities
    ADD CONSTRAINT fk_turnoveractivities_environment FOREIGN KEY (environmentid) REFERENCES public.turnoverenvironment(id);


--
-- Name: turnoveractivities fk_turnoveractivities_subenvironment; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turnoveractivities
    ADD CONSTRAINT fk_turnoveractivities_subenvironment FOREIGN KEY (subenvid) REFERENCES public.turnoversubenvironment(id);


--
-- Name: turnovermpscycles fk_turnovermpscycles_turnovermps; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turnovermpscycles
    ADD CONSTRAINT fk_turnovermpscycles_turnovermps FOREIGN KEY (mpsid) REFERENCES public.turnovermps(id);


--
-- Name: turnoversubenvironment fk_turnoversubenvironment_environment; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turnoversubenvironment
    ADD CONSTRAINT fk_turnoversubenvironment_environment FOREIGN KEY (environmentid) REFERENCES public.turnoverenvironment(id);


--
-- PostgreSQL database dump complete
--

