# syntax=docker/dockerfile:1.7
# Traefik image (ADR-0012): file provider only, CrowdSec bouncer plugin baked in as a local plugin,
# non-root, unprivileged listeners (8080/8443 published as 80/443). Build: docker build infra/traefik/

ARG TRAEFIK_IMAGE=traefik:v3.7.13@sha256:f86a2cab1b5c649070c49f883c743dd32d8485a56e3368c5f93b9e91f1e91259

# --- plugins: verified source tarball extracted into the local-plugin layout --------------------
FROM ${TRAEFIK_IMAGE} AS plugins
# renovate: datasource=github-releases depName=maxlerebourg/crowdsec-bouncer-traefik-plugin extractVersion=^v(?<version>.*)$
ARG CROWDSEC_PLUGIN_VERSION=1.7.1
ADD --checksum=sha256:a50cdfe37d67c48be571417a26d8c5a2b28e4b91e5b1ed3b1ea2bcb0e6b4aa38 \
    https://github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin/archive/refs/tags/v${CROWDSEC_PLUGIN_VERSION}.tar.gz /tmp/crowdsec-plugin.tar.gz
RUN mkdir -p /plugins-local/src/github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin \
    && tar -xzf /tmp/crowdsec-plugin.tar.gz -C /plugins-local/src/github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin --strip-components=1 \
    && rm -rf /plugins-local/src/github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin/.github \
    && test -f /plugins-local/src/github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin/.traefik.yml

# --- runtime ----------------------------------------------------------------------------------
FROM ${TRAEFIK_IMAGE} AS runtime
ARG GIT_SHA=unknown
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.title="web-app-test traefik" \
      org.opencontainers.image.description="Traefik v3.7 with the CrowdSec bouncer local plugin" \
      org.opencontainers.image.source="https://github.com/akshatauppinventure/web-app-test" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="traefik:v3.7.13"

# OS security updates (pinned base digest lags Alpine's repo; ADR-0019 §3 gate).
RUN apk upgrade --no-cache \
    && addgroup -g 65532 -S traefik && adduser -u 65532 -S -G traefik -H -s /sbin/nologin traefik \
    && mkdir -p /letsencrypt /var/log/traefik /etc/traefik/dynamic \
    && chown 65532:65532 /letsencrypt /var/log/traefik && chmod 700 /letsencrypt
COPY --from=plugins --chown=root:root /plugins-local /plugins-local
COPY --chown=root:root traefik.yml /etc/traefik/traefik.yml
COPY --chown=root:root dynamic/ /etc/traefik/dynamic/
COPY --chown=root:root --chmod=755 scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

USER 65532:65532
EXPOSE 8080 8443
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 CMD ["traefik", "healthcheck", "--ping.entryPoint=ping", "--entryPoints.ping.address=:8082"]
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
