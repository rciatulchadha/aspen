CREATE OR REPLACE FUNCTION public.uf_gettoactdetails(p_id integer)
 RETURNS TABLE(envdescription character varying, subenvdescription character varying, eoxdate timestamp without time zone, comments text)
 LANGUAGE sql
 STABLE
AS $function$

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

$function$

