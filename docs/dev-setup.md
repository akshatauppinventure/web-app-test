# Local development setup (PLAN T09)

The local stack mirrors the POC topology in Docker Compose: PostgreSQL 18, Keycloak 26.7 (custom image), a one-shot migration job, the FastAPI backend and the Next.js frontend. Everything listens on `127.0.0.1` only.

## Prerequisites

- Docker Desktop (or Docker Engine 27+ with Compose v2), `make`, `curl`, `jq`, `openssl`.
- For working on the code itself: `uv` (backend), `pnpm` 12 (frontend), `hadolint`, `shellcheck` — see `CLAUDE.md` → Toolchain.

## First start

```bash
make dev-up        # generates .dev-secrets/, copies .env.example to .env, builds images, starts everything
make dev-smoke     # health checks + a real sign-in/sign-out with the local user dev@example.com
```

| URL | What |
|---|---|
| http://localhost:3000 | Frontend (sign-in buttons → Keycloak → `/hello`) |
| http://localhost:8000/docs | Backend OpenAPI docs (`ENVIRONMENT=local` only) |
| http://localhost:8080/auth/admin | Keycloak admin console — user `admin`, password in `.dev-secrets/keycloak_admin_password` |

Local user for the app realm: `dev@example.com`, password in `.dev-secrets/dev_user_password` (created by `make dev-smoke`; or register a new account on the Keycloak login page — registration is enabled).

Other targets: `make dev-logs`, `make dev-down` (keeps data), `make dev-reset` (drops volumes; the realm is re-imported on the next start; `.dev-secrets/` is kept).

## Sign in with Google locally (owner prerequisite P2)

1. Google Cloud Console → *APIs & Services* → *OAuth consent screen*: External, Testing, add yourself as a test user.
2. *Credentials* → *Create credentials* → *OAuth client ID* → Web application, name `local`.
   Authorized redirect URI: `http://localhost:8080/auth/realms/app/broker/google/endpoint`.
3. Put the **client ID** in `.env` (`GOOGLE_CLIENT_ID=…apps.googleusercontent.com`).
4. Put the **client secret** in `.dev-secrets/app_google_client_secret` (no trailing newline: `printf '%s' '<secret>' > .dev-secrets/app_google_client_secret`).
5. `make dev-reset && make dev-up` (the client ID is substituted into the realm at first import; the secret is read live from the file vault, so changing only the secret needs just `docker compose -f compose.dev.yaml restart keycloak`).
6. Open http://localhost:3000 → *Sign in with Google* → Google consent → `/hello` shows the visit message; a second visit increments the count.

## How the pieces talk

| From → to | Address | Why |
|---|---|---|
| Browser → Keycloak | `http://localhost:8080/auth` | `KC_HOSTNAME`; also the token issuer (`iss`) |
| Frontend → Keycloak (token, userinfo, refresh) | `http://keycloak:8080/auth` | `KEYCLOAK_INTERNAL_ISSUER`; no discovery, no hairpin |
| Frontend → Backend | `http://backend:8000` | `API_BASE_URL`; bearer token from the session |
| Backend → Keycloak (JWKS) | `http://keycloak:8080/auth/…/certs` | `OIDC_JWKS_URL`; `OIDC_ISSUER` stays the public issuer |
| Keycloak / backend / migrate → Postgres | `postgres:5432` on the `db` network (`internal: true`, `172.28.1.0/24`) | matches `pg_hba.conf` |

Secrets are files in `.dev-secrets/` mounted as Compose secrets (`/run/secrets/*`), never environment variables (ADR-0016). `scripts/dev/gen-dev-secrets.sh --force` regenerates them (then `make dev-reset`, because Postgres roles keep the old passwords).

## Troubleshooting

- **`migrate` exits non-zero on first start:** Postgres init did not finish; `make dev-logs` and check `initdb:` lines. `make dev-reset` and retry.
- **Login loop / "RefreshTokenError":** the frontend and Keycloak disagree on the issuer. `AUTH_KEYCLOAK_ISSUER` must equal `KC_HOSTNAME` + `/realms/app`.
- **Changed `infra/keycloak/realms/app-realm.json`:** it is baked into the image and imported only into an empty database: `make dev-reset && make dev-up`.
- **Ports 3000/8000/8080 busy:** stop the other process; the compose file binds fixed loopback ports.
