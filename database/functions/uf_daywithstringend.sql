CREATE OR REPLACE FUNCTION public.uf_daywithstringend(p_date timestamp without time zone)
 RETURNS character varying
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
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
$function$

