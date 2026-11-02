\set ON_ERROR_STOP on

\echo '============================================================'
\echo 'VSR PostgreSQL Migration Validation'
\echo '============================================================'


-- ============================================================
-- 1. DATABASE
-- ============================================================

\echo ''
\echo '--- DATABASE ---'

SELECT
    current_database() AS database,
    current_user AS username,
    version();


-- ============================================================
-- 2. TABLE INVENTORY
-- ============================================================

\echo ''
\echo '--- TABLE COUNT ---'

SELECT COUNT(*) AS table_count
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE';


-- ============================================================
-- 3. TABLE ROW COUNTS
-- ============================================================

\echo ''
\echo '--- TABLE ROW COUNTS ---'

SELECT 'Activities' AS table_name, COUNT(*) AS row_count FROM activities
UNION ALL SELECT 'ActivityLog_PC', COUNT(*) FROM activitylog_pc
UNION ALL SELECT 'Alerts', COUNT(*) FROM alerts
UNION ALL SELECT 'Archived Activities', COUNT(*) FROM archived_activities
UNION ALL SELECT 'Archived Events', COUNT(*) FROM archived_events
UNION ALL SELECT 'Archived_ActivityLog_PC', COUNT(*) FROM archived_activitylog_pc
UNION ALL SELECT 'ASPENPermissions_PC', COUNT(*) FROM aspenpermissions_pc
UNION ALL SELECT 'ASPENPermissions_ROCC', COUNT(*) FROM aspenpermissions_rocc
UNION ALL SELECT 'DailyTasks', COUNT(*) FROM dailytasks
UNION ALL SELECT 'dtproperties', COUNT(*) FROM dtproperties
UNION ALL SELECT 'EmailFromAddressAndSignature', COUNT(*) FROM emailfromaddressandsignature
UNION ALL SELECT 'EmailSubscriptions', COUNT(*) FROM emailsubscriptions
UNION ALL SELECT 'Environment', COUNT(*) FROM environment
UNION ALL SELECT 'Environment_Ops', COUNT(*) FROM environment_ops
UNION ALL SELECT 'Environment_PC', COUNT(*) FROM environment_pc
UNION ALL SELECT 'Environment_Sub', COUNT(*) FROM environment_sub
UNION ALL SELECT 'Event Templates', COUNT(*) FROM event_templates
UNION ALL SELECT 'Events', COUNT(*) FROM events
UNION ALL SELECT 'InfoTaskNo', COUNT(*) FROM infotaskno
UNION ALL SELECT 'OpsReportStatusColour', COUNT(*) FROM opsreportstatuscolour
UNION ALL SELECT 'StatutoryHolidays', COUNT(*) FROM statutoryholidays
UNION ALL SELECT 'TemplatedActivities', COUNT(*) FROM templatedactivities
UNION ALL SELECT 'TurnoverActivities', COUNT(*) FROM turnoveractivities
UNION ALL SELECT 'TurnoverEnvironment', COUNT(*) FROM turnoverenvironment
UNION ALL SELECT 'TurnoverMPS', COUNT(*) FROM turnovermps
UNION ALL SELECT 'TurnoverMPSCycles', COUNT(*) FROM turnovermpscycles
UNION ALL SELECT 'TurnoverMPSStatus', COUNT(*) FROM turnovermpsstatus
UNION ALL SELECT 'TurnoverNotes', COUNT(*) FROM turnovernotes
UNION ALL SELECT 'TurnoverOnlinesMainframe', COUNT(*) FROM turnoveronlinesmainframe
UNION ALL SELECT 'TurnoverOnlinesV21', COUNT(*) FROM turnoveronlinesv21
UNION ALL SELECT 'TurnoverSubEnvironment', COUNT(*) FROM turnoversubenvironment
ORDER BY table_name;


-- ============================================================
-- 4. PRIMARY KEYS
-- ============================================================

\echo ''
\echo '--- PRIMARY KEYS ---'

SELECT COUNT(*) AS primary_key_count
FROM information_schema.table_constraints
WHERE table_schema = 'public'
  AND constraint_type = 'PRIMARY KEY';


-- ============================================================
-- 5. FOREIGN KEYS
-- ============================================================

\echo ''
\echo '--- FOREIGN KEYS ---'

