# GitOps stacks (ADR-0018)

Portainer (on VPS-B) deploys these two Compose files from `main` with 5-minute polling and "re-pull image":

| Stack | Environment | File | Services |
|---|---|---|---|
| `edge` | VPS-A (Agent) | `edge/compose.yaml` | traefik (`0.0.0.0:80/443`), crowdsec, frontend |
| `core` | VPS-B (local) | `core/compose.yaml` | postgres (no ports, `db` internal network), migrate (one-shot), keycloak (`10.0.0.2:8080`), backend (`10.0.0.2:8000`) on core's private-network address (ADR-0026) |

**Images** are `ghcr.io/akshatauppinventure/<component>:sha-<git-sha>@sha256:<digest>`, written by the deploy-PR bot (T13) after CI signs them. The `sha-0000000@sha256:000…` placeholders are replaced by the first deploy PRs; `scripts/ci/check-hardening.py` only checks the digest *form*.

**Stack environment variables Portainer must set (none secret):**

| Stack | Variable | Value |
|---|---|---|
| edge | `ACME_EMAIL` | owner's email for Let's Encrypt |
| edge | `ACME_CA_SERVER` | staging URL for the first deploy (T22), then production (default) |
| edge, core | `PUBLIC_HOST` | optional; default `test-vinayak.duckdns.org` |
| core | `GOOGLE_CLIENT_ID` | Google OAuth client "poc" id (public) |
| core | `CORE_BIND_IP` | optional; default `10.0.0.2` (core private-network address) |

**Secrets** are files under `/etc/app/secrets/` on each host (`scripts/secrets/secrets-push.sh`, T19; schema in `infra/secrets/SCHEMA.md`). Edge secrets never go to VPS-B and vice versa.

**Policy checks (CI):** `scripts/ci/check-compose.sh`, `scripts/ci/check-published-ports.sh` (allowlist `infra/policy/published-ports.txt`), `scripts/ci/check-hardening.py` (exceptions in `infra/policy/hardening-exceptions.yaml`).

**Local dry run:** `make stacks-dryrun` starts each stack with `scripts/test/stacks/*.override.yaml` (local images, `.dev-secrets`, loopback binds) and checks health, the public issuer, routing and the bouncer registration.
