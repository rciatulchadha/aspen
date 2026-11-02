BEGIN;

ALTER TABLE environment_ops
    ADD CONSTRAINT fk_environment_ops_environment
    FOREIGN KEY (environmentid)
    REFERENCES environment (id);

ALTER TABLE environment_pc
    ADD CONSTRAINT fk_environment_pc_environment
    FOREIGN KEY (environmentid)
    REFERENCES environment (id);

ALTER TABLE environment_sub
    ADD CONSTRAINT fk_environment_sub_environment
    FOREIGN KEY (envid)
    REFERENCES environment (id);

ALTER TABLE events
    ADD CONSTRAINT fk_events_activities
    FOREIGN KEY (id)
    REFERENCES activities (id);

ALTER TABLE turnoveractivities
    ADD CONSTRAINT fk_turnoveractivities_activities
    FOREIGN KEY (activityid)
    REFERENCES activities (id);

ALTER TABLE turnoveractivities
    ADD CONSTRAINT fk_turnoveractivities_environment
    FOREIGN KEY (environmentid)
    REFERENCES turnoverenvironment (id);

ALTER TABLE turnoveractivities
    ADD CONSTRAINT fk_turnoveractivities_subenvironment
    FOREIGN KEY (subenvid)
    REFERENCES turnoversubenvironment (id);

ALTER TABLE turnovermpscycles
    ADD CONSTRAINT fk_turnovermpscycles_turnovermps
    FOREIGN KEY (mpsid)
    REFERENCES turnovermps (id);

ALTER TABLE turnoversubenvironment
    ADD CONSTRAINT fk_turnoversubenvironment_environment
    FOREIGN KEY (environmentid)
    REFERENCES turnoverenvironment (id);

COMMIT;

