---
name: ciallo-migrate
description: Use when generating SQL schema diffs, applying migrations, detecting checksum drift, or running idempotent seeds with unmbt/ciallo-migrate.
---

# unmbt/ciallo-migrate

## Rules
- Never modify an already-applied migration script; `verify_migrations` raises `MigrateError::ChecksumDrift` on SHA-256 mismatch.
- Use `diff_schemas` to produce deterministic `up.sql` and `down.sql` for Postgres or SQLite/D1.
- Use `run_seeds` for idempotent seed scripts tracked in `_ciallo_seeds`.
