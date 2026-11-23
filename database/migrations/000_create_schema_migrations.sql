BEGIN;

CREATE TABLE IF NOT EXISTS public.schema_migrations (
    version varchar(100) PRIMARY KEY,
    description text NOT NULL,
    applied_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    applied_by varchar(200) NOT NULL DEFAULT CURRENT_USER
);

COMMIT;
