#!/usr/bin/env bash
# Weekly repository check; monthly 10% data read (ADR-0021 §5). Usage: restic-check.sh [--read-data]
set -euo pipefail
SECRETS=/etc/app/secrets
export RESTIC_REPOSITORY_FILE="$SECRETS/restic_repository"
export RESTIC_PASSWORD_FILE="$SECRETS/restic_password"
AWS_ACCESS_KEY_ID="$(tr -d '\n' < "$SECRETS/restic_s3_access_key")"
AWS_SECRET_ACCESS_KEY="$(tr -d '\n' < "$SECRETS/restic_s3_secret_key")"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
if [[ "${1:-}" == "--read-data" ]]; then
  restic check --read-data-subset=10% --quiet
else
  restic check --quiet
fi
logger -t restic-check -p daemon.info "restic check ok (${1:-metadata})"
