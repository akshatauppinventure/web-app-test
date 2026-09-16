#!/usr/bin/env bash
# Restore drill (ADR-0021 §7): restore the latest app + keycloak dumps into a scratch Postgres,
# compare row counts with production, and print a log line for docs/runbooks/restore-drill-log.md.
set -euo pipefail
SECRETS=/etc/app/secrets
export RESTIC_REPOSITORY_FILE="$SECRETS/restic_repository"
export RESTIC_PASSWORD_FILE="$SECRETS/restic_password"
AWS_ACCESS_KEY_ID="$(tr -d '\n' < "$SECRETS/restic_s3_access_key")"
AWS_SECRET_ACCESS_KEY="$(tr -d '\n' < "$SECRETS/restic_s3_secret_key")"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
PG_IMAGE="${PG_IMAGE:-postgres:18.6-trixie@sha256:4ef4dbc939d61acea57712655ddb4b4ab27419c913f94cca0cd57cb3ea3c2280}"
PROD_CONTAINER="${PG_CONTAINER:-core-postgres-1}"
SCRATCH="restore-drill-$$"
start="$(date +%s)"
work="$(mktemp -d)"; trap 'rm -rf "$work"; docker rm -f "$SCRATCH" >/dev/null 2>&1 || true' EXIT

snap="$(restic snapshots --tag pg:app --latest 1 --json | jq -r '.[0].short_id')"
[[ -n "$snap" && "$snap" != "null" ]] || { echo "no app snapshot"; exit 1; }
restic dump --tag pg:app latest pg_dump-app.custom > "$work/app.custom"
restic dump --tag pg:keycloak latest pg_dump-keycloak.custom > "$work/keycloak.custom"
restic dump --tag pg:globals latest pg_globals.sql > "$work/globals.sql"

docker run -d --rm --name "$SCRATCH" -e POSTGRES_PASSWORD=drill -v "$work:/restore:ro" "$PG_IMAGE" >/dev/null
for _ in $(seq 1 30); do docker exec "$SCRATCH" pg_isready -U postgres >/dev/null 2>&1 && break; sleep 2; done
docker exec "$SCRATCH" psql -U postgres -q -f /restore/globals.sql >/dev/null 2>&1 || true
for db in app keycloak; do
  docker exec "$SCRATCH" createdb -U postgres "$db"
  docker exec "$SCRATCH" pg_restore -U postgres -d "$db" --no-owner --role=postgres "/restore/$db.custom" >/dev/null 2>&1 || true
done
prod_visits="$(docker exec -u postgres "$PROD_CONTAINER" psql -U postgres -d app -Atc 'SELECT count(*) FROM visits')"
drill_visits="$(docker exec "$SCRATCH" psql -U postgres -d app -Atc 'SELECT count(*) FROM visits')"
drill_users="$(docker exec "$SCRATCH" psql -U postgres -d keycloak -Atc 'SELECT count(*) FROM user_entity')"
dur=$(( $(date +%s) - start ))
echo "| $(date -u +%F) | $snap | visits prod=$prod_visits restored=$drill_visits | keycloak users=$drill_users | ${dur}s | $( [[ "$prod_visits" == "$drill_visits" ]] && echo OK || echo "MISMATCH (backup is from last night)") |"
