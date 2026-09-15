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
5. **Pinning (ADR-0020).** Container images: exact tag **and** `@sha256:` digest, never `latest`. GitHub Actions: full commit SHA with a version comment. Python/Node dependencies: locked (`uv.lock`, `pnpm-lock.yaml`).
6. **Docs move with code.** Update README, runbooks, `PLAN.md` status and this file in the same PR.
7. **Commit messages:** imperative subject ≤ 72 chars prefixed with the task id, e.g. `T01: add FastAPI scaffold with health endpoints`.

## Toolchain (local, macOS arm64)

| Area | Tools | Notes |
|---|---|---|
| Backend | `uv`, Python 3.14, `ruff`, `pyright`, `pytest` | `cd backend && uv sync --locked` |
| Frontend | `pnpm` (exact version in `package.json`), Node 24 | `cd frontend && pnpm install --frozen-lockfile` |
| Containers | Docker 29 (arm64 locally; CI builds `linux/amd64`), `hadolint` | Test images with `--read-only --cap-drop ALL --security-opt no-new-privileges` |
| Infra | `shellcheck`, `docker compose config`, `sops`, `age`, `tofu` | Installed as the corresponding tasks land |

## Commands

Targets are added to the `Makefile` as tasks land; `make help` lists them. Until then a stub target fails with the task id that will implement it.

- `make backend-check` — locked sync, ruff lint + format check, pyright (strict), pytest. Run before every backend commit.
- `make backend-run` — uvicorn on :8000 with `/docs` enabled (`ENVIRONMENT=local`).
- `make test-db-up` / `make test-db-down` — throwaway Postgres 18.6 from `compose.test.yaml` on `127.0.0.1:55432` (test-only passwords in `scripts/test/pg-secrets/`). DB tests skip when it is not running; run them before every backend PR.
- `make backend-migrate` — `alembic upgrade head`; needs `DATABASE_URL` for the `app_migrator` role.

## Backend conventions (`backend/`)

- App factory `create_app(settings)` in `app/main.py`; tests build apps with explicit `Settings`, never from the environment.
- `Settings` (`app/config.py`) reads env vars and secret files from `SECRETS_DIR` (default `/run/secrets`) via `load_settings()`. Secrets are `SecretStr`; nothing secret has a default.
- Logging is structlog JSON; `redact_sensitive` blanks keys like `authorization`, `cookie`, `*token*`, `password`. Never log request bodies or tokens.
- `/docs`, `/redoc`, `/openapi.json` exist only when `ENVIRONMENT=local`; `/healthz` and `/readyz` are unauthenticated and excluded from the schema.
- pytest runs with `filterwarnings = error` and `asyncio_mode = auto`; tests are a package (`tests/__init__.py`). DB fixtures live in `tests/db_fixtures.py` (registered as a pytest plugin); mark DB tests with `requires_postgres`.
- Database (`app/db.py`): `Database.user_session(sub)` opens one transaction and sets `app.user_id` transaction-locally; all user-data queries go through it. Never accept an owner id from the client.
- Migrations are hand-written Alembic files under `backend/alembic/versions/` (no autogenerate). Every user-data table gets `ENABLE` + `FORCE ROW LEVEL SECURITY`, a policy on `current_setting('app.user_id', true)` and explicit grants to `app_rw`. Migrations connect as `app_migrator`; `env.py` does `SET ROLE app_owner`.
- Postgres roles/config live in `infra/postgres/` (see its README). The `db` network subnet is fixed at `172.28.1.0/24`.

## Task status

| Task | Status | PR |
|---|---|---|
| T00 Repo skeleton, ADRs accepted | done | initial commit |
| T01 Backend scaffold | done | #1 |
| T02 DB schema, roles, migrations, RLS | done | #2 |
| T03–T25 | not started | — |