SELECT COUNT(*) AS foreign_key_count
FROM information_schema.table_constraints
WHERE table_schema = 'public'
  AND constraint_type = 'FOREIGN KEY';

SELECT
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS referenced_table,
    ccu.column_name AS referenced_column
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
   AND tc.constraint_schema = kcu.constraint_schema
JOIN information_schema.constraint_column_usage ccu
    ON tc.constraint_name = ccu.constraint_name
   AND tc.constraint_schema = ccu.constraint_schema
WHERE tc.table_schema = 'public'
  AND tc.constraint_type = 'FOREIGN KEY'
ORDER BY tc.table_name;


-- ============================================================
-- 6. INDEX INVENTORY
-- ============================================================

\echo ''
\echo '--- INDEX COUNT ---'

SELECT COUNT(*) AS index_count
FROM pg_indexes
WHERE schemaname = 'public';


-- ============================================================
-- 7. VIEW INVENTORY
-- ============================================================

\echo ''
\echo '--- VIEWS ---'

SELECT
    table_name AS view_name
FROM information_schema.views
WHERE table_schema = 'public'
ORDER BY table_name;


-- ============================================================
-- 8. FUNCTION / PROCEDURE INVENTORY
-- ============================================================

\echo ''
\echo '--- FUNCTIONS AND PROCEDURES ---'

SELECT
    routine_type,
    routine_name
FROM information_schema.routines
WHERE routine_schema = 'public'
ORDER BY routine_type, routine_name;


-- ============================================================
-- 9. FK ORPHAN VALIDATION
-- ============================================================

\echo ''
\echo '--- ORPHAN VALIDATION ---'

SELECT
    'events -> activities' AS relationship,
    COUNT(*) AS orphan_count
FROM events e
LEFT JOIN activities a
    ON a.id = e.id
WHERE a.id IS NULL

UNION ALL

SELECT
    'environment_ops -> environment',
    COUNT(*)
FROM environment_ops x
LEFT JOIN environment e
    ON e.id = x.environmentid
WHERE e.id IS NULL

UNION ALL

SELECT
    'environment_pc -> environment',
    COUNT(*)
FROM environment_pc x
LEFT JOIN environment e
    ON e.id = x.environmentid
WHERE e.id IS NULL

UNION ALL

SELECT
    'environment_sub -> environment',
    COUNT(*)
FROM environment_sub x
LEFT JOIN environment e
    ON e.id = x.envid
WHERE e.id IS NULL

UNION ALL

SELECT
    'turnoversubenvironment -> turnoverenvironment',
    COUNT(*)
FROM turnoversubenvironment x
LEFT JOIN turnoverenvironment e
    ON e.id = x.environmentid
WHERE e.id IS NULL

UNION ALL

SELECT
    'turnovermpscycles -> turnovermps',
    COUNT(*)
FROM turnovermpscycles c
LEFT JOIN turnovermps m
    ON m.id = c.mpsid
WHERE m.id IS NULL;


-- ============================================================
-- 10. CORE DATA CONTROLS
-- ============================================================

\echo ''
\echo '--- ACTIVITIES CONTROLS ---'

SELECT
    COUNT(*) AS rows,
    MIN(id) AS min_id,
    MAX(id) AS max_id,
    COUNT(*) FILTER (WHERE closed = 'Yes') AS closed_yes,
    COUNT(*) FILTER (WHERE closed = 'No') AS closed_no,
    COUNT(*) FILTER (WHERE deleted) AS deleted,
    COUNT(*) FILTER (WHERE unplannedact) AS unplanned,
    COUNT(*) FILTER (WHERE criticalact) AS critical
FROM activities;


\echo ''
\echo '--- EVENTS CONTROLS ---'

SELECT
    COUNT(*) AS rows,
    MIN(serial) AS min_serial,
    MAX(serial) AS max_serial,
    COUNT(DISTINCT id) AS distinct_activity_ids
FROM events;


\echo ''
\echo '--- DAILY TASKS CONTROLS ---'

SELECT
    COUNT(*) AS rows,
    COUNT(*) FILTER (WHERE "time" IS NULL) AS null_times,
    COUNT(*) FILTER (
        WHERE "time" IS NOT NULL
          AND "time"::time IS NOT NULL
    ) AS valid_times
FROM dailytasks;


