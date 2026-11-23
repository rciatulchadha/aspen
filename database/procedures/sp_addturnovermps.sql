CREATE OR REPLACE PROCEDURE public.sp_addturnovermps(IN p_collections integer, IN p_maindrivers integer, IN p_guiders integer, IN p_mpupappgd timestamp without time zone, IN p_cycle1 character varying, IN p_cycle2 character varying DEFAULT ''::character varying, IN p_cycle3 character varying DEFAULT ''::character varying, IN p_cycle4 character varying DEFAULT ''::character varying, IN p_cycle5 character varying DEFAULT ''::character varying, IN p_cycle6 character varying DEFAULT ''::character varying, IN p_premaf1date timestamp without time zone DEFAULT NULL::timestamp without time zone, IN p_premaf1status character varying DEFAULT NULL::character varying, IN p_premaf4date timestamp without time zone DEFAULT NULL::timestamp without time zone, IN p_premaf4status character varying DEFAULT NULL::character varying, IN p_volser1 character varying DEFAULT NULL::character varying, IN p_volser2 character varying DEFAULT NULL::character varying, IN p_volser3 character varying DEFAULT NULL::character varying)
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$

