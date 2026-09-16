# syntax=docker/dockerfile:1.7
# PostgreSQL 18 with the POC roles/hardening scripts and configuration baked in (ADR-0009), so the
# GitOps stack needs no bind mounts. Runs as the `postgres` user (uid 999) from the start.
ARG POSTGRES_IMAGE=postgres:18.6-trixie@sha256:4ef4dbc939d61acea57712655ddb4b4ab27419c913f94cca0cd57cb3ea3c2280
FROM ${POSTGRES_IMAGE}
ARG GIT_SHA=unknown
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.title="web-app-test postgres" \
      org.opencontainers.image.description="PostgreSQL 18.6 with least-privilege roles, scram-only pg_hba and hardening settings" \
      org.opencontainers.image.source="https://github.com/akshatauppinventure/web-app-test" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="postgres:18.6-trixie"
COPY --chown=root:root --chmod=755 initdb/01-roles.sh /docker-entrypoint-initdb.d/01-roles.sh
COPY --chown=root:root --chmod=644 initdb/02-hardening.sql /docker-entrypoint-initdb.d/02-hardening.sql
COPY --chown=root:root --chmod=644 postgresql.conf pg_hba.conf /etc/postgresql/
USER 999:999
CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]
