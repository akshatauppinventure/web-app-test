# syntax=docker/dockerfile:1.7
# CrowdSec image with the POC configuration baked in (ADR-0013). The upstream entrypoint rsyncs
# /staging/etc/crowdsec into /etc/crowdsec at start, so files placed there become the config.
ARG CROWDSEC_IMAGE=crowdsecurity/crowdsec:v1.8.1@sha256:0f2523fa61ef507f15d953045cface490cc880670c62f2755ced17524107f71a
FROM ${CROWDSEC_IMAGE}
ARG GIT_SHA=unknown
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.title="web-app-test crowdsec" \
      org.opencontainers.image.description="CrowdSec v1.8 with the POC acquisition, AppSec and profile configuration" \
      org.opencontainers.image.source="https://github.com/akshatauppinventure/web-app-test" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="crowdsecurity/crowdsec:v1.8.1"
COPY acquis.d/ /staging/etc/crowdsec/acquis.d/
COPY config/profiles.yaml /staging/etc/crowdsec/profiles.yaml
COPY parsers/allowlist.yaml /staging/etc/crowdsec/parsers/s02-enrich/poc-allowlist.yaml
COPY appsec/poc-appsec-detect.yaml /staging/etc/crowdsec/appsec-configs/poc-appsec-detect.yaml
# The default acquisition points at a non-existent file; ours live in acquis.d.
RUN rm -f /staging/etc/crowdsec/acquis.yaml
