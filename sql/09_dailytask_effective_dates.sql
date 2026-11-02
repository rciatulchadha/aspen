\set ON_ERROR_STOP on

BEGIN;


-- ============================================================
-- DAILY TASK EFFECTIVE-DATE WINDOW
--
-- effective_from:
--   First schedule date on which the template is eligible.
--
-- effective_to:
--   Last eligible schedule date.
--   NULL means the template remains active indefinitely.
-- ============================================================

ALTER TABLE dailytasks
ADD COLUMN IF NOT EXISTS
    effective_from date;


ALTER TABLE dailytasks
ADD COLUMN IF NOT EXISTS
    effective_to date;


-- Existing migrated Daily Tasks must remain eligible.
--
-- Use the earliest Activity date rather than CURRENT_DATE so
-- historical schedule preview and validation remain possible.

UPDATE dailytasks
SET effective_from = (
    SELECT
        COALESCE(
            MIN(est_time)::date,
            CURRENT_DATE
        )
    FROM activities
)
WHERE effective_from IS NULL;


ALTER TABLE dailytasks
ALTER COLUMN effective_from
SET NOT NULL;


ALTER TABLE dailytasks
ALTER COLUMN effective_from
SET DEFAULT CURRENT_DATE;


DO $migration$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname =
            'ck_dailytasks_effective_dates'
    ) THEN

        ALTER TABLE dailytasks
        ADD CONSTRAINT
            ck_dailytasks_effective_dates

        CHECK (
            effective_to IS NULL
            OR effective_to >= effective_from
        );

    END IF;

END;
$migration$;


CREATE INDEX IF NOT EXISTS
    ix_dailytasks_effective_dates

ON dailytasks (
    environment,
    effective_from,
    effective_to
);


COMMIT;
