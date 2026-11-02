BEGIN;

-- ============================================================
-- vw_TurnoverMPS
-- Latest TurnoverMPS record formatted for display
-- ============================================================

CREATE OR REPLACE VIEW vw_turnovermps AS
SELECT
    id,

    (
        CASE
            WHEN collections = 1
                THEN collections::varchar || ' Collection'
            ELSE collections::varchar || ' Collections'
        END
        || ', ' ||
        CASE
            WHEN maindrivers = 1
                THEN maindrivers::varchar || ' Maindriver'
            ELSE maindrivers::varchar || ' Maindrivers'
        END
        || ', ' ||
        CASE
            WHEN guiders = 1
                THEN guiders::varchar || ' Guider'
            ELSE guiders::varchar || ' Guiders'
        END
        || '.'
    ) AS mpsconfiguration,

    to_char(
        mpupappgdtime,
        'HH24:MI'
    ) AS mpupappgdtime,

    (
        to_char(premaf1date, 'FMMonth')
        || ' '
        || EXTRACT(day FROM premaf1date)::integer
        || ' '
        || premaf1status
    ) AS premaf1,

    (
        to_char(premaf4date, 'FMMonth')
        || ' '
        || EXTRACT(day FROM premaf4date)::integer
        || ' '
        || premaf4status
    ) AS premaf4,

    (
        'Ciber Incollect Loaded - '
        || cibervolser1
        || ', Ciber Outcollect Loaded - '
        || cibervolser2
    ) AS ciberline1,

    (
        'Ciber Outcollect Created - '
        || cibervolser3
    ) AS ciberline2

FROM turnovermps

ORDER BY id DESC

LIMIT 1;


-- ============================================================
-- vw_TurnoverMPSCurrentCycles
-- Cycles belonging to latest MPS record
-- ============================================================

CREATE OR REPLACE VIEW vw_turnovermpscurrentcycles AS
SELECT
    replace(
        cycledetails,
        'Cycle ',
        ''
    )::varchar(200) AS cycledetails

FROM turnovermpscycles

WHERE mpsid = (
    SELECT MAX(id)
    FROM turnovermps
)

ORDER BY id;


-- ============================================================
-- vw_TurnoverMPSwithCycles
-- Latest MPS + associated cycles
-- ============================================================

CREATE OR REPLACE VIEW vw_turnovermpswithcycles AS
SELECT
    m.mpsconfiguration,
    m.mpupappgdtime,
    m.premaf1,
    m.premaf4,
    m.ciberline1,
    m.ciberline2,
    c.cycledetails

FROM vw_turnovermps m

JOIN turnovermpscycles c
    ON c.mpsid = m.id

ORDER BY c.id;


COMMIT;
