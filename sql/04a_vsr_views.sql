BEGIN;

-- ============================================================
-- 1. vw_Environment_Ops
-- ============================================================

CREATE OR REPLACE VIEW vw_environment_ops AS
SELECT
    e.description,
    e.dbkey,
    o.billenabled,
    o.colourstart,
    o.colourend,

    to_char(
        CURRENT_DATE + o.fromdatediff,
        'YYYY-MM-DD'
    ) AS fromdate,

    o.fromtime,

    to_char(
        CURRENT_DATE + o.todatediff,
        'YYYY-MM-DD'
    ) AS todate,

    o.totime,
    o.activitiestable

FROM environment e
JOIN environment_ops o
    ON e.id = o.environmentid;


-- ============================================================
-- 2. vw_Environment_PC
-- ============================================================

CREATE OR REPLACE VIEW vw_environment_pc AS
SELECT
    e.description,
    e.dbkey,
    e.commandline,
    p.timeend,

    to_char(
        CURRENT_DATE + p.fromdatediff,
        'YYYY-MM-DD'
    ) AS fromdate,

    to_char(
        CURRENT_DATE + p.todatediff,
        'YYYY-MM-DD'
    ) AS todate,

    e.tasklength

FROM environment e
JOIN environment_pc p
    ON e.id = p.environmentid;


-- ============================================================
-- 3. vw_Environment_PC_Report
-- ============================================================

CREATE OR REPLACE VIEW vw_environment_pc_report AS
SELECT
    e.description,
    e.dbkey,
    e.commandline,
    p.reporttitle,
    p.reporttimefrom,
    p.reporttimeto,
    p.reportdrafttime,
    p.reportfinaltime

FROM environment e
JOIN environment_pc p
    ON e.id = p.environmentid;


-- ============================================================
-- 4. vw_Environment_Sub
-- ============================================================

CREATE OR REPLACE VIEW vw_environment_sub AS
SELECT
    e.description AS env,
    e.dbkey AS envkey,
    s.description AS subenv,
    s.sortorder

FROM environment e
JOIN environment_sub s
    ON e.id = s.envid;


-- ============================================================
-- 5. vw_Permissions_PC
--
-- This intentionally preserves the legacy ASPEN matching logic.
-- We will redesign the permission model later.
-- ============================================================

CREATE OR REPLACE VIEW vw_permissions_pc AS
SELECT
    p.username,
    e.dbkey,
    e.commandline,
    e.description

FROM environment e
JOIN aspenpermissions_pc p
    ON p.envavailable LIKE
       '%' || CAST(e.id AS varchar) || '%';


-- ============================================================
-- 6. vw_ResourcesAvailable
-- ============================================================

CREATE OR REPLACE VIEW vw_resourcesavailable AS
SELECT DISTINCT
    resource,
    environment

FROM activities

WHERE resource <> '';


COMMIT;
