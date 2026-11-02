\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION uf_eoxreplace(
    p_templatedstring varchar(4000),
    p_taskno integer,
    p_today timestamp without time zone,
    p_weekdayno char(1)
)
RETURNS varchar(8000)
LANGUAGE plpgsql
IMMUTABLE
AS $func$
DECLARE
    v_result text;
    v_jobtype varchar(20);
    v_tomorrow timestamp without time zone;
BEGIN
    IF p_templatedstring IS NULL THEN
        RETURN NULL;
    END IF;

    v_result := p_templatedstring;
    v_tomorrow := p_today + INTERVAL '1 day';

    v_jobtype :=
        CASE
            WHEN p_weekdayno = '7'
             AND EXTRACT(month FROM p_today)
                 != EXTRACT(month FROM v_tomorrow)
                THEN 'EOD/EOW/EOM'

            WHEN p_weekdayno = '7'
                THEN 'EOD/EOW'

            WHEN EXTRACT(month FROM p_today)
                 != EXTRACT(month FROM v_tomorrow)
                THEN 'EOD/EOM'

            ELSE 'EOD'
        END;

    IF p_taskno < 100 THEN
        v_result := p_weekdayno || '000' || v_result;
    END IF;

    v_result := replace(v_result, 'EOX', v_jobtype);

    v_result := replace(
        v_result,
        'TODAYSDATEHERE',
        to_char(p_today, 'FMMonth')
        || ' '
        || uf_daywithstringend(p_today)
    );

    v_result := replace(
        v_result,
        'TODAYPLUSONE',
        to_char(v_tomorrow, 'FMMonth')
        || ' '
        || uf_daywithstringend(v_tomorrow)
    );

    v_result := replace(
        v_result,
        'WEEKDAYNO',
        p_weekdayno
    );

    RETURN v_result::varchar(8000);
END;
$func$;


CREATE OR REPLACE FUNCTION uf_autoeoxreplace(
    p_templatedstring varchar(4000),
    p_taskno integer,
    p_today timestamp without time zone,
    p_weekdayno char(1)
)
RETURNS varchar(8000)
LANGUAGE plpgsql
IMMUTABLE
AS $func$
DECLARE
    v_result text;
    v_jobtype varchar(20);
    v_tomorrow timestamp without time zone;
BEGIN
    IF p_templatedstring IS NULL THEN
        RETURN NULL;
    END IF;

    v_result := p_templatedstring;
    v_tomorrow := p_today + INTERVAL '1 day';

    v_jobtype :=
        CASE
            WHEN p_weekdayno = '7'
             AND EXTRACT(month FROM p_today)
                 != EXTRACT(month FROM v_tomorrow)
                THEN 'EOD/EOW/EOM'

            WHEN p_weekdayno = '7'
                THEN 'EOD/EOW'

            WHEN EXTRACT(month FROM p_today)
                 != EXTRACT(month FROM v_tomorrow)
                THEN 'EOD/EOM'

            ELSE 'EOD'
        END;

    v_result := replace(v_result, 'EOX', v_jobtype);

    v_result := replace(
        v_result,
        'TODAYSDATEHERE',
        to_char(p_today, 'FMMonth')
        || ' '
        || uf_daywithstringend(p_today)
    );

    v_result := replace(
        v_result,
        'TODAYPLUSONE',
        to_char(v_tomorrow, 'FMMonth')
        || ' '
        || uf_daywithstringend(v_tomorrow)
    );

    v_result := replace(
        v_result,
        'WEEKDAYNO',
        p_weekdayno
    );

    RETURN v_result::varchar(8000);
END;
$func$;

COMMIT;
