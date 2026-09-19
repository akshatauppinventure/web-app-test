# ADR-0012: Reverse proxy: Traefik with the file provider

- **Status:** Accepted (2026-09-15); access model superseded by [ADR-0026](0026-remove-wireguard-public-ssh-private-network.md)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0003, ADR-0010, ADR-0013, ADR-0014, ADR-0022, ADR-0023

## Context

We need an internet-facing reverse proxy that:
- handles TLS with automatic Let's Encrypt certificates,
- enforces security headers and rate limits,
- integrates with CrowdSec/WAF,
- routes to Next.js locally and to Keycloak on VPS-B.

The owner asked for the option that is most **globally adopted, popular and reliable**.

Comparison (2026-09-13/14):

| Criterion | Traefik | Caddy |
|---|---|---|
| Container adoption | 3.5 billion Docker Hub pulls, one of the top-15 official images, 1,000+ contributors (July 2026) | Lower container usage |
| GitHub stars | ~64k | ~75k |
| Development and support | 470 PRs merged in H1 2026; company-backed; v3.7 and v2.11 maintained in parallel | Active, single line (2.11.x) |
| WAF / intrusion prevention | CrowdSec bouncer plugin (with AppSec) and Coraza plugin, no custom build | Requires an xcaddy custom build |
| Keycloak docs | Official Traefik reverse-proxy blueprint (26.7) | — |
| 2025–26 CVEs | Forward-auth header spoofing (CVE-2026-54763/54764), path normalization (CVE-2025-66490) | `forward_auth` header injection (CVE-2026-30851), FastCGI path bug |
| Reliability | Mature; no material difference | Mature; no material difference |

- **Current version:** Traefik **v3.7.13** (2026-09-04).

## Decision

1. **Proxy:** **Traefik v3.7.x** on VPS-A, as a custom image `ghcr.io/<org>/traefik` built from `traefik:v3.7.13` (pinned by digest).
2. **No Docker socket.**
   - Use the **file provider only** (`providers.file.directory=/etc/traefik/dynamic`, `watch=true`).
   - Routes live in reviewed YAML (`infra/traefik/dynamic/*.yml`).
   - The Docker provider is disabled (it also can't route across hosts).
3. **Plugins stored locally in the image:**
   - The CrowdSec bouncer plugin is downloaded in CI at a pinned version and checksum, copied into `/plugins-local/`, and loaded via `experimental.localPlugins`.
   - Traefik never fetches plugins from the internet at runtime.
4. **Entry points:**
   - `web` (:80): redirects everything to HTTPS, except the ACME HTTP-01 challenge.
   - `websecure` (:443): HTTP/2 enabled; HTTP/3 off for the POC.
   - `forwardedHeaders.insecure=false`; `trustedIPs` empty until Cloudflare is added (ADR-0023).
   - Published on `0.0.0.0:80`/`443` (and IPv6 only if enabled per ADR-0014).
5. **TLS:**
   - ACME resolver `le` using **HTTP-01**, storage `/letsencrypt/acme.json` (volume, mode 0600).
   - TLS options: `minVersion: VersionTLS12`, secure cipher suites, `sniStrict: true`. HSTS is set via headers middleware (see 7).
6. **Routers** (single POC hostname, ADR-0022):

   | Router | Rule | Service | Middlewares |
   |---|---|---|---|
   | `keycloak-public` | ``Host(`<poc-host>`) && (PathPrefix(`/auth/realms/`) \|\| PathPrefix(`/auth/resources/`))`` | `http://10.10.0.2:8080` (over WireGuard) | crowdsec, secure-headers, ratelimit-auth, body-limit |
   | `keycloak-block` | ``Host(`<poc-host>`) && PathPrefix(`/auth`)`` (lower priority than above) | noop → **404** | — |
   | `frontend` | ``Host(`<poc-host>`)`` | `http://frontend:3000` (Docker network `edge`) | crowdsec, secure-headers, ratelimit-app, body-limit, compress |

   Everything else (IP-address or unknown `Host`) hits a default catch-all router returning 404, with a default self-signed certificate, so scanners get nothing.
7. **Middlewares:**
   - `secure-headers`:
     - `stsSeconds: 63072000`, `stsIncludeSubdomains: true` (preload once a real domain exists).
     - `contentTypeNosniff`, `frameDeny`, `referrerPolicy: strict-origin-when-cross-origin`, a restrictive `permissionsPolicy`.
     - `customResponseHeaders` removes the `Server` and `X-Powered-By` headers.
     - CSP is set by Next.js (nonces) for app pages and by a strict static policy for Keycloak paths.
   - `ratelimit-app` (e.g. average 50 req/s, burst 100 per IP) and `ratelimit-auth` (e.g. 10 req/s, burst 20 per IP); tuned during POC testing.
   - `body-limit`: `buffering.maxRequestBodyBytes` 1 MiB (Keycloak paths 256 KiB).
   - `inFlightReq` limit per IP.
   - `crowdsec` (ADR-0013).
8. **Operations:**
   - Dashboard and API **disabled** (`api.dashboard=false`, `api.insecure=false`).
   - Access logs in JSON to `/var/log/traefik/access.log` (shared read-only with CrowdSec), with `Authorization` and `Cookie` headers dropped.
   - Health check via `ping` on a non-published entry point.
   - Runs as non-root with `cap_add: [NET_BIND_SERVICE]`.

## Alternatives considered

| Option | Why not chosen |
|---|---|
| Caddy 2.11 | Excellent and simplest TLS, but lower container adoption; WAF/CrowdSec requires a custom build. Owner prioritized adoption. |
| Traefik with Docker provider (+ socket proxy) | Label discovery can't route to VPS-B anyway; a socket proxy is still extra attack surface |
| Nginx / Nginx Proxy Manager | Nginx is the most deployed web server, but with manual certificate automation and less dynamic configuration; NPM exposes an admin UI and has had security issues |
| HAProxy | Top-tier performance and reliability; weaker automatic ACME/WAF integration for a small POC |

## Consequences

**Positive**
- Widely adopted proxy with first-class CrowdSec integration; no Docker socket; routes reviewed in PRs.

**Negative / risks**
- File-provider routes must be edited by hand when services change (rare here).
- Local plugins must be refreshed with Traefik upgrades (Renovate + CI).
- The Traefik CVEs involved forward-auth; **we don't use forward-auth middleware**, and we keep patching fast.

**Follow-ups**
- Enable HSTS preload and split `app.`/`auth.` hostnames with the real domain.
- Configure Cloudflare `trustedIPs` (ADR-0023).

## References

- https://doc.traefik.io/traefik/providers/file/
- https://doc.traefik.io/traefik/https/acme/
- https://doc.traefik.io/traefik/plugins/
- https://traefik.io/blog/traefik-contributor-count-and-adoption-are-accelerating
- https://commandlinux.com/statistics/reverse-proxy-usage-nginx-haproxy-traefik-caddy
- https://github.com/traefik/traefik/releases
- https://www.tenable.com/cve/CVE-2026-54764
- https://github.com/caddyserver/caddy/security/advisories
- https://www.keycloak.org/2026/07/keycloak-2670-released
