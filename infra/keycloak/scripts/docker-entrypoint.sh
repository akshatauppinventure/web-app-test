#!/bin/bash
# Reads *_FILE secrets into the environment variables Keycloak expects, then execs kc.sh.
# Keycloak itself has no *_FILE convention for these; the file vault (KC_VAULT=file) covers
# only ${vault.*} placeholders inside realm configuration.
set -euo pipefail

for var in KC_DB_PASSWORD KC_BOOTSTRAP_ADMIN_PASSWORD WEB_BFF_CLIENT_SECRET; do
  file_var="${var}_FILE"
  file="${!file_var:-}"
  if [[ -n "$file" ]]; then
    if [[ ! -r "$file" ]]; then
      echo "entrypoint: $file_var=$file is not readable" >&2
      exit 1
    fi
    value="$(tr -d '\r\n' < "$file")"
    export "$var=$value"
    unset "$file_var"
  fi
done

exec /opt/keycloak/bin/kc.sh "$@"
