# Keycloak custom image and `app` realm (ADR-0010, ADR-0011)

| Path | Purpose |
|---|---|
| `Dockerfile` | `quay.io/keycloak/keycloak:26.7.3` (digest-pinned) + Apple identity-provider extension (`ADD --checksum`), `kc.sh build --db=postgres --http-relative-path=/auth --health-enabled=true --metrics-enabled=true --vault=file`; realm JSON and password blocklist baked in; runs as uid 1000 |
| `checksums.txt` | Version, URL, sha256 and upstream sha512 of every third-party artifact; `scripts/verify-checksums.sh` re-verifies against upstream and the Dockerfile (CI) |
| `realms/app-realm.json` | Realm `app` (no secrets): registration on, brute force on, password policy, token lifetimes, roles `user`/`admin`, clients `web-bff` (confidential + PKCE S256 + `aud: api` mapper) and `api` (bearer-only), IdPs `google` (enabled) and `apple` (disabled) |
| `realms/app-realm.ci.json` | Partial-import overlay used only by `scripts/smoke.sh` (direct-grant client `ci-smoke`) |
| `scripts/docker-entrypoint.sh` | Reads `KC_DB_PASSWORD_FILE`, `KC_BOOTSTRAP_ADMIN_PASSWORD_FILE`, `WEB_BFF_CLIENT_SECRET_FILE` into env, then `exec kc.sh` |
| `scripts/smoke.sh` | Upgrade gate (ADR-0010 §6): discovery/JWKS, realm settings, Apple factory loaded, IdP config, client config, real login, refresh rotation, password policy, brute force |
| `password-blacklists/blocklist.txt` | Referenced by `passwordBlacklist(blocklist.txt)` in the password policy |

## Runtime configuration

Environment (set by Compose; none of these are secrets): `KC_DB_URL`, `KC_DB_USERNAME`, `KC_HOSTNAME` (`https://test-vinayak.duckdns.org/auth` in the POC, `http://localhost:8080/auth` locally), `KC_BOOTSTRAP_ADMIN_USERNAME`, `GOOGLE_CLIENT_ID`, `KC_HOSTNAME_STRICT=false` only for local/test.

Secrets (files under `/run/secrets`):

| File | Consumed by |
|---|---|
| `keycloak_db_password` | `KC_DB_PASSWORD_FILE` (entrypoint) |
| `keycloak_admin_password` | `KC_BOOTSTRAP_ADMIN_PASSWORD_FILE` (entrypoint; only on first start) |
| `web_bff_client_secret` | `WEB_BFF_CLIENT_SECRET_FILE` → `${WEB_BFF_CLIENT_SECRET}` in the realm JSON at import |
| `app_google_client_secret` | Keycloak file vault (`${vault.google_client_secret}`; the file name is `<realm>_<key>`) |

Placeholders `${ENV_VAR}` in the realm JSON are substituted **only at first import**; `${vault.*}` references are resolved on every use, so rotating the Google secret is a file change plus restart. Rotating the `web-bff` secret after the first import is done in the admin console (or the admin API) and in the frontend secret at the same time.

The container needs writable `tmpfs` at `/tmp`, `/opt/keycloak/data/tmp` and `/opt/keycloak/data/transaction-logs` when run with `read_only: true`.

## Realm export / import runbook

**Import** happens automatically on first start (`start --optimized --import-realm`); an existing realm is left untouched (`IGNORE_EXISTING`). To re-import after editing the JSON on a dev machine: `make test-db-down` (drops the volume) and start again.

**Export after changes made in the admin console** (over WireGuard on VPS-B, or locally):

```bash
docker compose exec -u 1000 keycloak /opt/keycloak/bin/kc.sh export --dir /tmp/export --realm app --users skip
docker compose cp keycloak:/tmp/export/app-realm.json /tmp/app-realm.export.json
```

Then merge into `realms/app-realm.json` **removing every secret and generated id** (`secret`, `clientSecret` values, `id`, `containerId`, `authenticationFlows` ids, `keycloakVersion`) and keeping the `${...}` placeholders. Run `scripts/smoke.sh` against a fresh test stack before merging (the import must still succeed from an empty database).

## Testing

```bash
make keycloak-image      # build web-app-test/keycloak:dev
make keycloak-smoke      # compose --profile keycloak up, run smoke.sh (~1 min), leave it running
make test-db-down        # stop and delete volumes
```
