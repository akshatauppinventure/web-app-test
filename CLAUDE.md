# CLAUDE.md — working conventions for this repository

Read this first. `PLAN.md` is the roadmap (tasks T00–T25); `docs/adr/` holds the 24 accepted decisions. Do not re-open accepted decisions; write a superseding ADR instead.

## Fixed facts

- GitHub repo: `akshatauppinventure/web-app-test` (private). Default branch `main`. Rulesets are unavailable on this private repo under the Free plan (owner decision P12 pending); protection is process-only: never push to `main` directly, always PR.
- POC hostname: `test-vinayak.duckdns.org` (DuckDNS, Let's Encrypt HTTP-01). No custom domain, Cloudflare or Apple login in the POC.
- Hosting target: UpCloud `us-nyc1`, two Ubuntu 26.04 VPS: A "edge" (Traefik, CrowdSec, frontend) and B "core" (Keycloak, backend, PostgreSQL, Portainer Server). WireGuard `10.10.0.1` (A) / `10.10.0.2` (B).
- Owner-only prerequisites (accounts, tokens, purchases) are listed in `PLAN.md` § "Owner prerequisites". Never fake them; stop and report when one is missing.

## How work is done

1. **One task = one branch = one PR.** Branch `task/T##-short-name`; PR title `T##: <title>`; body follows `.github/PULL_REQUEST_TEMPLATE.md` and names the ADRs implemented. Merge with squash.
2. **Test-driven.** Write the failing test first, then the minimum code to pass, then refactor. Every task's "Tests" list in `PLAN.md` is the minimum; each PR states how the tests were run.
3. **Definition of done** is the global list in `PLAN.md` plus the task's own "Done when". CI green from T11 onward; before that, the task's listed local checks must pass.
4. **No secrets in git.** Local dev secrets live in `.dev-secrets/` (gitignored); deployed secrets are SOPS+age encrypted in `infra/secrets/`. Never print secret values in logs, PRs or chat.
5. **Pinning (ADR-0020).** Renovate (`renovate.json`) keeps pins current; put a `# renovate: datasource=… depName=…` comment above any `ARG *_VERSION` so it is tracked. Validate config changes with `npx --yes --package renovate@<ver> renovate-config-validator renovate.json`. Container images: exact tag **and** `@sha256:` digest, never `latest`. GitHub Actions: full commit SHA with a version comment. Python/Node dependencies: locked (`uv.lock`, `pnpm-lock.yaml`).
6. **Docs move with code.** Update README, runbooks, `PLAN.md` status and this file in the same PR.
7. **Commit messages:** imperative subject ≤ 72 chars prefixed with the task id, e.g. `T01: add FastAPI scaffold with health endpoints`.

## Toolchain (local, macOS arm64)

| Area | Tools | Notes |
|---|---|---|
| Backend | `uv`, Python 3.14, `ruff`, `pyright`, `pytest` | `cd backend && uv sync --locked` |
| Frontend | `pnpm` 12 (exact version in `package.json`; `npm i -g pnpm@<ver>` if corepack fails), Node 24 | `cd frontend && pnpm install --frozen-lockfile` |
| Containers | Docker 29 (arm64 locally; CI builds `linux/amd64`), `hadolint` | Test images with `--read-only --cap-drop ALL --security-opt no-new-privileges` |
| Infra | `shellcheck`, `docker compose config`, `sops`, `age`, `tofu` | Installed as the corresponding tasks land |

## Commands

Targets are added to the `Makefile` as tasks land; `make help` lists them. Until then a stub target fails with the task id that will implement it.

- `make backend-check` — locked sync, ruff lint + format check, pyright (strict), pytest. Run before every backend commit.
- `make backend-run` — uvicorn on :8000 with `/docs` enabled (`ENVIRONMENT=local`).
- `make test-db-up` / `make test-db-down` — throwaway Postgres 18.6 from `compose.test.yaml` on `127.0.0.1:55432` (test-only passwords in `scripts/test/pg-secrets/`). DB tests skip when it is not running; run them before every backend PR.
- `make backend-migrate` — `alembic upgrade head`; needs `DATABASE_URL` for the `app_migrator` role.
- `make frontend-check` — frozen install, next-version guard, eslint, tsc, vitest, `next build`. Run before every frontend commit.
- `make keycloak-image` / `make keycloak-smoke` — build the Keycloak image and run the smoke test against Postgres + Keycloak on `127.0.0.1:18080` (compose profile `keycloak`). Run the smoke test for every Keycloak or extension bump.
- `make dev-up` / `make dev-smoke` / `make dev-logs` / `make dev-down` / `make dev-reset` — local full stack from `compose.dev.yaml` (`docs/dev-setup.md`). `dev-smoke` runs the health checks and a real sign-in/sign-out. Run it after any change to auth, realm, compose or images.
- `make frontend-image` / `make frontend-image-test` — build `web-app-test/frontend:dev` and run `scripts/test/frontend-image.sh` (uid 1000, read-only FS with tmpfs `/app/.next/cache`, no npm, `/api/healthz`, no `X-Powered-By`, labels, HEALTHCHECK).
- `make backend-image` / `make backend-image-test` — build `web-app-test/backend:dev` and run `scripts/test/backend-image.sh` (uid 10001, read-only FS, no uv/pip, `/healthz`, OCI labels, HEALTHCHECK). `make hadolint` lints all Dockerfiles with `.hadolint.yaml` (warnings fail).

## Compose conventions

- Every service: `read_only`, `cap_drop: [ALL]`, `no-new-privileges`, `mem_limit`, `pids_limit`, healthcheck; writable paths are `tmpfs`. Postgres adds back only the caps its entrypoint needs.
- Ports bind to `127.0.0.1` locally; in the stacks (T16) only Traefik binds `0.0.0.0`.
- Secrets are Compose `secrets:` (files), never environment variables. Apps read `*_FILE` or `/run/secrets/<name>`; the migrate job uses `DATABASE_URL_FILE`.
- Network `db` is `internal: true` with subnet `172.28.1.0/24` (fixed by `pg_hba.conf`); `core` is `172.28.2.0/24`. The test compose uses the same `db` subnet, so the dev stack and `make test-db-up` cannot run at the same time (`make dev-down` first; the Makefile guards this).

## Container image conventions

- Multi-stage; the runtime stage has no package manager for the language (no uv, no pip), runs as a fixed non-root UID, and works with `--read-only --cap-drop ALL --security-opt no-new-privileges`. Writable paths are `tmpfs`.
- `HEALTHCHECK` uses tools already in the image (python for the backend); no curl/wget added.
- OCI labels `source`, `revision`, `created` come from build args `GIT_SHA`, `BUILD_DATE`.
- Base images: exact tag **and** digest (multi-arch index digest, so the same line builds on arm64 locally and amd64 in CI).

## Frontend conventions (`frontend/`)

- pnpm 12 with `pnpm-workspace.yaml` supply-chain settings: `minimumReleaseAge: 4320` (3 days) blocks brand-new versions, so pick the newest version older than 3 days when pinning (`npm view <pkg> time --json`). Lifecycle scripts run only for `onlyBuiltDependencies`; anything else that needs a build goes in `ignoredBuiltDependencies` with a comment, never disable `strictDepBuilds`.
- ESLint stays on the newest 9.x until eslint-config-next's plugins support ESLint 10 (eslint-plugin-react 7.37 crashes on 10).
- Version floor for `next` is `16.3.3` (`scripts/check-next-version.mts`, tested); CI fails below it (T11).
- App Router only, TypeScript strict with `noUncheckedIndexedAccess` and `exactOptionalPropertyTypes`. Server-only code imports `server-only` (T07). No client-side token handling, ever.
- Tests: vitest (node environment) in `frontend/tests/*.test.ts`; test route handlers by importing and calling them. Pure logic lives in `frontend/lib/*` with injected `fetchImpl`/`now` so it is unit-testable; `auth.ts` is never imported by tests.
- Auth.js v5 gotchas learned in T07: with a lazy config (`NextAuth(() => cfg)`), `auth(handler)` returns a Promise, so `proxy.ts` must call `auth(req, event)` inline and rely on `callbacks.authorized`; explicit `authorization`/`token`/`userinfo` URLs skip OIDC discovery (browser → public issuer, server → `KEYCLOAK_INTERNAL_ISSUER`); `/api/auth/session` is blocked in the route handler so tokens never reach the browser; `next start` warns with `output: standalone` (the container runs `node server.js`).
- pnpm 12 build-script policy lives in `allowBuilds` (true/false per package) in `pnpm-workspace.yaml`; pnpm appends placeholder entries when a new package with scripts appears, so commit a deliberate `true`/`false`.
- `make frontend-e2e` (`scripts/test/frontend-e2e.sh`) drives sign-in → Keycloak form → callback → `/hello` → logout with curl; run it whenever auth code changes.

## Keycloak conventions (`infra/keycloak/`)

- Realm JSON is the source of truth and contains **no secrets**: `${ENV_VAR}` placeholders are substituted once at first import; `${vault.<key>}` reads `/run/secrets/app_<key>` on use (Keycloak file vault, built in with `--vault=file`).
- Build-time options (`db`, `http-relative-path`, `health`, `metrics`, `vault`) must be passed to `kc.sh build`; runtime env vars cannot change them on an `--optimized` image.
- Realm-import gotchas learned in T05: `defaultRole.composites` is ignored (define `default-roles-app` inside `roles.realm`); composites can only reference roles defined in the same file (built-ins like `uma_authorization` don't exist yet); users created via `partialImport` do not get default roles, users created via `POST /admin/realms/app/users` do.
- Third-party jars: record version, URL, sha256 and upstream sha512 in `checksums.txt`; the Dockerfile uses `ADD --checksum=sha256:…`; `scripts/verify-checksums.sh` cross-checks both.

## Backend conventions (`backend/`)

- App factory `create_app(settings)` in `app/main.py`; tests build apps with explicit `Settings`, never from the environment.
- `Settings` (`app/config.py`) reads env vars and secret files from `SECRETS_DIR` (default `/run/secrets`) via `load_settings()`. Secrets are `SecretStr`; nothing secret has a default.
- Logging is structlog JSON; `redact_sensitive` blanks keys like `authorization`, `cookie`, `*token*`, `password`. Never log request bodies or tokens.
- `/docs`, `/redoc`, `/openapi.json` exist only when `ENVIRONMENT=local`; `/healthz` and `/readyz` are unauthenticated and excluded from the schema.
- pytest runs with `filterwarnings = error` and `asyncio_mode = auto`; tests are a package (`tests/__init__.py`). DB fixtures live in `tests/db_fixtures.py` (registered as a pytest plugin); mark DB tests with `requires_postgres`.
- Database (`app/db.py`): `Database.user_session(sub)` opens one transaction and sets `app.user_id` transaction-locally; all user-data queries go through it. Never accept an owner id from the client.
- Migrations are hand-written Alembic files under `backend/alembic/versions/` (no autogenerate). Every user-data table gets `ENABLE` + `FORCE ROW LEVEL SECURITY`, a policy on `current_setting('app.user_id', true)` and explicit grants to `app_rw`. Migrations connect as `app_migrator`; `env.py` does `SET ROLE app_owner`.
- Postgres roles/config live in `infra/postgres/` (see its README). The `db` network subnet is fixed at `172.28.1.0/24`.
- Auth (`app/auth/`): `current_user` validates the bearer JWT (alg allowlist `RS256`/`ES256`, `iss`, `aud=api`, `azp=web-bff`, `typ=Bearer`, `exp`/`nbf`/`iat` with 30 s leeway, non-empty `sub`); `require_roles("user")` guards every `/v1` route. JWKS is cached in `JWKSClient`; unknown `kid` refreshes at most once per 60 s. OIDC settings (`OIDC_ISSUER`, `OIDC_JWKS_URL`, …) are env vars, not secrets.
- Test tokens come from `tests/keys.py` (RSA pair generated at import, fake JWKS served through `respx`). Add a negative test for every new claim check.

## Task status

| Task | Status | PR |
|---|---|---|
| T00 Repo skeleton, ADRs accepted | done | initial commit |
| T01 Backend scaffold | done | #1 |
| T02 DB schema, roles, migrations, RLS | done | #2 |
| T03 JWT validation and hello endpoints | done | #3 |
| T04 Backend container image | done | #4 |
| T05 Keycloak image and `app` realm | done | #7 |
| T06 Frontend scaffold | done | #5, #6 |
| T07 Frontend auth (Auth.js BFF) and /hello | done | #8 |
| T08 Frontend container image | done | #9 |
| T09 Local full stack + dev docs | done (Google login pending owner P2) | #10 |
| T10 Renovate + repo policy | done (app install pending owner P13) | #11 |
| T11–T25 | not started | — |
