# ADR-0009: Database: PostgreSQL 18

- **Status:** Accepted (2026-09-15); WireGuard references superseded by [ADR-0026](0026-remove-wireguard-public-ssh-private-network.md)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0003, ADR-0005, ADR-0010, ADR-0011, ADR-0021

## Context

The owner requires PostgreSQL. It stores application data and Keycloak's data (users, sessions, realm signing keys), so it's the most sensitive component.

Versions as of 2026-09-14:
- **PostgreSQL 18.6** (2026-08-13) is the latest stable.
- **PostgreSQL 19** is in beta; release is expected Sept/Oct 2026.

The official Docker image for PG18+ **changed its data directory layout**:
- `PGDATA` is now `/var/lib/postgresql/18/docker`.
- Volumes must be mounted at `/var/lib/postgresql`, not `/var/lib/postgresql/data`.

This enables faster `pg_upgrade --link` major upgrades.

Whether to run Postgres in Docker is debated. It's widely done and adequate for single-host, low-connection workloads; a native install gives more tuning and backup-tool flexibility.

## Decision

1. **Version and image:** **PostgreSQL 18** via **`postgres:18.6-trixie`** (pinned by digest). Apply minor releases within the security SLA (ADR-0020). **Don't adopt PostgreSQL 19 before 19.1** and a separate upgrade ADR.
2. **Placement:**
   - Runs on **VPS-B only**, attached to an `internal: true` Docker network (`db`) shared only with Keycloak, FastAPI and the migration job.
   - **Never publishes a port.** Admin access is via `docker exec` over SSH on WireGuard.
   - Storage: named volume `pgdata` mounted at `/var/lib/postgresql`. Never set `PGDATA` to the old path.
3. **Databases and roles (least privilege):**

   | Role | Purpose | Privileges |
   |---|---|---|
   | `postgres` (superuser) | Bootstrap and emergency use only | Password from secret file; not used by any app |
   | `app_owner` | Owns app schema objects | `NOLOGIN`; objects created via `app_migrator` |
   | `app_migrator` | Runs Alembic migrations | Member of `app_owner`; used only by the one-shot `migrate` job |
   | `app_rw` | Runtime role for FastAPI | `LOGIN`, **not owner, `NOBYPASSRLS`**, `SELECT/INSERT/UPDATE/DELETE` on app tables only, `USAGE` on sequences |
   | `keycloak` | Keycloak runtime | Owns the separate `keycloak` database only; no access to `app` |

   - Two databases: `app` and `keycloak`. `REVOKE ALL ON DATABASE ... FROM PUBLIC`; `REVOKE CREATE ON SCHEMA public FROM PUBLIC`.
4. **Security settings:**
   - `password_encryption = scram-sha-256`.
   - `pg_hba.conf` allows only `scram-sha-256` from the `db` network subnet. `trust` isn't used, except the image's local socket during init, which is then removed.
   - `log_connections = on`, `log_disconnections = on`.
   - `statement_timeout` and `idle_in_transaction_session_timeout` set for `app_rw`.
   - Secrets via `POSTGRES_PASSWORD_FILE` and role passwords from secret files (ADR-0016).
   - **Row-Level Security** is enabled and **forced** (`ALTER TABLE ... FORCE ROW LEVEL SECURITY`) on every table that holds user-owned data (ADR-0011).
   - TLS is not needed inside B's internal Docker network. **Production 3-tier: TLS (`hostssl`, `verify-full`) is required** because traffic crosses hosts.
5. **Connection pooling:** none for the POC (SQLAlchemy pool sizes set conservatively). PgBouncer is revisited for production.

## Alternatives considered

| Option | Why not chosen |
|---|---|
| PostgreSQL 19.0 at launch | Too new for a POC; wait for 19.1+ |
| PostgreSQL 17 | Older; 18 brings async I/O and other improvements, and the image layout supports easier upgrades |
| Native (apt/PGDG) Postgres on VPS-B | Better for production tuning and PITR tooling; Docker chosen for POC consistency and Portainer visibility. **Reconsider for production.** |
| Managed PostgreSQL (UpCloud) | Provider lock-in (ADR-0002); higher cost |
| Separate Postgres instances for app and Keycloak | More RAM and operational work for little POC benefit; separation by database + role is sufficient now |

## Consequences

**Positive**
- The database is unreachable from the internet and from VPS-A. Least-privilege roles and forced RLS limit the damage from app bugs.

**Negative / risks**
- App and Keycloak share one instance: a resource spike or instance failure affects both.
- A Docker volume on a single disk: data durability relies on backups (ADR-0021) and provider storage redundancy.

**Follow-ups**
- Production ADRs: native vs container, point-in-time recovery (WAL-G/pgBackRest), PgBouncer, TLS across hosts, PG19 upgrade.

## References

- https://www.postgresql.org/docs/release/
- https://github.com/docker-library/postgres/pull/1259
- https://hub.docker.com/_/postgres/
- https://www.postgresql.org/docs/18/ddl-rowsecurity.html
- https://sliplane.io/blog/best-practices-for-postgres-in-docker
