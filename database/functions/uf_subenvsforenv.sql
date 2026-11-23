CREATE OR REPLACE FUNCTION public.uf_subenvsforenv(p_env character varying)
 RETURNS TABLE(description character varying)
 LANGUAGE sql
 STABLE
AS $function$

    SELECT
        s.description

    FROM turnoversubenvironment s

    JOIN turnoverenvironment e
        ON s.environmentid = e.id

    WHERE e.description = p_env

    ORDER BY s.sortorder;

$function$

