# Traefik image and configuration (ADR-0012, ADR-0013)

| Path | Purpose |
|---|---|
| `Dockerfile` | `traefik:v3.7.13` (digest-pinned) + CrowdSec bouncer plugin extracted from a checksum-verified source tarball into `/plugins-local/src/<module>/`; runs as uid 65532; listeners on 8080/8443 (published as 80/443) |
| `plugins.lock` | module, version, URL, sha256 of every local plugin; `scripts/fetch-plugins.sh` re-verifies against upstream and the Dockerfile (CI) |
| `traefik.yml` | Static config: entry points `web` (→ 301 to `https://host`), `websecure` (TLS via ACME resolver `le`, HTTP/2), `ping` (never published); file provider only; JSON access log with request headers dropped except User-Agent/Referer/Content-Type/X-Forwarded-For; no API/dashboard; `experimental.localPlugins`; header/path hygiene (`aliasHeadersStrategy: reject`, encoded `/ \ ? NUL` rejected) |
| `dynamic/tls.yml` | TLS 1.2+, `sniStrict`, modern cipher suites |
| `dynamic/middlewares.yml` | `secure-headers`, `ratelimit-app` (50/s, burst 100), `ratelimit-auth` (10/s, burst 20), `inflight` (100/IP), `body-limit` (1 MiB), `body-limit-auth` (256 KiB), `compress`, `crowdsec` (stream mode, AppSec on, **fail-open**), `not-found` (418 from `noop@internal` → 404 page from the frontend) |
| `dynamic/routes.yml` | Routers `keycloak-public` (only `/auth/realms/*`, `/auth/resources/*`), `keycloak-block` (rest of `/auth` → 404), `frontend`, `catch-all` (unknown Host → 404); upstreams from `FRONTEND_UPSTREAM` / `KEYCLOAK_UPSTREAM` |
| `scripts/docker-entrypoint.sh` | Renders `ACME_EMAIL`, `ACME_CA_SERVER`, `LOG_LEVEL` into the static config (a static file cannot read env vars) |

## Runtime environment

| Variable | Test | POC (T16) |
|---|---|---|
| `PUBLIC_HOST` | `test-vinayak.duckdns.org` | `test-vinayak.duckdns.org` |
| `FRONTEND_UPSTREAM` | `http://frontend:80` (whoami stub) | `http://frontend:3000` (edge network) |
| `KEYCLOAK_UPSTREAM` | `http://keycloak:80` (whoami stub) | `http://10.10.0.2:8080` (WireGuard) |
| `ACME_EMAIL` / `ACME_CA_SERVER` | unreachable CA | owner email / staging then production |

Secrets: `/run/secrets/crowdsec_bouncer_key` (bouncer API key, T15). Volumes: `/letsencrypt` (acme.json, mode 0600, owned by 65532), `/var/log/traefik` (shared read-only with CrowdSec). `/tmp` must be a tmpfs (rendered config).

Unknown SNI or no SNI is refused at the TLS layer (`sniStrict`), so scanners hitting the IP get nothing; a known SNI with a foreign `Host` header gets 404.

## Testing

```bash
make traefik-test      # self-signed test cert, compose.traefik-test.yaml (whoami upstreams), scripts/test/traefik-routes.sh
make traefik-verify-plugins
docker compose -f compose.traefik-test.yaml down -v
```
