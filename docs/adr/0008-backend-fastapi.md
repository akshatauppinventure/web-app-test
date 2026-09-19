# ADR-0008: Backend: FastAPI on Python 3.14

- **Status:** Accepted (2026-09-15); WireGuard references superseded by [ADR-0026](0026-remove-wireguard-public-ssh-private-network.md)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0009, ADR-0011, ADR-0019, ADR-0020

## Context

The owner requires a Python backend API. It must:
- validate Keycloak-issued JWTs,
- enforce authorization,
- talk to PostgreSQL with Row-Level Security,
- run as a small, hardened container.

Versions as of 2026-09-14:
- **FastAPI 0.141.x** (July 2026). FastAPI releases often.
- **Python 3.14.x** (`python:3.14-slim-trixie`, 3.14.7). Python 3.15 is due in October 2026.
- **uv** is the de facto fast Python package and project manager.

## Decision

1. **Framework and libraries:**
   - **FastAPI** (pinned exact version) + **Uvicorn**
   - **Pydantic v2** (strict models, `extra="forbid"`)
   - **SQLAlchemy 2.x** (async) with **psycopg 3**
   - **Alembic** migrations
   - **PyJWT** (with `cryptography`) for JWT validation (ADR-0011)
   - **pydantic-settings** for configuration (reading secrets from files)
2. **Runtime:** **Python 3.14** on `python:3.14-slim-trixie` (pinned by digest).
3. **Dependency management:** **uv** with a committed `uv.lock`; CI uses `uv sync --locked`.
4. **Container build:**
   - Multi-stage. The builder stage installs into a virtualenv; the final stage copies only the venv and app code. uv isn't shipped in the final image.
   - Runs as a non-root UID, with a read-only root filesystem.
   - Command: `uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers --forwarded-allow-ips=<VPS-A WireGuard IP>`. Uvicorn runs inside the container; the published port is bound to the WireGuard IP (ADR-0014).
5. **API conventions:**
   - Version prefix `/v1`.
   - `GET /healthz` (unauthenticated liveness check, no dependencies) and `GET /readyz` (checks the DB; reachable only from the internal network or WireGuard).
   - Hello-world endpoints: `GET /v1/me` and `GET /v1/hello`.
   - **OpenAPI docs (`/docs`, `/redoc`, `/openapi.json`) are turned off** when `ENVIRONMENT != "local"`.
   - CORS **off**: FastAPI is never called by browsers (ADR-0011).
   - Structured JSON logging. Never log tokens, secrets or personal data.
   - Request body size limits; strict input validation; errors don't reveal internals.
6. **Data access:**
   - Only parameterized ORM/Core queries. No string-built SQL.
   - Every request that touches user data runs in a transaction that sets the RLS user context (ADR-0011).
7. **Quality gates:** `ruff` (lint + format), `pyright` (strict for `app/`), `pytest` (+ `pytest-asyncio`), with a Postgres service container in CI for integration and RLS tests.

## Alternatives considered

| Option | Why not chosen |
|---|---|
| Django + DRF | Heavier; brings its own auth/admin/ORM, which we don't want (Keycloak handles identity) |
| Flask | Less built-in validation, async support and OpenAPI; FastAPI is now the mainstream Python API choice |
| Litestar | Technically strong, but a much smaller community |
| Python 3.13 | Older; 3.14 is current stable with good wheel coverage by Sept 2026 |
| Poetry / pip-tools | uv is faster, has a lockfile and is now the most widely adopted |
| Granian server | Promising, but Uvicorn is more widely deployed and documented |

## Consequences

**Positive**
- Typed, validated API with little boilerplate; small, reproducible images.

**Negative / risks**
- FastAPI's 0.x versioning and fast releases mean occasional breaking changes. Mitigated by exact pins, Renovate PRs and tests.
- Async SQLAlchemy adds complexity. Kept to simple patterns for the POC.

**Follow-ups**
- Evaluate Python 3.15 after its release (Oct 2026) and ecosystem wheel availability.

## References

- https://pypi.org/project/fastapi/
- https://github.com/docker-library/python/tree/master/3.14/slim-trixie
- https://hynek.me/articles/docker-uv/
- https://docs.astral.sh/uv/guides/integration/docker/
