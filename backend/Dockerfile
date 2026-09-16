# syntax=docker/dockerfile:1.7
# Backend image (ADR-0008 §4, ADR-0005, ADR-0020).
# Build: docker build -t backend:dev --build-arg GIT_SHA=$(git rev-parse HEAD) backend/
# Digests are managed by Renovate (T10).

# NEGATIVE TEST (T12): an old base image with known fixable CVEs; must fail the Trivy gate
ARG PYTHON_IMAGE=python:3.14.0-slim-trixie

# --- uv binary (distroless image, only /uv is copied) -----------------------------------
FROM ghcr.io/astral-sh/uv:0.12.15@sha256:62f8c047d0a0e9ece6b53fc63df902585a67a47a7f318ddec4a37db586edc8e3 AS uv

# --- builder: locked, non-editable install into /app/.venv ------------------------------
FROM ${PYTHON_IMAGE} AS builder
COPY --from=uv /uv /usr/local/bin/uv
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/app/.venv
WORKDIR /app
# Dependencies first (cache-friendly), project second.
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-install-project
COPY README.md alembic.ini ./
COPY app ./app
COPY alembic ./alembic
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-editable

# --- runtime: no uv, no build tools, non-root, read-only friendly -----------------------
FROM ${PYTHON_IMAGE} AS runtime
ARG GIT_SHA=unknown
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.title="web-app-test backend" \
      org.opencontainers.image.description="FastAPI backend for the secure 2-VPS web app POC" \
      org.opencontainers.image.source="https://github.com/akshatauppinventure/web-app-test" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="akshatauppinventure"

# OS security updates (the pinned base digest lags Debian's security repo; ADR-0019 §3 gate),
# non-root user, and drop pip from the base image (nothing installs at runtime; less surface).
RUN groupadd --gid 10001 app \
    && useradd --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app \
    && python -m pip uninstall --yes pip \
    && rm -rf /root/.cache /usr/local/lib/python3.14/site-packages/pip* /usr/local/bin/pip*

WORKDIR /app
COPY --from=builder --chown=root:root --chmod=755 /app/.venv /app/.venv
COPY --from=builder --chown=root:root /app/alembic /app/alembic
COPY --from=builder --chown=root:root /app/alembic.ini /app/alembic.ini

ENV PATH="/app/.venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONFAULTHANDLER=1 \
    PYTHONHASHSEED=random \
    ENVIRONMENT=poc

USER 10001:10001
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2).status == 200 else 1)"]

# FORWARDED_ALLOW_IPS (VPS-A WireGuard IP) is read by uvicorn from the environment (ADR-0008 §4).
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--no-server-header", "--no-date-header"]
