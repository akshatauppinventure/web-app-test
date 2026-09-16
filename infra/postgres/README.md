# PostgreSQL 18 configuration (ADR-0009)

| File | Purpose |
|---|---|
| `Dockerfile` | `postgres:18.6-trixie` (digest-pinned) with the files below baked in; runs as uid 999 from the start, so the stack needs no capabilities (`cap_drop: [ALL]`, `read_only`, tmpfs for `/tmp` and `/var/run/postgresql`) |
| `initdb/01-roles.sh` | First-init only: roles `app_owner` (NOLOGIN), `app_migrator` (member of `app_owner`), `app_rw` (runtime, `NOBYPASSRLS`, `NOINHERIT`), `keycloak`; databases `app` and `keycloak`; `REVOKE` on PUBLIC; default privileges so `app_rw` gets DML on tables created by `app_owner` |
| `initdb/02-hardening.sql` | Per-role `statement_timeout`, `idle_in_transaction_session_timeout`, `lock_timeout`, `search_path`; logs every statement of the superuser |
| `postgresql.conf` | Loaded with `-c config_file=`; scram-sha-256, connection/DDL logging to stderr, conservative memory, UTC |
| `pg_hba.conf` | `peer` on the local socket (postgres OS user only), `scram-sha-256` from `172.28.1.0/24` (the `db` network), reject everything else |

Passwords are read from `*_PASSWORD_FILE` environment variables (Compose secrets). The scripts run once, when the data volume is empty; changing them later requires a reset (`down -v`) or a manual migration.

## Conventions

- The `db` Docker network must use subnet `172.28.1.0/24` (matches `pg_hba.conf`) in every compose file.
- Admin access: `docker compose exec -u postgres postgres psql -U postgres` (peer auth; `exec` as root is rejected).
- Migrations connect as `app_migrator` and `SET ROLE app_owner`, so tables are owned by `app_owner`; `app_rw` can never disable or bypass RLS.
- Every table with user data: `ENABLE` + `FORCE ROW LEVEL SECURITY` with policies on `current_setting('app.user_id', true)`.

The image is what every compose file uses (`build: ./infra/postgres` locally, `ghcr.io/akshatauppinventure/postgres@sha256:…` in the `core` stack). Changing a file here means a new image; the initdb scripts still run only on an empty data volume.

## Testing

```bash
docker compose -f compose.test.yaml up -d --wait   # Postgres on 127.0.0.1:55432
make backend-check                                 # includes tests/test_rls.py
docker compose -f compose.test.yaml down -v
```
