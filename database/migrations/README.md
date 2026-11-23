# ASPEN Database Migrations

This directory contains incremental PostgreSQL changes for ASPEN.

## Naming

Use sequential migration numbers:

001_description.sql
002_description.sql
003_description.sql

Migration 000 creates the migration-tracking table.

## Rules

- Never edit a migration after it has been deployed.
- Create a new migration for subsequent changes.
- Test migrations before production deployment.
- Use transactions where PostgreSQL permits them.
- Deployment must stop on the first SQL error.
- Production data must not be stored in migration files unless the SQL represents explicitly reviewed reference/configuration data.
- Credentials and Secret values must never be stored here.

## Tracking

Applied migrations are recorded in:

public.schema_migrations

The migration version is the filename prefix.

Example:

001_add_activity_index.sql

is recorded as version:

001

Git is the source of truth for ASPEN database schema and database code.
