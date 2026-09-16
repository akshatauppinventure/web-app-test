#!/usr/bin/env bash
# Generates local development secrets into .dev-secrets/ (gitignored) for compose.dev.yaml.
# Existing files are kept unless --force is given. Nothing secret is printed.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/../.." && pwd)/.dev-secrets"
FORCE="${1:-}"
mkdir -p "$DIR"
chmod 700 "$DIR"

rand() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "${1:-32}"; }

put() {  # put <name> <value>
  local f="$DIR/$1"
  if [[ -e "$f" && "$FORCE" != "--force" ]]; then echo "keep   $1"; return; fi
  umask 077
  printf '%s' "$2" > "$f"
  echo "write  $1"
}

put postgres_password "$(rand 40)"
put app_migrator_password "$(rand 40)"
put app_rw_password "$(rand 40)"
put keycloak_db_password "$(rand 40)"
put keycloak_admin_password "$(rand 32)"
put web_bff_client_secret "$(rand 48)"
put auth_secret "$(rand 48)"
put dev_user_password "$(rand 24)"
# Google OAuth client secret for the *local* client (owner prerequisite P2). Placeholder until set.
[[ -e "$DIR/app_google_client_secret" ]] || put app_google_client_secret "unset-google-client-secret"

# Derived connection URLs (passwords are URL-safe alphanumerics, so no encoding is needed).
put database_url "postgresql+psycopg://app_rw:$(cat "$DIR/app_rw_password")@postgres:5432/app"
put migrate_database_url "postgresql+psycopg://app_migrator:$(cat "$DIR/app_migrator_password")@postgres:5432/app"

echo "dev secrets ready in $DIR"
