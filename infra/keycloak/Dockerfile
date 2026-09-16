# syntax=docker/dockerfile:1.7
# Keycloak custom image (ADR-0010 §1): Apple identity-provider extension + optimized build.
# Build: docker build -t keycloak:dev infra/keycloak/
# The extension checksum below must match infra/keycloak/checksums.txt (checked in CI).

ARG KEYCLOAK_IMAGE=quay.io/keycloak/keycloak:26.7.3@sha256:29be7252db0a106f1cd2ac17b9a56ff2668073da645638a38b9fc67deeb2d6c4

# --- builder: add providers, run the augmentation (kc.sh build) -----------------------
FROM ${KEYCLOAK_IMAGE} AS builder
# renovate: datasource=github-releases depName=klausbetz/apple-identity-provider-keycloak
ARG APPLE_IDP_VERSION=1.17.0
ADD --checksum=sha256:4091dee2a1ec9e0771bef4bd46005197d86b0a2b1f25198c41738476b1d102bb --chown=keycloak:keycloak \
    https://github.com/klausbetz/apple-identity-provider-keycloak/releases/download/${APPLE_IDP_VERSION}/apple-identity-provider-${APPLE_IDP_VERSION}.jar \
    /opt/keycloak/providers/apple-identity-provider-${APPLE_IDP_VERSION}.jar

RUN /opt/keycloak/bin/kc.sh build --db=postgres --http-relative-path=/auth --health-enabled=true --metrics-enabled=true --vault=file

# --- runtime ------------------------------------------------------------------------------
FROM ${KEYCLOAK_IMAGE} AS runtime
ARG GIT_SHA=unknown
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.title="web-app-test keycloak" \
      org.opencontainers.image.description="Keycloak 26.7 with the Apple identity provider extension, optimized build" \
      org.opencontainers.image.source="https://github.com/akshatauppinventure/web-app-test" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="quay.io/keycloak/keycloak:26.7.3"

COPY --from=builder --chown=keycloak:keycloak /opt/keycloak/ /opt/keycloak/
# Realm definition (no secrets: placeholders resolve from env / the file vault at runtime).
COPY --chown=keycloak:keycloak realms/app-realm.json /opt/keycloak/data/import/app-realm.json
COPY --chown=keycloak:keycloak password-blacklists/ /opt/keycloak/data/password-blacklists/
COPY --chown=keycloak:keycloak --chmod=755 scripts/docker-entrypoint.sh /opt/keycloak/bin/docker-entrypoint.sh

# Build-time options (db, relative path, health, metrics, vault) are baked in by `kc.sh build`
# above; only runtime options are set here.
ENV KC_HTTP_ENABLED=true \
    KC_PROXY_HEADERS=xforwarded \
    KC_VAULT_DIR=/run/secrets

USER 1000
EXPOSE 8080 9000
ENTRYPOINT ["/opt/keycloak/bin/docker-entrypoint.sh"]
CMD ["start", "--optimized", "--import-realm"]
