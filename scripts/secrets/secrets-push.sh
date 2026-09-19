#!/usr/bin/env bash
# Decrypts infra/secrets/<host>.sops.yaml locally and writes each value to the host over SSH as
# /etc/app/secrets/<name> (0400, owned by the consuming UID). Values never appear in argv or logs.
# The default SSH targets are the host aliases webapptest-edge / webapptest-core from ~/.ssh/config
# (docs/runbooks/provisioning.md). Usage: secrets-push.sh <edge|core> [--dry-run] [--ssh-target user@host]
set -euo pipefail
HOST="${1:?edge|core}"; shift
DRY=0; TARGET=""
while (( $# )); do case "$1" in --dry-run) DRY=1;; --ssh-target) TARGET="$2"; shift;; *) echo "unknown arg $1" >&2; exit 2;; esac; shift; done
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FILE="${SECRETS_FILE:-$ROOT/infra/secrets/$HOST.sops.yaml}"
SOPS=(sops); [[ -n "${SOPS_CONFIG:-}" ]] && SOPS=(sops --config "$SOPS_CONFIG")
case "$HOST" in edge) TARGET="${TARGET:-webapptest-edge}";; core) TARGET="${TARGET:-webapptest-core}";; *) echo "unknown host" >&2; exit 2;; esac

# name -> "path owner mode" (owner = UID of the consuming container; see infra/secrets/SCHEMA.md)
dest() {
  case "$1" in
    crowdsec_bouncer_key) echo "/etc/app/secrets/$1 0 0444" ;;        # read by traefik (65532) and crowdsec (0)
    crowdsec_enroll_key|portainer_agent_secret|portainer_admin_password) echo "/etc/app/secrets/$1 0 0400" ;;
    auth_secret) echo "/etc/app/secrets/$1 1000 0400" ;;
    web_bff_client_secret) [[ "$HOST" == edge ]] && echo "/etc/app/secrets/$1 1000 0400" || echo "/etc/app/secrets/$1 1000 0400" ;;
    postgres_password|app_migrator_password|app_rw_password) echo "/etc/app/secrets/$1 999 0400" ;;
    keycloak_db_password) echo "/etc/app/secrets/$1 1000 0444" ;;      # postgres init (999) and keycloak (1000)
    keycloak_admin_password|app_google_client_secret) echo "/etc/app/secrets/$1 1000 0400" ;;
    database_url|migrate_database_url) echo "/etc/app/secrets/$1 10001 0400" ;;
    restic_*) echo "/etc/app/secrets/$1 0 0400" ;;
    *) echo "" ;;
  esac
}

if (( DRY )); then
  echo "dry run: would push $HOST secrets to $TARGET"
  names="$("${SOPS[@]}" -d --output-type json "$FILE" 2>/dev/null | jq -r 'keys[]' || grep -oE '^[a-z0-9_-]+' "$FILE")"
else
  names="$("${SOPS[@]}" -d --output-type json "$FILE" | jq -r 'keys[]')"
fi
status=0
while read -r name; do
  [[ -z "$name" || "$name" == sops ]] && continue
  spec="$(dest "$name")"
  if [[ -z "$spec" ]]; then echo "FAIL: no destination rule for secret '$name' (add it to secrets-push.sh and SCHEMA.md)"; status=1; continue; fi
  read -r path owner mode <<<"$spec"
  if (( DRY )); then echo "  $name -> $path (owner $owner, mode $mode)"; continue; fi
  "${SOPS[@]}" -d --extract "[\"$name\"]" "$FILE" | tr -d '\n' \
    | ssh -o BatchMode=yes "$TARGET" "sudo install -d -m 0700 -o root -g root \$(dirname '$path') && umask 077 && sudo tee '$path' >/dev/null && sudo chown '$owner':0 '$path' && sudo chmod '$mode' '$path'"
  echo "  pushed $name -> $path"
done <<<"$names"
(( DRY )) || ssh -o BatchMode=yes "$TARGET" "sudo ls -l /etc/app/secrets 2>/dev/null | sed 's/^/    /'"
exit $status
