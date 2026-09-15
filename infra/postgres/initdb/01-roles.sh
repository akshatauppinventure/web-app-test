#!/usr/bin/env bash
# Creates least-privilege roles and the two databases on first initialisation (ADR-0009 §3).
# Runs once, as the postgres superuser, from the official image's entrypoint.
# Passwords come from *_PASSWORD_FILE env vars pointing at Docker/Compose secrets.
set -euo pipefail

read_secret() {
  local var="$1" file="${!1:-}"
  if [[ -z "$file" || ! -r "$file" ]]; then
    echo "initdb: $var must point to a readable secret file" >&2
    exit 1
  fi
  tr -d '\r\n' < "$file"
}

APP_MIGRATOR_PASSWORD="$(read_secret APP_MIGRATOR_PASSWORD_FILE)"
APP_RW_PASSWORD="$(read_secret APP_RW_PASSWORD_FILE)"
KEYCLOAK_PASSWORD="$(read_secret KEYCLOAK_PASSWORD_FILE)"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
  -v migrator_pw="$APP_MIGRATOR_PASSWORD" -v rw_pw="$APP_RW_PASSWORD" -v kc_pw="$KEYCLOAK_PASSWORD" <<'SQL'
-- Roles
CREATE ROLE app_owner NOLOGIN NOINHERIT;
CREATE ROLE app_migrator LOGIN PASSWORD :'migrator_pw' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS IN ROLE app_owner;
CREATE ROLE app_rw LOGIN PASSWORD :'rw_pw' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS NOINHERIT;
CREATE ROLE keycloak LOGIN PASSWORD :'kc_pw' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;

-- Databases
CREATE DATABASE app OWNER app_owner;
CREATE DATABASE keycloak OWNER keycloak;

REVOKE ALL ON DATABASE app FROM PUBLIC;
REVOKE ALL ON DATABASE keycloak FROM PUBLIC;
REVOKE ALL ON DATABASE postgres FROM PUBLIC;
GRANT CONNECT ON DATABASE app TO app_migrator, app_rw;
GRANT CONNECT ON DATABASE keycloak TO keycloak;
SQL

# Schema privileges inside `app`: app_owner owns public; app_rw gets DML on future tables.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname app <<'SQL'
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
ALTER SCHEMA public OWNER TO app_owner;
GRANT USAGE, CREATE ON SCHEMA public TO app_owner;
GRANT USAGE ON SCHEMA public TO app_rw;
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_rw;
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO app_rw;
SQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname keycloak <<'SQL'
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
ALTER SCHEMA public OWNER TO keycloak;
SQL

echo "initdb: roles app_owner, app_migrator, app_rw, keycloak and databases app, keycloak created"
