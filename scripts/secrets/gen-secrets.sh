#!/usr/bin/env bash
# Generates a plaintext secrets YAML for one host with strong random values for every generated
# secret and CHANGE_ME markers for owner-supplied ones (see infra/secrets/SCHEMA.md).
# Values shared between hosts (web_bff_client_secret, portainer_agent_secret) are
# read from --shared-from <other-host-plaintext> when given, so both files stay consistent.
# Usage: gen-secrets.sh <edge|core> <out.yaml> [--shared-from other.yaml]
# The output is plaintext: write it to a tmpfs/temp dir and encrypt immediately (make secrets-encrypt).
set -euo pipefail
HOST="${1:?edge|core}"; OUT="${2:?output file}"; SHARED="${4:-}"
[[ "${3:-}" == "--shared-from" || -z "${3:-}" ]] || { echo "usage: $0 <edge|core> <out.yaml> [--shared-from other.yaml]" >&2; exit 2; }
rand() { openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | head -c "${1:-32}"; }
hexrand() { openssl rand -hex "${1:-32}"; }
shared() {  # shared <key> <generator>
  local key="$1" gen="$2" v=""
  if [[ -n "$SHARED" && -r "$SHARED" ]]; then v="$(awk -v k="$key" '$1==k":"{print $2}' "$SHARED" | tr -d '"')"; fi
  if [[ -n "$v" ]]; then printf '%s' "$v"; else eval "$gen"; fi
}
umask 077
case "$HOST" in
  edge)
    cat > "$OUT" <<YAML
# edge secrets (plaintext — encrypt with sops before committing; see docs/runbooks/secrets.md)
crowdsec_bouncer_key: "$(hexrand 32)"
crowdsec_enroll_key: "CHANGE_ME_or_unset"
auth_secret: "$(rand 48)"
web_bff_client_secret: "$(shared web_bff_client_secret 'rand 48')"
portainer_agent_secret: "$(shared portainer_agent_secret 'rand 48')"
YAML
    ;;
  core)
    pg_migrator="$(rand 40)"; pg_rw="$(rand 40)"
    cat > "$OUT" <<YAML
# core secrets (plaintext — encrypt with sops before committing; see docs/runbooks/secrets.md)
postgres_password: "$(rand 40)"
app_migrator_password: "$pg_migrator"
app_rw_password: "$pg_rw"
keycloak_db_password: "$(rand 40)"
keycloak_admin_password: "$(rand 32)"
web_bff_client_secret: "$(shared web_bff_client_secret 'rand 48')"
app_google_client_secret: "CHANGE_ME_google_poc_client_secret"
database_url: "postgresql+psycopg://app_rw:${pg_rw}@postgres:5432/app"
migrate_database_url: "postgresql+psycopg://app_migrator:${pg_migrator}@postgres:5432/app"
portainer_agent_secret: "$(shared portainer_agent_secret 'rand 48')"
portainer_admin_password: "$(rand 32)"
restic_repository: "CHANGE_ME_s3:https://<endpoint>/<bucket>"
restic_password: "$(rand 48)"
restic_s3_access_key: "CHANGE_ME"
restic_s3_secret_key: "CHANGE_ME"
YAML
    ;;
  *) echo "unknown host $HOST" >&2; exit 2 ;;
esac
echo "wrote plaintext $HOST secrets to $OUT ($(grep -c CHANGE_ME "$OUT") value(s) need the owner)"
