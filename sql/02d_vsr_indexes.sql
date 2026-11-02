-- ============================================================
-- ASPEN / VSR
-- Step 2D - Secondary and Unique Indexes
-- Target: PostgreSQL 15
--
-- Primary-key indexes are NOT repeated here.
-- ============================================================

BEGIN;


-- ============================================================
-- ACTIVITIES
-- SQL Server: TaslNo_Est_Time
-- UNIQUE(Taskno, Est_Time, Environment)
-- ============================================================

CREATE UNIQUE INDEX ux_activities_taskno_esttime_environment
    ON activities (taskno, est_time, environment);


-- ============================================================
-- ARCHIVED ACTIVITY LOG PC
-- Original SQL Server secondary index on ID
--
-- Note:
-- PostgreSQL already has the PK index on ID from Step 2B.
-- Therefore this duplicate non-unique index is intentionally
-- NOT recreated.
-- ============================================================


-- ============================================================
-- ASPEN PERMISSIONS PC
-- ============================================================

CREATE UNIQUE INDEX ux_aspenpermissions_pc_username
    ON aspenpermissions_pc (username);


-- ============================================================
-- ASPEN PERMISSIONS ROCC
-- ============================================================

CREATE UNIQUE INDEX ux_aspenpermissions_rocc_username
    ON aspenpermissions_rocc (username);


-- ============================================================
-- DAILY TASKS
-- ============================================================

CREATE UNIQUE INDEX ux_dailytasks_taskno_environment
    ON dailytasks (taskno, environment);


-- ============================================================
-- EMAIL FROM ADDRESS AND SIGNATURE
-- ============================================================

CREATE UNIQUE INDEX ux_emailfromaddress_department
    ON emailfromaddressandsignature (fromaddress, department);

CREATE UNIQUE INDEX ux_emailfromaddress_department_only
    ON emailfromaddressandsignature (department);


-- ============================================================
-- EMAIL SUBSCRIPTIONS
-- ============================================================

CREATE UNIQUE INDEX ux_emailsubscriptions_emailaddress
    ON emailsubscriptions (emailaddress);


-- ============================================================
-- ENVIRONMENT
-- ============================================================

CREATE UNIQUE INDEX ux_environment_dbkey
    ON environment (dbkey);


-- ============================================================
-- ENVIRONMENT SUB
-- ============================================================

CREATE UNIQUE INDEX ux_environment_sub_envid_description
    ON environment_sub (envid, description);

CREATE UNIQUE INDEX ux_environment_sub_envid_sortorder
    ON environment_sub (envid, sortorder);


-- ============================================================
-- EVENTS
--
-- SQL Server had a non-unique secondary index on Events.ID.
-- This is important because ID is the Activity foreign key
-- and is used heavily in activity/event joins.
-- ============================================================

CREATE INDEX ix_events_activity_id
    ON events (id);


-- ============================================================
-- INFO TASK NUMBER
-- ============================================================

CREATE UNIQUE INDEX ux_infotaskno_weekday_environment
    ON infotaskno (weekday, environment);


-- ============================================================
-- OPS REPORT STATUS COLOUR
-- ============================================================

CREATE UNIQUE INDEX ux_opsreportstatuscolour_status
    ON opsreportstatuscolour (status);


-- ============================================================
-- STATUTORY HOLIDAYS
-- ============================================================

CREATE UNIQUE INDEX ux_statutoryholidays_holiday
    ON statutoryholidays (holiday);


-- ============================================================
-- TURNOVER ACTIVITIES
-- ============================================================

CREATE UNIQUE INDEX ux_turnoveractivities_activityid
    ON turnoveractivities (activityid);


-- ============================================================
-- TURNOVER ENVIRONMENT
-- ============================================================

CREATE UNIQUE INDEX ux_turnoverenvironment_sortorder
    ON turnoverenvironment (sortorder);


-- ============================================================
-- TURNOVER MPS STATUS
-- ============================================================

CREATE UNIQUE INDEX ux_turnovermpsstatus_environment_sortorder
    ON turnovermpsstatus (statusenvironment, sortorder);


-- ============================================================
-- TURNOVER NOTES
-- ============================================================

CREATE UNIQUE INDEX ux_turnovernotes_sortorder
    ON turnovernotes (sortorder);


-- ============================================================
-- TURNOVER ONLINES MAINFRAME
-- ============================================================

CREATE UNIQUE INDEX ux_turnoveronlinesmainframe_sortorder
    ON turnoveronlinesmainframe (sortorder);


COMMIT;
