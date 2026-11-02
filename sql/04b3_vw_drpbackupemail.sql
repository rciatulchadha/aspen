BEGIN;

CREATE OR REPLACE VIEW vw_drpbackupemail AS
SELECT
    (
        'Task #'
        || taskno::varchar
        || ' - Title:  '
        || title
        || ' - Status:  '
        || status
    ) AS drpdetails

FROM activities

WHERE environment = 'netbackup'

  AND est_time BETWEEN
      CURRENT_TIMESTAMP - INTERVAL '1 day'
      AND CURRENT_TIMESTAMP

  AND (
       taskno::text LIKE '%080'
    OR taskno::text LIKE '%017'
    OR taskno::text LIKE '%015'
    OR taskno::text LIKE '%019'
    OR taskno::text LIKE '%079'
  )

  AND deleted = false;

COMMIT;
