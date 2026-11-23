CREATE OR REPLACE FUNCTION public.uf_valideoxdate(p_eoxdate timestamp without time zone, p_eoxenv character varying)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
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
$function$

