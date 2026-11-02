\set ON_ERROR_STOP on

BEGIN;


ALTER TABLE app_local_users
ADD COLUMN IF NOT EXISTS
    must_change_password boolean
    NOT NULL
    DEFAULT true;


ALTER TABLE app_local_users
ADD COLUMN IF NOT EXISTS
    password_changed_at
    timestamp without time zone;


-- Do not unexpectedly lock out existing emergency Admins.

UPDATE app_local_users
SET must_change_password = false
WHERE emergency_admin = true;


COMMIT;
