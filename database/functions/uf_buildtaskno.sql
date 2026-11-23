CREATE OR REPLACE FUNCTION public.uf_buildtaskno(p_env character varying, p_weekday character varying)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
    SELECT taskno
    FROM infotaskno
    WHERE environment = p_env
      AND weekday = p_weekday;
$function$

