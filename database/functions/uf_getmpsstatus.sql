CREATE OR REPLACE FUNCTION public.uf_getmpsstatus(p_mpsenv character varying)
 RETURNS TABLE(description character varying)
 LANGUAGE sql
 STABLE
AS $function$

    SELECT
        s.description
    FROM turnovermpsstatus s
    WHERE s.statusenvironment IN (
        p_mpsenv,
        'All'
    )
    ORDER BY s.sortorder;

$function$

