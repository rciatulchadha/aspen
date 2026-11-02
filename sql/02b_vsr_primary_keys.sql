BEGIN;

ALTER TABLE activities
    ADD CONSTRAINT pk_activities PRIMARY KEY (id);

ALTER TABLE activitylog_pc
    ADD CONSTRAINT pk_activitylog_pc PRIMARY KEY (id);

ALTER TABLE alerts
    ADD CONSTRAINT pk_alerts PRIMARY KEY (id);

ALTER TABLE archived_activities
    ADD CONSTRAINT pk_archived_activities PRIMARY KEY (id);

ALTER TABLE archived_events
    ADD CONSTRAINT pk_archived_events PRIMARY KEY (serial);

ALTER TABLE archived_activitylog_pc
    ADD CONSTRAINT pk_archived_activitylog_pc PRIMARY KEY (id);

ALTER TABLE aspenpermissions_pc
    ADD CONSTRAINT pk_aspenpermissions_pc PRIMARY KEY (serial);

ALTER TABLE aspenpermissions_rocc
    ADD CONSTRAINT pk_aspenpermissions_rocc PRIMARY KEY (serial);

ALTER TABLE dailytasks
    ADD CONSTRAINT pk_dailytasks PRIMARY KEY (serial);

ALTER TABLE dtproperties
    ADD CONSTRAINT pk_dtproperties
    PRIMARY KEY (id, property);

ALTER TABLE emailfromaddressandsignature
    ADD CONSTRAINT pk_emailfromaddressandsignature
    PRIMARY KEY (serial);

ALTER TABLE emailsubscriptions
    ADD CONSTRAINT pk_emailsubscriptions
    PRIMARY KEY (serial);

ALTER TABLE environment
    ADD CONSTRAINT pk_environment PRIMARY KEY (id);

ALTER TABLE environment_ops
    ADD CONSTRAINT pk_environment_ops
    PRIMARY KEY (environmentid);

ALTER TABLE environment_pc
    ADD CONSTRAINT pk_environment_pc
    PRIMARY KEY (environmentid);

ALTER TABLE environment_sub
    ADD CONSTRAINT pk_environment_sub PRIMARY KEY (id);

ALTER TABLE event_templates
    ADD CONSTRAINT pk_event_templates PRIMARY KEY (serial);

ALTER TABLE events
    ADD CONSTRAINT pk_events PRIMARY KEY (serial);

ALTER TABLE infotaskno
    ADD CONSTRAINT pk_infotaskno PRIMARY KEY (serial);

ALTER TABLE opsreportstatuscolour
    ADD CONSTRAINT pk_opsreportstatuscolour PRIMARY KEY (id);

ALTER TABLE statutoryholidays
    ADD CONSTRAINT pk_statutoryholidays PRIMARY KEY (serial);

ALTER TABLE templatedactivities
    ADD CONSTRAINT pk_templatedactivities PRIMARY KEY (id);

ALTER TABLE turnoveractivities
    ADD CONSTRAINT pk_turnoveractivities PRIMARY KEY (serial);

ALTER TABLE turnoverenvironment
    ADD CONSTRAINT pk_turnoverenvironment PRIMARY KEY (id);

ALTER TABLE turnovermps
    ADD CONSTRAINT pk_turnovermps PRIMARY KEY (id);

ALTER TABLE turnovermpscycles
    ADD CONSTRAINT pk_turnovermpscycles PRIMARY KEY (id);

ALTER TABLE turnovermpsstatus
    ADD CONSTRAINT pk_turnovermpsstatus PRIMARY KEY (id);

ALTER TABLE turnovernotes
    ADD CONSTRAINT pk_turnovernotes PRIMARY KEY (category);

ALTER TABLE turnoveronlinesmainframe
    ADD CONSTRAINT pk_turnoveronlinesmainframe PRIMARY KEY (database);

ALTER TABLE turnoveronlinesv21
    ADD CONSTRAINT pk_turnoveronlinesv21 PRIMARY KEY (sortorder);

ALTER TABLE turnoversubenvironment
    ADD CONSTRAINT pk_turnoversubenvironment PRIMARY KEY (id);

COMMIT;
