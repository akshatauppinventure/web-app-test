#!/usr/bin/env bash
# Nightly backup on VPS-B (ADR-0021): pg_dump of app + keycloak, roles, Portainer data -> restic.
# Runs as root from pg-backup.service; restic credentials come from /etc/app/secrets (never env files).
set -euo pipefail
SECRETS=/etc/app/secrets
export RESTIC_REPOSITORY_FILE="$SECRETS/restic_repository"
export RESTIC_PASSWORD_FILE="$SECRETS/restic_password"
AWS_ACCESS_KEY_ID="$(tr -d '\n' < "$SECRETS/restic_s3_access_key")"
AWS_SECRET_ACCESS_KEY="$(tr -d '\n' < "$SECRETS/restic_s3_secret_key")"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
PG_CONTAINER="${PG_CONTAINER:-core-postgres-1}"
PORTAINER_VOLUME="${PORTAINER_VOLUME:-portainer_portainer-data}"
STAMP_DIR=/var/lib/app
HOST_TAG="$(hostname)"
mkdir -p "$STAMP_DIR"

pg() { docker exec -i -u postgres "$PG_CONTAINER" "$@"; }

restic snapshots >/dev/null 2>&1 || restic init

for db in app keycloak; do
  pg pg_dump --format=custom --no-owner=false "$db" \
    | restic backup --stdin --stdin-filename "pg_dump-$db.custom" --tag "pg:$db" --tag "host:$HOST_TAG" --quiet
done
pg pg_dumpall --globals-only | restic backup --stdin --stdin-filename "pg_globals.sql" --tag "pg:globals" --tag "host:$HOST_TAG" --quiet
docker run --rm -v "$PORTAINER_VOLUME:/data:ro" busybox:stable tar -C /data -cf - . \
  | restic backup --stdin --stdin-filename "portainer-data.tar" --tag "portainer" --tag "host:$HOST_TAG" --quiet

restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 3 --prune --quiet
date -u +%FT%TZ > "$STAMP_DIR/last-backup-ok"
logger -t pg-backup -p daemon.info "backup completed"
