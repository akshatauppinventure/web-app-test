# backend

FastAPI service (ADR-0008). Python 3.14, managed with `uv`.

```bash
uv sync --locked            # create .venv from uv.lock
uv run pytest -q            # tests
uv run ruff check . && uv run ruff format --check . && uv run pyright
ENVIRONMENT=local uv run uvicorn app.main:app --reload   # http://127.0.0.1:8000/docs
```

Configuration: environment variables (`ENVIRONMENT`, `LOG_LEVEL`, `LOG_JSON`) and secret files in `SECRETS_DIR` (default `/run/secrets`), e.g. `/run/secrets/database_url`. See `app/config.py`.

## Database

- Start a test database: `make test-db-up` (Postgres 18.6, roles from `infra/postgres/initdb`).
- Migrations: `DATABASE_URL=postgresql+psycopg://app_migrator:<pw>@host:5432/app uv run alembic upgrade head`.
- The runtime role is `app_rw`; RLS is forced on every user-data table (`tests/test_rls.py`).
