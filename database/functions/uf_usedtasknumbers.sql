CREATE OR REPLACE FUNCTION public.uf_usedtasknumbers(p_env character varying, p_weekday character, p_tasklength integer)
 RETURNS TABLE(taskno integer)
 LANGUAGE sql
 STABLE
AS $function$

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

$function$

