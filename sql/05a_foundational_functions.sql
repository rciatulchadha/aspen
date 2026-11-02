BEGIN;

-- ============================================================
-- 1. uf_DayWithStringEnd
--
-- SQL Server behavior examples:
-- 1  -> 1st
-- 2  -> 2nd
-- 3  -> 3rd
-- 21 -> 21st
-- 31 -> 31st
--
-- Preserves the exact legacy ASPEN rules.
-- ============================================================

CREATE OR REPLACE FUNCTION uf_daywithstringend(
    p_date timestamp without time zone
)
RETURNS varchar(4)
LANGUAGE plpgsql
IMMUTABLE
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


-- ============================================================
-- 2. uf_ValidEOXDate
--
-- SQL Server rules:
--
-- EOD       -> every date is valid
-- EOD/W     -> Sunday
-- EOD/M     -> last day of month
-- EOD/W/M   -> Sunday AND last day of month
--
-- Python/PostgreSQL week calculation is avoided here.
-- ISO DOW gives Monday=1 ... Sunday=7.
-- ============================================================

CREATE OR REPLACE FUNCTION uf_valideoxdate(
    p_eoxdate timestamp without time zone,
    p_eoxenv varchar(10)
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
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


-- ============================================================
-- 3. uf_BuildTaskNo
--
-- Existing SQL Server function simply looks up TaskNo
-- by Environment + Weekday.
-- ============================================================

CREATE OR REPLACE FUNCTION uf_buildtaskno(
    p_env varchar(10),
    p_weekday varchar(10)
)
RETURNS integer
LANGUAGE sql
STABLE
AS $$
    SELECT taskno
    FROM infotaskno
    WHERE environment = p_env
      AND weekday = p_weekday;
$$;

COMMIT;