-- ============================================================
-- 11. IDENTITY SEQUENCE VALIDATION
-- ============================================================

\echo ''
\echo '--- IMPORTANT SEQUENCES ---'

SELECT
    'activities' AS table_name,
    MAX(id)::bigint AS max_value,
    (SELECT last_value FROM activities_id_seq)::bigint
        AS sequence_value
FROM activities

UNION ALL

SELECT
    'events',
    MAX(serial)::bigint,
    (SELECT last_value FROM events_serial_seq)::bigint
FROM events

UNION ALL

SELECT
    'turnovermps',
    MAX(id)::bigint,
    (SELECT last_value FROM turnovermps_id_seq)::bigint
FROM turnovermps

UNION ALL

SELECT
    'turnovermpscycles',
    MAX(id)::bigint,
    (SELECT last_value FROM turnovermpscycles_id_seq)::bigint
FROM turnovermpscycles

UNION ALL

SELECT
    'infotaskno',
    MAX(serial)::bigint,
    (SELECT last_value FROM infotaskno_serial_seq)::bigint
FROM infotaskno

UNION ALL

SELECT
    'dailytasks',
    MAX(serial)::bigint,
    (SELECT last_value FROM dailytasks_serial_seq)::bigint
FROM dailytasks;


-- ============================================================
-- 12. EOX FUNCTION REGRESSION
-- ============================================================

\echo ''
\echo '--- EOX REGRESSION ---'

SELECT
    uf_daywithstringend(
        TIMESTAMP '2026-10-01'
    ) AS day_1,

    uf_daywithstringend(
        TIMESTAMP '2026-10-02'
    ) AS day_2,

    uf_daywithstringend(
        TIMESTAMP '2026-10-03'
    ) AS day_3,

    uf_daywithstringend(
        TIMESTAMP '2026-10-31'
    ) AS day_31;


SELECT
    uf_autoeoxreplace(
        'Processing EOX',
        101,
        TIMESTAMP '2026-10-18',
        '7'
    ) AS sunday,

    uf_autoeoxreplace(
        'Processing EOX',
        101,
        TIMESTAMP '2026-10-31',
        '6'
    ) AS month_end,

    uf_autoeoxreplace(
        'Processing EOX',
        101,
        TIMESTAMP '2026-05-31',
        '7'
    ) AS sunday_month_end;


-- ============================================================
-- 13. DAILY SCHEDULING REGRESSION
-- ============================================================

\echo ''
\echo '--- DAILY SCHEDULING REGRESSION ---'

SELECT
    (
        SELECT COUNT(*)
        FROM uf_autoeoxdailylist(
            'v21',
            '1',
            3
        )
    ) AS source_function_rows,

    (
        SELECT COUNT(*)
        FROM uf_autoeoxreplacedailylist(
            'v21',
            TIMESTAMP '2026-10-19',
            '1'
        )
    ) AS replacement_function_rows;


-- ============================================================
-- 14. TASK NUMBER VALIDATION
-- ============================================================

\echo ''
\echo '--- USED / AVAILABLE TASK NUMBER COLLISION CHECK ---'

SELECT COUNT(*) AS collisions
FROM uf_usedtasknumbers(
    'v21',
    '1',
    3
) u

JOIN uf_availabletasknumbers(
    '1',
    'v21'
) a
    ON a.taskno = u.taskno;


-- ============================================================
-- 15. ROCC REPORT SMOKE TEST
-- ============================================================

\echo ''
\echo '--- ROCC REPORT SMOKE TEST ---'

SELECT COUNT(*) AS report_rows
FROM uf_roccreport(
    'v21',
    TIMESTAMP '2026-10-01 00:00:00',
    TIMESTAMP '2026-10-02 23:59:59'
);


-- ============================================================
-- 16. MPS VIEW VALIDATION
-- ============================================================

\echo ''
\echo '--- MPS VIEWS ---'

SELECT
    (SELECT COUNT(*) FROM vw_turnovermps)
        AS current_mps_rows,

    (SELECT COUNT(*) FROM vw_turnovermpscurrentcycles)
        AS current_cycle_rows,

    (SELECT COUNT(*) FROM vw_turnovermpswithcycles)
        AS mps_with_cycle_rows;


\echo ''
\echo '============================================================'
\echo 'VALIDATION COMPLETE'
\echo '============================================================'
