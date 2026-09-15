# ADR-0021: Backups and restore

- **Status:** Accepted (2026-09-15)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0002, ADR-0005, ADR-0006, ADR-0009, ADR-0016

## Context

PostgreSQL on VPS-B holds all application and identity data in a Docker volume on one disk. The POC needs reliable, encrypted, off-host backups and a *tested* restore, without the complexity of point-in-time recovery (PITR) tooling.

Research (2026):
- **WAL-G** and **pgBackRest** are the leading PITR tools. pgBackRest had a maintenance scare in April 2026 and now has multiple sponsors.
- **restic** is a mature, FOSS, encrypted, deduplicating backup tool with S3 support.
- UpCloud Managed Object Storage **US-1** is located in Chicago, reachable from NYC1.

## Decision

1. **What is backed up** (nightly, 02:30 America/New_York, on VPS-B):
   - `pg_dump --format=custom` of the **`app`** and **`keycloak`** databases, streamed from `docker exec` into `restic backup --stdin`.
   - `pg_dumpall --globals-only` (roles; password hashes included).
   - Portainer data volume (tar stream).
   - **Not backed up:** Traefik `acme.json` (reissued automatically), container images (rebuildable from GHCR/git), secrets (in git via SOPS, ADR-0016).
2. **Where:**
   - A **restic repository** in a dedicated bucket on **UpCloud Managed Object Storage US-1 (Chicago)**: a different data center from the servers.
   - Access key scoped to that bucket only.
   - **Bucket versioning / object lock enabled if supported** by the service. If not, a second copy at another provider becomes an earlier production follow-up.
3. **Encryption:**
   - restic client-side encryption (AES-256 + Poly1305).
   - Repository password and object-storage keys stored as `core` secrets (ADR-0016), plus a **copy in the admin password manager**. Without it, backups are unrecoverable.
4. **Scheduling and runtime:**
   - **Host systemd timer + service** (not a container), running as a dedicated backup user with only the permissions needed for `docker exec` on the postgres container.
   - The timer logs to journald. A non-zero exit is surfaced in health checks (ADR-0024).
5. **Retention:** `restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 3 --prune` after each backup. `restic check` weekly; `restic check --read-data-subset=10%` monthly.
6. **Targets (POC):** **RPO ≤ 24 hours; RTO ≤ 4 hours.**
7. **Restore drills:**
   - **During POC verification**, then **monthly**:
     1. Restore the latest snapshot into a scratch `postgres:18.6` container.
     2. Run `pg_restore`.
     3. Compare row counts and run the app's smoke query.
     4. Log the result in `docs/runbooks/restore-drill-log.md`.
   - A backup that has never been restored is not considered a backup.

## Alternatives considered

| Option | Why not chosen |
|---|---|
| WAL-G / pgBackRest (PITR) now | Continuous WAL archiving and more moving parts; the POC tolerates 24 h RPO. **Planned for production.** |
| Provider server snapshots only | Crash-consistent at best, same provider/account, weak for DB consistency; useful as an *extra* layer only |
| BorgBackup / Kopia | Viable; restic has native S3 support and a very large user base |
| Backups on VPS-A | Would put backup credentials on the edge host (ADR-0003) |

## Consequences

**Positive**
- Encrypted, off-host, versioned backups with tested restores; simple to understand and audit.

**Negative / risks**
- Up to 24 hours of data loss.
- Same-provider object storage doesn't protect against losing the UpCloud account.
- Logical dumps take longer to restore as data grows.

**Follow-ups**
- Production ADR: PITR (WAL-G or pgBackRest), cross-provider copy, immutable storage, stricter RPO/RTO.

## References

- https://restic.readthedocs.io/
- https://www.postgresql.org/docs/18/app-pgdump.html
- https://upcloud.com/docs/products/managed-object-storage/availability/
- https://www.bytebase.com/blog/top-open-source-postgres-backup-solution/
