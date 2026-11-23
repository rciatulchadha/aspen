# ASPEN PostgreSQL Database

This directory contains the version-controlled PostgreSQL schema and database code for ASPEN.

## Platform

- PostgreSQL 15
- Database: `vsr`
- OpenShift namespace: `aspen`
- PostgreSQL workload: `vsr-postgresql`
- PostgreSQL service port: `5432`
- PostgreSQL GitOps path: `gitops/postgres`
- Argo CD application: `aspen-postgres-npe`

PostgreSQL infrastructure is managed through Argo CD.

Database credentials and Kubernetes Secret values are not stored in Git.

## Directory Structure

- `baseline/` - Complete schema baseline
- `functions/` - PostgreSQL functions
- `procedures/` - PostgreSQL procedures
- `migrations/` - Future database migrations
- `README.md` - Database deployment documentation

## Schema Baseline

`baseline/vsr_schema.sql` represents the ASPEN PostgreSQL schema at the point the database was brought under source control.

The baseline was generated using `pg_dump --schema-only`.

No production application data is included.

The baseline was successfully restored into a clean PostgreSQL test database and validated with:

- 34 tables
- 25 functions
- 12 procedures

The baseline is intended for database reconstruction, disaster recovery preparation, development/test database creation, and schema comparison.

Normal database changes should use migrations rather than modifying the baseline.

## Functions

Individual PostgreSQL functions are maintained under:

`database/functions/`

Example:

`uf_autoeoxreplacedailylist.sql`

Functions should be maintained in Git so changes can be reviewed, tested, and reproduced.

## Procedures

Individual PostgreSQL stored procedures are maintained under:

`database/procedures/`

Example:

`sp_automaticdailytaskpopulator.sql`

## Migrations

Future database changes must be stored under:

`database/migrations/`

Examples:

- `001_add_activity_index.sql`
- `002_update_daily_task_generation.sql`
- `003_add_audit_column.sql`

A migration already deployed to an environment should not normally be modified.

Create a new migration for subsequent changes.

## Database Change Process

The standard database deployment flow is:

Git -> Migration -> Test PostgreSQL -> ASPEN PostgreSQL -> Validation

Database schema, function, and procedure changes should originate from Git whenever possible.

If an emergency database change is made directly in PostgreSQL, the corresponding SQL must be added to Git immediately afterward.

## Production Data

Production application data must not be committed to Git.

This includes:

- Activities
- Events
- Archived activities and events
- Application users
- Password hashes
- Audit records
- Runtime job information
- Operational notes

Schema definitions containing columns such as `password_hash` are safe to store in Git. Actual password-hash values are not.

## Reference Data

Some ASPEN tables contain configuration or reference data rather than operational history.

Examples include:

- `dailytasks`
- `environment`
- `environment_sub`
- `environment_ops`
- `environment_pc`
- `statutoryholidays`
- `event_templates`
- `templatedactivities`

Reference data should be managed through reviewed migrations or controlled seed scripts.

Do not automatically export production table data into Git.

## Secrets

Never commit:

- PostgreSQL passwords
- Database connection strings containing credentials
- `VSR_DATABASE_URL`
- `VSR_SESSION_SECRET`
- Kubernetes Secret values
- Quay credentials
- GitHub tokens

The PostgreSQL Deployment references the existing OpenShift Secret `vsr-postgresql`.

The Secret provides:

- `database-user`
- `database-password`
- `database-name`

Only Secret references are stored in Git.

## PostgreSQL Infrastructure

OpenShift PostgreSQL infrastructure is maintained under:

`gitops/postgres/`

It is managed by the Argo CD application:

`aspen-postgres-npe`

The existing PostgreSQL PVC contains ASPEN database data and must not be deleted or recreated during normal deployments.

## Source of Truth

For database schema and database code:

**Git is the source of truth.**

For production application data:

**PostgreSQL is the source of truth.**

For database credentials:

**OpenShift or the approved secret-management mechanism is the source of truth.**
